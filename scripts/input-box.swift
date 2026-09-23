// llm-input — bottom-of-screen native text prompt, the entry point for commands that need a
// typed term instead of a text selection (e.g. Dictionary Lookup). Same visual language as
// pill.swift (font, HUD blur, corner radius, screen position) so the prompt and the result pill
// read as one continuous native surface, not a Raycast window plus a separate overlay.
//
// Placeholder text is argv[1]. On Return, writes the typed text to stdout and exits 0. On
// Escape, or if the panel loses key focus (user clicked away), exits 1 with no output — the
// caller reads either as "cancelled". Unlike the pill, this panel DOES become key (it must, to
// receive keystrokes), so it uses a plain borderless style rather than a non-activating one.
import AppKit

let cliArgs = CommandLine.arguments
let placeholder = cliArgs.count > 1 ? cliArgs[1] : "Type here…"

final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

func writeAndExit(_ text: String?) -> Never {
  if let text, !text.isEmpty {
    FileHandle.standardOutput.write((text + "\n").data(using: .utf8)!)
    exit(0)
  }
  exit(1)
}

final class Delegate: NSObject, NSWindowDelegate, NSTextFieldDelegate {
  weak var panel: NSPanel?
  var dismissed = false

  func dismiss(result text: String?) {
    guard !dismissed else { return }
    dismissed = true
    guard let p = panel else { writeAndExit(text) }
    NSAnimationContext.runAnimationGroup(
      { ctx in
        ctx.duration = 0.12
        p.animator().alphaValue = 0
      },
      completionHandler: { writeAndExit(text) })
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.insertNewline(_:)) {
      dismiss(result: textView.string)
      return true
    }
    if selector == #selector(NSResponder.cancelOperation(_:)) {
      dismiss(result: nil)
      return true
    }
    return false
  }

  func windowDidResignKey(_ notification: Notification) { dismiss(result: nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Cmd+V/C/X/A are dispatched via the menu bar's key-equivalent matching — with no menu at
// all (no nib/storyboard here), AppKit has nothing to route them to, so they're silently
// swallowed even though the field itself supports paste:/copy:/cut:/selectAll: natively.
let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu
let mainMenu = NSMenu()
mainMenu.addItem(editMenuItem)
app.mainMenu = mainMenu

// show on the screen the mouse is on — matches pill.swift, and keeps the prompt and the
// result pill that follows it in the same place.
let mouse = NSEvent.mouseLocation
let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
  ?? NSScreen.main ?? NSScreen.screens[0]
let vis = screen.visibleFrame

let font = NSFont.systemFont(ofSize: 15, weight: .medium)
let hPad: CGFloat = 20
let vPad: CGFloat = 14
let winW: CGFloat = 460
let fieldH: CGFloat = 22
let winH = fieldH + 2 * vPad

let panel = KeyablePanel(
  contentRect: NSRect(x: vis.midX - winW / 2, y: vis.minY + 120, width: winW, height: winH),
  styleMask: [.borderless],
  backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.appearance = NSAppearance(named: .vibrantDark)

let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
effect.material = .hudWindow
effect.blendingMode = .behindWindow
effect.state = .active
effect.wantsLayer = true
effect.layer?.cornerRadius = 14
effect.layer?.masksToBounds = true

let field = NSTextField(frame: NSRect(x: hPad, y: vPad, width: winW - 2 * hPad, height: fieldH))
field.font = font
field.textColor = .white
field.backgroundColor = .clear
field.isBordered = false
field.focusRingType = .none
field.placeholderString = placeholder
field.usesSingleLineMode = true
field.lineBreakMode = .byTruncatingTail

let delegate = Delegate()
delegate.panel = panel
field.delegate = delegate
panel.delegate = delegate

effect.addSubview(field)
panel.contentView = effect

panel.alphaValue = 0
app.activate(ignoringOtherApps: true)
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(field)

NSAnimationContext.runAnimationGroup { ctx in
  ctx.duration = 0.15
  panel.animator().alphaValue = 1
}

app.run()
