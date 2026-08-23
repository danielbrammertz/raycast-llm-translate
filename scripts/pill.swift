// llm-pill — bottom-of-screen pill overlay that WRAPS long text (Raycast toasts/HUDs are
// single-line). Reads the text from stdin, duration in seconds as argv[1] (default 6).
// Borderless and non-activating (never steals focus). A thin line along the bottom edge
// drains as a countdown; hovering pauses it (the pill stays while the cursor is on it);
// moving the cursor away resumes the remaining countdown, then it fades out.
//
// Note: clicks are NOT handled on purpose. A non-activating panel never becomes key, and
// macOS only delivers mouseDown to such windows when a view opts in via acceptsFirstMouse —
// a click-to-pin variant would need that override. Hover-pause covers the "keep it" need.
import AppKit

let cliArgs = CommandLine.arguments
let duration = cliArgs.count > 1 ? (Double(cliArgs[1]) ?? 6.0) : 6.0

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard var text = String(data: stdinData, encoding: .utf8)?
  .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
else { exit(0) }
if text.count > 4000 { text = String(text.prefix(4000)) + "…" }

func pauseLayer(_ layer: CALayer) {
  let t = layer.convertTime(CACurrentMediaTime(), from: nil)
  layer.speed = 0
  layer.timeOffset = t
}

func resumeLayer(_ layer: CALayer) {
  let paused = layer.timeOffset
  layer.speed = 1
  layer.timeOffset = 0
  layer.beginTime = 0
  layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
}

final class PillView: NSVisualEffectView {
  var closing = false
  var remaining: TimeInterval = 6
  var startedAt = Date()
  var closeItem: DispatchWorkItem?
  var progressLayer: CALayer?
  weak var pillPanel: NSPanel?

  func startCountdown(width: CGFloat) {
    let bar = CALayer()
    bar.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
    bar.anchorPoint = CGPoint(x: 0, y: 0.5)
    bar.bounds = CGRect(x: 0, y: 0, width: width, height: 3)
    bar.position = CGPoint(x: 0, y: 1.5)
    layer?.addSublayer(bar)
    progressLayer = bar

    let anim = CABasicAnimation(keyPath: "bounds.size.width")
    anim.fromValue = width
    anim.toValue = 0
    anim.duration = remaining
    anim.timingFunction = CAMediaTimingFunction(name: .linear)
    anim.fillMode = .forwards
    anim.isRemovedOnCompletion = false
    bar.add(anim, forKey: "countdown")

    scheduleClose()
  }

  func scheduleClose() {
    startedAt = Date()
    let item = DispatchWorkItem { [weak self] in self?.beginClose() }
    closeItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: item)
  }

  func pauseCountdown() {
    guard !closing else { return }
    closeItem?.cancel()
    remaining = max(0.8, remaining - Date().timeIntervalSince(startedAt))
    if let bar = progressLayer { pauseLayer(bar) }
  }

  func resumeCountdown() {
    guard !closing else { return }
    if let bar = progressLayer { resumeLayer(bar) }
    scheduleClose()
  }

  func beginClose() {
    guard !closing else { return }
    closing = true
    closeItem?.cancel()
    guard let panel = pillPanel else { NSApp.terminate(nil); return }
    NSAnimationContext.runAnimationGroup(
      { ctx in
        ctx.duration = 0.35
        panel.animator().alphaValue = 0
      },
      completionHandler: { NSApp.terminate(nil) })
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) { pauseCountdown() }
  override func mouseExited(with event: NSEvent) { resumeCountdown() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// show on the screen the mouse is on — that's where the user is working
let mouse = NSEvent.mouseLocation
let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
  ?? NSScreen.main ?? NSScreen.screens[0]
let vis = screen.visibleFrame

let font = NSFont.systemFont(ofSize: 15, weight: .medium)
let hPad: CGFloat = 20
let vPad: CGFloat = 14
let maxTextW = min(vis.width * 0.55, 760)
let maxTextH = vis.height * 0.5

let label = NSTextField(wrappingLabelWithString: text)
label.font = font
label.textColor = .white
label.alignment = (text.contains("\n") || text.count > 120) ? .left : .center
label.lineBreakMode = .byWordWrapping
label.cell?.truncatesLastVisibleLine = true

// Width estimate from a plain measurement, THEN let the field's own cell compute the
// height it really needs at that width — boundingRect ignores the cell's internal
// padding and leading, which re-wraps lines and used to truncate the last ones.
let measured = (text as NSString).boundingRect(
  with: NSSize(width: maxTextW, height: .greatestFiniteMagnitude),
  options: [.usesLineFragmentOrigin, .usesFontLeading],
  attributes: [.font: font])
let textW = min(ceil(measured.width) + 8, maxTextW)
let needed = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 100_000))
  ?? NSSize(width: textW, height: measured.height * 1.2)
let textH = min(ceil(needed.height) + 4, maxTextH)
let winW = textW + 2 * hPad
let winH = textH + 2 * vPad

let panel = NSPanel(
  contentRect: NSRect(x: vis.midX - winW / 2, y: vis.minY + 120, width: winW, height: winH),
  styleMask: [.borderless, .nonactivatingPanel],
  backing: .buffered, defer: false)
panel.level = .statusBar
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = false // required for hover tracking (pauses the countdown)
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.appearance = NSAppearance(named: .vibrantDark)

let effect = PillView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
effect.material = .hudWindow
effect.blendingMode = .behindWindow
effect.state = .active
effect.wantsLayer = true
effect.layer?.cornerRadius = 14
effect.layer?.masksToBounds = true
effect.remaining = duration
effect.pillPanel = panel

label.frame = NSRect(x: hPad, y: vPad, width: textW, height: textH)
effect.addSubview(label)
panel.contentView = effect

panel.alphaValue = 0
panel.orderFrontRegardless()

NSAnimationContext.runAnimationGroup { ctx in
  ctx.duration = 0.18
  panel.animator().alphaValue = 1
}
effect.startCountdown(width: winW)

app.run()
