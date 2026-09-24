// llm-pill — bottom-of-screen pill overlay. Two modes, same binary:
//
// Simple mode (default): reads plain text from stdin, WRAPS it (Raycast toasts/HUDs are
// single-line), duration in seconds as argv[1] (default 6).
//
// Split mode (--split as an argv flag): reads a JSON payload from stdin (SplitPayload) and shows
// the original text on top (smaller, selectable) and the translation on the bottom. Double-click
// or drag-select a word/phrase in the top text to swap the bottom area to an elaborate
// explanation of it — the explanation call is made by THIS process directly via URLSession, not
// routed back through the Raycast command (which already exited after spawning this).
// Deselecting reverts the bottom back to the translation.
//
// Both modes: borderless and non-activating (never steals focus). A thin line along the bottom
// edge drains as a countdown; hovering pauses it (the pill stays while the cursor is on it) —
// in split mode, having an active (non-empty) selection also pauses it, so it doesn't vanish
// while you're reading an explanation with the cursor elsewhere. A small close button in the
// top-right corner dismisses it immediately.
//
// Note: the pill body itself still doesn't handle clicks — a non-activating panel never becomes
// key, and macOS only delivers mouseDown to views that opt in via acceptsFirstMouse. CloseButton
// and (in split mode) the selectable source text view both opt in, scoped to those views, so the
// rest of the pill stays click-through and the panel never steals focus.
import AppKit

let cliArgs = CommandLine.arguments
let isSplit = cliArgs.contains("--split")
let duration = cliArgs.count > 1 ? (Double(cliArgs[1]) ?? 6.0) : 6.0

// Nothing else holds a strong reference to the split controller (NSTextView.delegate is weak,
// by Cocoa convention) — without this, it would be deallocated the moment execution leaves the
// `if isSplit` block below, before app.run() even starts.
var splitControllerKeepAlive: SplitController?

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
  var paused = false
  var isHovering = false
  var hasSelection = false // split mode only — an active selection also keeps the pill up
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

  /// Pause when hovering OR (split mode) there's an active selection; resume only when neither
  /// holds. Both mouse events and selection-change events funnel through this, so pausing twice
  /// in a row (e.g. hover while already selection-paused) can't double-subtract `remaining`.
  func updatePauseState() {
    if isHovering || hasSelection { pauseCountdown() } else { resumeCountdown() }
  }

  func pauseCountdown() {
    guard !closing, !paused else { return }
    paused = true
    closeItem?.cancel()
    remaining = max(0.8, remaining - Date().timeIntervalSince(startedAt))
    if let bar = progressLayer { pauseLayer(bar) }
  }

  func resumeCountdown() {
    guard !closing, paused else { return }
    paused = false
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

  override func mouseEntered(with event: NSEvent) { isHovering = true; updatePauseState() }
  override func mouseExited(with event: NSEvent) { isHovering = false; updatePauseState() }
}

/// Small top-right close affordance. The only clickable part of the simple pill: opts into
/// acceptsFirstMouse so its click is delivered despite the panel being non-activating.
final class CloseButton: NSImageView {
  var onClick: (() -> Void)?
  let dim = NSColor.white.withAlphaComponent(0.45)
  let bright = NSColor.white.withAlphaComponent(0.95)

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick?() }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) {
    NSCursor.pointingHand.push()
    contentTintColor = bright
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.pop()
    contentTintColor = dim
  }
}

// MARK: - Split mode only

/// The original-text view. Same acceptsFirstMouse story as CloseButton: without this override,
/// a non-activating panel that never becomes key would deliver it zero mouse events, so
/// double-click/drag-select would silently never fire.
final class SelectableSourceTextView: NSTextView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Same acceptsFirstMouse story again, for dragging the bottom area's scrollbar thumb.
final class ClickableScrollView: NSScrollView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SplitPayload: Decodable {
  let originalText: String
  let translation: String
  let primaryLanguage: String
  let secondaryLanguage: String
  let apiKey: String
  let model: String
}

