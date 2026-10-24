import AppKit
import SwiftUI
import Combine

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Arrow/return/esc when no text field has focus (e.g. after clicking a row or the preview).
    var onNavKey: ((NavKey) -> Void)?
    /// Asks the current screen to focus its text field (a plain character was typed with no field focused).
    var onTypedWithoutFocus: (() -> Void)?
    private var replayed: NSEvent?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onNavKey?(.up)
        case 125: onNavKey?(.down)
        case 36, 76: onNavKey?(.enter)
        case 53: onNavKey?(.escape)
        default:
            // A letter arrived but no text field has focus (e.g. after clicking a row): focus the field and replay
            // the keystroke once so it isn't lost.
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            if mods.isEmpty, replayed !== event, let c = event.characters, !c.isEmpty, c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }) {
                replayed = event
                onTypedWithoutFocus?()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.replayed = event
                    NSApp.postEvent(event, atStart: true)
                }
            } else { super.keyDown(with: event) }
        }
    }

    /// Accessory app + non-activating panel has no Edit menu in play, so route ⌘A/C/X/V/Z ourselves.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        var action: Selector?
        switch (flags, key) {
        case ([.command], "n"):
            NotificationCenter.default.post(name: OverlayController.newItemNotification, object: nil)
            return true
        case ([.command], "k"):
            NotificationCenter.default.post(name: OverlayController.toggleActionsNotification, object: nil)
            return true
        case ([.command], ","):
            NotificationCenter.default.post(name: OverlayController.openSettingsNotification, object: nil)
            return true
        case ([.command], "a"): action = #selector(NSText.selectAll(_:))
        case ([.command], "c"): action = #selector(NSText.copy(_:))
        case ([.command], "x"): action = #selector(NSText.cut(_:))
        case ([.command], "v"): action = #selector(NSText.paste(_:))
        case ([.command], "z"): action = Selector(("undo:"))
        case ([.command, .shift], "z"): action = Selector(("redo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the pre-created overlay panel; show/hide only, so hotkey -> first frame stays fast.
final class OverlayController {
    static let openSettingsNotification = Notification.Name("NexusOpenSettings")
    /// Set while the system auth sheet is up, so losing key focus doesn't dismiss the overlay.
    static var suppressAutoHide = false
    /// Benchmark mode: show the panel fully transparent so it can be measured without flashing on screen.
    static var silent = false
    static let newItemNotification = Notification.Name("NexusNewItem")
    static let toggleActionsNotification = Notification.Name("NexusToggleActions")
    static let size = NSSize(width: 760, height: 480)
    let model = SearchModel()
    private let panel: OverlayPanel
    private let tint = NSView()
    private var tintObserver: AnyCancellable?

    init() {
        panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        // maskImage (not layer masking) so the window shadow follows the rounded shape.
        blur.maskImage = Self.roundedMask(radius: 20)
        blur.layer?.cornerRadius = 20
        blur.layer?.cornerCurve = .continuous
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        // Dark tint between the blur and the content keeps the panel readable over light windows.
        tint.wantsLayer = true
        tint.frame = blur.bounds
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)
        applyTint()
        tintObserver = Settings.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.applyTint() }

        let host = NSHostingView(rootView: LauncherView(model: model))
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        panel.contentView = blur

        model.dismiss = { [weak self] in self?.hide() }
        panel.onNavKey = { [weak self] k in self?.model.key(k) }
        panel.onTypedWithoutFocus = { [weak self] in self?.model.refocus() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            if !Self.suppressAutoHide { self?.hide() }
        }
    }

    private func applyTint() {
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(Settings.shared.data.overlayTintAlpha).cgColor
    }

    private static func roundedMask(radius r: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(_ start: SearchModel.Mode = .root) {
        if isVisible && model.mode == start { hide() } else { show(start) }
    }

    func show(_ start: SearchModel.Mode = .root) {
        if !LatencyMeter.isRunning { LatencyMeter.begin() }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let x = f.midX - Self.size.width / 2
            let y = f.maxY - Self.size.height - f.height * 0.18
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        // Capture the app to paste into before we take key focus (panel is non-activating, so it's still frontmost).
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        model.clipboard.targetApp = target
        model.snippets.targetApp = target
        model.totp.targetApp = target
        model.script.targetApp = target
        model.transform.targetApp = target
        ScriptIndex.shared.reload() // pick up scripts added or edited since the last open
        model.reset(start: start)
        LatencyMeter.lap("model")
        panel.alphaValue = Self.silent ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        LatencyMeter.lap("order")
        panel.displayIfNeeded() // force layout + draw now so the measurement includes it
        CATransaction.flush()
        LatencyMeter.end()
    }

    func hide() {
        LatencyMeter.cancel()
        panel.orderOut(nil)
        model.totp.clearSecrets()
    }
}
