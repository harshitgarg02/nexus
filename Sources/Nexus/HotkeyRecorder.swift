import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click, press a combo. Uses a local event monitor that consumes events, so combos that app menus or
/// the system would normally claim first (⌘⇧V, ⌘⇧S, ⌃V…) still reach us. Nexus's own global hotkeys
/// are suspended while recording so they don't swallow the keypress.
final class RecorderNSView: NSView {
    var binding = KeyBinding.none { didSet { needsDisplay = true } }
    var onCapture: (KeyBinding?) -> Void = { _ in } // nil = reset to default
    private var monitor: Any?
    private var liveMods: NSEvent.ModifierFlags = []
    private(set) var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 28) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); start() }
    override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { stop() } }
    deinit { stop() }

    private func start() {
        guard !recording else { return }
        recording = true
        liveMods = []
        Hotkey.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self, self.recording else { return e }
            return self.handle(e) ? nil : e
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording { recording = false; Hotkey.resume() }
    }

    private func handle(_ e: NSEvent) -> Bool {
        if e.type == .flagsChanged {
            liveMods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            needsDisplay = true
            return true
        }
        let mods = KeyBinding.carbonModifiers(e.modifierFlags)
        let code = Int(e.keyCode)
        if mods == 0 {
            if code == kVK_Escape { stop(); return true }
            if code == kVK_Delete || code == kVK_ForwardDelete { finish(.none); return true }
        }
        let b = KeyBinding(keyCode: code, modifiers: mods, label: KeyBinding.label(for: e))
        if mods == 0 && !b.isFunctionKey { NSSound.beep(); return true } // need a modifier
        finish(b)
        return true
    }

    private func finish(_ b: KeyBinding) {
        stop()
        window?.makeFirstResponder(nil)
        onCapture(b)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.07)).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.2)).setStroke()
        path.lineWidth = 1
        path.stroke()

        var text = binding.display
        var color = binding.isNone ? NSColor.secondaryLabelColor : NSColor.labelColor
        if recording {
            var s = ""
            if liveMods.contains(.control) { s += "⌃" }
            if liveMods.contains(.option) { s += "⌥" }
            if liveMods.contains(.shift) { s += "⇧" }
            if liveMods.contains(.command) { s += "⌘" }
            text = s.isEmpty ? "Press shortcut…" : s
            color = .secondaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    let binding: KeyBinding
    let onCapture: (KeyBinding?) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let v = RecorderNSView()
        v.binding = binding
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ v: RecorderNSView, context: Context) {
        v.binding = binding
        v.onCapture = onCapture
    }
}