private struct ChatMessage: Encodable { let role: String; let content: String }
private struct ChatRequest: Encodable {
  let model: String
  let temperature: Double
  let max_tokens: Int
  let messages: [ChatMessage]
}
private struct ChatMessageOut: Decodable { let content: String? }
private struct ChatChoice: Decodable { let message: ChatMessageOut }
private struct ChatResponse: Decodable { let choices: [ChatChoice]? }

enum ExplainError: Error { case badStatus(Int), empty }

func explainSystemPrompt(primary: String, secondary: String) -> String {
  "You are helping a \(primary) speaker learn \(secondary) vocabulary. Given a sentence and a " +
  "specific word or phrase from it, write a clear, well-organized explanation in \(primary), " +
  "structured as short labeled sections: its meaning as used in this sentence; other common " +
  "meanings/senses it has; a brief note on its origin or derivation where genuinely interesting " +
  "(skip if not); 2-4 \(primary) translations/equivalents covering its different senses. " +
  "Naturally include the original \(secondary) word/phrase and brief \(secondary) usage examples " +
  "where helpful. Use **bold** only for the short section labels themselves (e.g. " +
  "**Meaning:**); write everything else as plain sentences — no bullet lists, no headings, no " +
  "other markdown. Write only the explanation — no preamble."
}

func fetchExplanation(phrase: String, payload: SplitPayload) async throws -> String {
  let reqBody = ChatRequest(
    model: payload.model, temperature: 0.4, max_tokens: 500,
    messages: [
      ChatMessage(
        role: "system",
        content: explainSystemPrompt(primary: payload.primaryLanguage, secondary: payload.secondaryLanguage)),
      ChatMessage(
        role: "user",
        content: "Sentence: \"\(payload.originalText)\"\nTranslation: \"\(payload.translation)\"\nExplain: \"\(phrase)\""),
    ])
  var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
  request.httpMethod = "POST"
  request.timeoutInterval = 45
  request.setValue("Bearer \(payload.apiKey)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.setValue("https://github.com/danielbrammertz/raycast-llm-translate", forHTTPHeaderField: "HTTP-Referer")
  request.setValue("Raycast LLM Translate", forHTTPHeaderField: "X-Title")
  request.httpBody = try JSONEncoder().encode(reqBody)

  let (data, response) = try await URLSession.shared.data(for: request)
  guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
    throw ExplainError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
  }
  let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
  let text = decoded.choices?.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  guard !text.isEmpty else { throw ExplainError.empty }
  return text
}

/// Owns the split pill's interactive behavior: debounced selection handling, the in-flight
/// explanation lookup (cancelled and replaced if the user selects something else before it
/// lands), and resizing the panel to fit whatever's currently in the bottom area.
final class SplitController: NSObject, NSTextViewDelegate {
  let payload: SplitPayload
  let topView: NSTextView
  let bottomScroll: ClickableScrollView
  let bottomTextView: NSTextView
  let divider: NSView
  let closeBtn: CloseButton
  let panel: NSPanel
  let effect: PillView
  let hPad: CGFloat
  let vPad: CGFloat
  let gapH: CGFloat
  let dividerH: CGFloat
  let closeSize: CGFloat
  let textW: CGFloat
  let topH: CGFloat
  let maxBottomH: CGFloat // available screen space for the bottom area — beyond this, it scrolls
  let font: NSFont

  var debounceItem: DispatchWorkItem?
  var currentTask: Task<Void, Never>?

