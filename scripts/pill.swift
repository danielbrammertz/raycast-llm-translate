// llm-pill — bottom-of-screen pill overlay that WRAPS long text (Raycast toasts/HUDs are
// single-line). Reads the text from stdin, duration in seconds as argv[1] (default 6).
// Borderless, non-activating (never steals focus), click-through, fades in/out, auto-quits.
import AppKit

let cliArgs = CommandLine.arguments
let duration = cliArgs.count > 1 ? (Double(cliArgs[1]) ?? 6.0) : 6.0

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard var text = String(data: stdinData, encoding: .utf8)?
  .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
else { exit(0) }
if text.count > 4000 { text = String(text.prefix(4000)) + "…" }

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

let measured = (text as NSString).boundingRect(
  with: NSSize(width: maxTextW, height: .greatestFiniteMagnitude),
  options: [.usesLineFragmentOrigin, .usesFontLeading],
  attributes: [.font: font])
let textW = min(ceil(measured.width) + 2, maxTextW)
let textH = min(ceil(measured.height) + 2, maxTextH)
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
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.appearance = NSAppearance(named: .vibrantDark)

let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
effect.material = .hudWindow
effect.blendingMode = .behindWindow
effect.state = .active
effect.wantsLayer = true
effect.layer?.cornerRadius = 14
effect.layer?.masksToBounds = true

let label = NSTextField(wrappingLabelWithString: text)
label.font = font
label.textColor = .white
label.alignment = (text.contains("\n") || text.count > 120) ? .left : .center
label.lineBreakMode = .byWordWrapping
label.cell?.truncatesLastVisibleLine = true
label.frame = NSRect(x: hPad, y: vPad, width: textW, height: textH)
effect.addSubview(label)
panel.contentView = effect

panel.alphaValue = 0
panel.orderFrontRegardless()

NSAnimationContext.runAnimationGroup { ctx in
  ctx.duration = 0.18
  panel.animator().alphaValue = 1
}

DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
  NSAnimationContext.runAnimationGroup(
    { ctx in
      ctx.duration = 0.35
      panel.animator().alphaValue = 0
    },
    completionHandler: { app.terminate(nil) })
}
// hard safety exit in case animations/run loop wedge
DispatchQueue.main.asyncAfter(deadline: .now() + duration + 3) { exit(0) }

app.run()