  init(payload: SplitPayload, topView: NSTextView, bottomScroll: ClickableScrollView,
       bottomTextView: NSTextView, divider: NSView, closeBtn: CloseButton, panel: NSPanel,
       effect: PillView, hPad: CGFloat, vPad: CGFloat, gapH: CGFloat, dividerH: CGFloat,
       closeSize: CGFloat, textW: CGFloat, topH: CGFloat, maxBottomH: CGFloat, font: NSFont) {
    self.payload = payload
    self.topView = topView
    self.bottomScroll = bottomScroll
    self.bottomTextView = bottomTextView
    self.divider = divider
    self.closeBtn = closeBtn
    self.panel = panel
    self.effect = effect
    self.hPad = hPad
    self.vPad = vPad
    self.gapH = gapH
    self.dividerH = dividerH
    self.closeSize = closeSize
    self.textW = textW
    self.topH = topH
    self.maxBottomH = maxBottomH
    self.font = font
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    // Debounced rather than acted on immediately — this fires repeatedly as a drag grows the
    // selected range, and we only want to act once the gesture has settled.
    debounceItem?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.selectionSettled() }
    debounceItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
  }

  private func selectionSettled() {
    let range = topView.selectedRange()
    let phrase = (topView.string as NSString).substring(with: range)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if phrase.isEmpty {
      effect.hasSelection = false
      effect.updatePauseState()
      currentTask?.cancel()
      setBottomContent(payload.translation, animated: true)
    } else {
      effect.hasSelection = true
      effect.updatePauseState()
      startLookup(phrase: phrase)
    }
  }

  private func startLookup(phrase: String) {
    currentTask?.cancel()
    setBottomText(bottomTextView, "Looking up \u{201C}\(phrase)\u{201D}\u{2026}", font: font) // transient — no resize
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await fetchExplanation(phrase: phrase, payload: self.payload)
        guard !Task.isCancelled else { return }
        DispatchQueue.main.async { self.setBottomContent(text, animated: true) }
      } catch {
        guard !Task.isCancelled else { return }
        DispatchQueue.main.async { self.setBottomContent("Could not look that up.", animated: true) }
      }
    }
    currentTask = task
  }

  private func setBottomContent(_ text: String, animated: Bool) {
    setBottomText(bottomTextView, text, font: font)
    relayout(animated: animated)
  }

  /// Resizes everything to fit the current bottom content: as tall as needed, up to the real
  /// available screen space (maxBottomH already accounts for that) — beyond that, the bottom
  /// area scrolls instead of growing further or clipping. The panel's bottom edge (its screen Y
  /// origin) never changes — only its height does — so it stays anchored in place and grows
  /// upward, matching where it was originally placed.
  private func relayout(animated: Bool) {
    let bottomNatural = naturalHeight(bottomTextView, width: textW)
    let bottomVisible = min(bottomNatural, maxBottomH)
    let dividerY = vPad + bottomVisible + gapH
    let topY = dividerY + dividerH + gapH
    let newWinH = topY + topH + vPad
    let newFrame = NSRect(x: panel.frame.minX, y: panel.frame.minY, width: panel.frame.width, height: newWinH)

    let apply = {
      self.bottomTextView.frame = NSRect(x: 0, y: 0, width: self.textW, height: bottomNatural)
      self.bottomScroll.frame = NSRect(x: self.hPad, y: self.vPad, width: self.textW, height: bottomVisible)
      self.divider.frame = NSRect(x: self.hPad, y: dividerY, width: self.textW, height: self.dividerH)
      self.topView.frame = NSRect(x: self.hPad, y: topY, width: self.textW, height: self.topH)
      self.closeBtn.frame.origin.y = newWinH - 8 - self.closeSize
      self.panel.setFrame(newFrame, display: true)
      self.effect.frame = NSRect(x: 0, y: 0, width: newFrame.width, height: newWinH)
    }

    if animated {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        ctx.allowsImplicitAnimation = true
        apply()
      }
    } else {
      apply()
    }
  }
}

/// Width a line of text needs at this font, capped at maxWidth (the same boundingRect technique
/// simple mode already used for its own width estimate).
func measuredWidth(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGFloat {
  let measured = (text as NSString).boundingRect(
    with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    attributes: [.font: font])
  return min(ceil(measured.width) + 8, maxWidth)
}

/// Natural (uncapped) height an NSTextView's content needs at a given width, via real TextKit
/// layout — boundingRect (used for the NSTextField/simple-mode case) isn't reliable here since
/// NSTextView wraps via a different layout path than NSString/NSCell measurement. Uncapped
/// because the bottom area needs its true content height to size its scrollable document view;
/// callers cap the *visible* height separately.
func naturalHeight(_ tv: NSTextView, width: CGFloat) -> CGFloat {
  tv.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
  if let tc = tv.textContainer { tv.layoutManager?.ensureLayout(for: tc) }
  let used = tv.textContainer.map { tv.layoutManager?.usedRect(for: $0).height ?? 20 } ?? 20
  return ceil(used) + 4
}

/// Renders inline Markdown (the explain prompt is told to use **bold** for section labels only)
/// into a styled string, so it doesn't show up as literal asterisks. inlineOnlyPreservingWhitespace
/// keeps line breaks exactly as given rather than reflowing into markdown "paragraphs" — the model
/// separates sections with blank lines and that spacing should survive as-is. Falls back to plain
/// text if parsing fails for any reason (malformed input shouldn't ever produce an empty pill).
func renderMarkdown(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
  var options = AttributedString.MarkdownParsingOptions()
  options.interpretedSyntax = .inlineOnlyPreservingWhitespace
  guard var parsed = try? AttributedString(markdown: text, options: options) else {
    return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
  }
  // NSFontManager.shared.convert(_:toHaveTrait:.boldFontMask) silently no-ops on the modern
  // system font (confirmed empirically) — asking for the system font at bold weight directly
  // is the reliable way to get an actually-bold variant.
  let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
  for run in parsed.runs {
    let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
    parsed[run.range].font = isBold ? boldFont : font
    parsed[run.range].foregroundColor = color
  }
  return NSAttributedString(parsed)
}

func setBottomText(_ tv: NSTextView, _ text: String, font: NSFont) {
  tv.textStorage?.setAttributedString(renderMarkdown(text, font: font, color: .white))
}

// MARK: - Shared setup

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
let closeSize: CGFloat = 14
let closeGutter: CGFloat = 24 // extra width reserved on the right for the close button
let maxTextW = min(vis.width * 0.55, 760) - closeGutter
let maxTextH = vis.height * 0.5

func makePanel(rect: NSRect) -> NSPanel {
  let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.level = .statusBar
  panel.isOpaque = false
  panel.backgroundColor = .clear
  panel.hasShadow = true
  panel.ignoresMouseEvents = false // required for hover tracking (pauses the countdown)
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  panel.appearance = NSAppearance(named: .vibrantDark)
  return panel
}

func makeEffect(frame: NSRect) -> PillView {
  let effect = PillView(frame: frame)
  effect.material = .hudWindow
  effect.blendingMode = .behindWindow
  effect.state = .active
  effect.wantsLayer = true
  effect.layer?.cornerRadius = 14
  effect.layer?.masksToBounds = true
  return effect
}

func showPanel(_ panel: NSPanel, effect: PillView, winW: CGFloat) {
  panel.contentView = effect
  panel.alphaValue = 0
  panel.orderFrontRegardless()
  NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.18
    panel.animator().alphaValue = 1
  }
  effect.startCountdown(width: winW)
}

if isSplit {
  let stdinData = FileHandle.standardInput.readDataToEndOfFile()
  guard let payload = try? JSONDecoder().decode(SplitPayload.self, from: stdinData) else { exit(0) }

  let topFont = NSFont.systemFont(ofSize: 12, weight: .regular)
  let gapH: CGFloat = 10
  let dividerH: CGFloat = 1
  let topMaxH: CGFloat = 90 // roughly 4-5 lines — the original text is usually one sentence

  let topWidth = measuredWidth(payload.originalText, font: topFont, maxWidth: maxTextW)
  let bottomWidth = measuredWidth(payload.translation, font: font, maxWidth: maxTextW)
  let textW = max(topWidth, bottomWidth)

  let topView = SelectableSourceTextView(frame: NSRect(x: 0, y: 0, width: textW, height: topMaxH))
  topView.isRichText = false
  topView.isEditable = false
  topView.isSelectable = true
  topView.drawsBackground = false
  topView.textContainerInset = .zero
  topView.textContainer?.lineFragmentPadding = 0
  topView.font = topFont
  topView.textColor = NSColor.white.withAlphaComponent(0.7)
  topView.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.25)]
  topView.string = payload.originalText
  let topH = min(naturalHeight(topView, width: textW), topMaxH)

  // Available height budget: anchored at vis.minY + 120 (fixed, same as simple mode), grow
  // upward up to screenTopMargin below the top of the screen. maxBottomH is whatever's left
  // after the fixed top area, divider, and padding — the true ceiling before the bottom area
  // needs to scroll instead of growing further.
  let screenTopMargin: CGFloat = 40
  let availableWinH = vis.maxY - screenTopMargin - (vis.minY + 120)
  let maxBottomH = availableWinH - topH - vPad - gapH - dividerH - gapH - vPad

  let bottomTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: textW, height: 20))
  bottomTextView.isRichText = false
  bottomTextView.isEditable = false
  bottomTextView.isSelectable = false
  bottomTextView.drawsBackground = false
  bottomTextView.textContainerInset = .zero
  bottomTextView.textContainer?.lineFragmentPadding = 0
  bottomTextView.isVerticallyResizable = true
  bottomTextView.isHorizontallyResizable = false
  bottomTextView.textContainer?.widthTracksTextView = true
  bottomTextView.font = font
  bottomTextView.textColor = .white
  setBottomText(bottomTextView, payload.translation, font: font)
  let bottomNatural = naturalHeight(bottomTextView, width: textW)
  let bottomH = min(bottomNatural, maxBottomH)

  let bottomScroll = ClickableScrollView(frame: .zero)
  bottomScroll.hasVerticalScroller = true
  bottomScroll.hasHorizontalScroller = false
  bottomScroll.autohidesScrollers = true
  bottomScroll.drawsBackground = false
  bottomScroll.borderType = .noBorder
  bottomScroll.documentView = bottomTextView

  let dividerY = vPad + bottomH + gapH
  let topY = dividerY + dividerH + gapH
  let winH = topY + topH + vPad
  let winW = textW + 2 * hPad + closeGutter

  bottomTextView.frame = NSRect(x: 0, y: 0, width: textW, height: bottomNatural)
  bottomScroll.frame = NSRect(x: hPad, y: vPad, width: textW, height: bottomH)
  let divider = NSView(frame: NSRect(x: hPad, y: dividerY, width: textW, height: dividerH))
  divider.wantsLayer = true
  divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
  topView.frame = NSRect(x: hPad, y: topY, width: textW, height: topH)

  let panel = makePanel(rect: NSRect(x: vis.midX - winW / 2, y: vis.minY + 120, width: winW, height: winH))
  let effect = makeEffect(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
  effect.remaining = duration
  effect.pillPanel = panel

  effect.addSubview(topView)
  effect.addSubview(divider)
  effect.addSubview(bottomScroll)

  let closeBtn = CloseButton(frame: NSRect(x: winW - 6 - closeSize, y: winH - 8 - closeSize, width: closeSize, height: closeSize))
  closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
  closeBtn.contentTintColor = closeBtn.dim
  closeBtn.onClick = { [weak effect] in effect?.beginClose() }
  effect.addSubview(closeBtn)

  let controller = SplitController(
    payload: payload, topView: topView, bottomScroll: bottomScroll, bottomTextView: bottomTextView,
    divider: divider, closeBtn: closeBtn, panel: panel, effect: effect, hPad: hPad, vPad: vPad,
    gapH: gapH, dividerH: dividerH, closeSize: closeSize, textW: textW, topH: topH,
    maxBottomH: maxBottomH, font: font)
  topView.delegate = controller
  splitControllerKeepAlive = controller

  showPanel(panel, effect: effect, winW: winW)
} else {
  let stdinData = FileHandle.standardInput.readDataToEndOfFile()
  guard var text = String(data: stdinData, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
  else { exit(0) }
  if text.count > 4000 { text = String(text.prefix(4000)) + "…" }

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
  let winW = textW + 2 * hPad + closeGutter
  let winH = textH + 2 * vPad

  let panel = makePanel(rect: NSRect(x: vis.midX - winW / 2, y: vis.minY + 120, width: winW, height: winH))
  let effect = makeEffect(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
  effect.remaining = duration
  effect.pillPanel = panel

  label.frame = NSRect(x: hPad, y: vPad, width: textW, height: textH)
  effect.addSubview(label)

  let closeBtn = CloseButton(frame: NSRect(x: winW - 6 - closeSize, y: winH - 8 - closeSize, width: closeSize, height: closeSize))
  closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
  closeBtn.contentTintColor = closeBtn.dim
  closeBtn.onClick = { [weak effect] in effect?.beginClose() }
  effect.addSubview(closeBtn)

  showPanel(panel, effect: effect, winW: winW)
}

app.run()
