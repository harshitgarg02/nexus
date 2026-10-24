import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private let settingsWindow = SettingsWindowController()
    /// Actions that currently have a module behind them. Others stay unregistered so they don't steal keys.
    private var handlers: [HotkeyAction: () -> Void] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIndex.shared.reload()
        overlay = OverlayController()
        handlers[.overlay] = { [weak self] in LatencyMeter.begin(); self?.overlay.toggle() }
        handlers[.clipboard] = { [weak self] in LatencyMeter.begin(); self?.overlay.toggle(.clipboard) }
        handlers[.totp] = { [weak self] in LatencyMeter.begin(); self?.overlay.toggle(.totp) }
        handlers[.snippets] = { [weak self] in LatencyMeter.begin(); self?.overlay.toggle(.snippets) }
        ScriptIndex.shared.reload()
        ClipboardService.shared.start()
        CurrencyService.shared.start()
        LegacyMigration.runIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Nexus")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Nexus", action: #selector(showOverlay), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nexus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        PortsMenu.shared.install()
        Caffeinate.shared.installMenuBarItem()

        registerHotkeys()
        if CommandLine.arguments.contains("--bench") { runBenchmark() } else { warmUp() }
        NotificationCenter.default.addObserver(forName: Settings.hotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotkeys()
        }
        NotificationCenter.default.addObserver(forName: OverlayController.openSettingsNotification, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
    }

    private func registerHotkeys() {
        for (action, handler) in handlers {
            let b = Settings.shared.binding(action)
            if b.isNone { Hotkey.unregister(id: action.hotkeyID) }
            else { Hotkey.register(id: action.hotkeyID, keyCode: b.keyCode, modifiers: b.modifiers, handler: handler) }
        }
    }

    /// Render the overlay once, invisibly, so SwiftUI/AppKit/blur setup cost isn't paid on the first hotkey press.
    private func warmUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            OverlayController.silent = true
            for mode in [SearchModel.Mode.root, .clipboard, .snippets] {
                overlay.show(mode)
                overlay.hide()
            }
            OverlayController.silent = false
            LatencyMeter.reset()
        }
    }

    /// `Nexus --bench`: toggles each overlay mode 40x and writes cold/warm open latency to /tmp/nexus-bench.txt, then quits.
    /// Lets us tune without pressing the hotkey by hand.
    private func runBenchmark() {
        OverlayController.silent = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            var lines: [String] = []
            for mode in [SearchModel.Mode.root, .clipboard, .snippets, .totp] {
                LatencyMeter.reset()
                var firstLaps: [(String, Double)]?
                for i in 0..<40 {
                    LatencyMeter.begin()
                    overlay.toggle(mode)
                    if i == 0 { firstLaps = LatencyMeter.lastLaps }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    overlay.hide()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                let s = LatencyMeter.samples
                if let l = firstLaps { lines.append("  cold phases: " + l.map { String(format: "%@ %.0f", $0.0, $0.1) }.joined(separator: " → ")) }
                if let cold = s.first, let warm = LatencyMeter.stats(Array(s.dropFirst())) {
                    lines.append(String(format: "%@: cold %.1f ms | warm mean %.1f p95 %.1f max %.1f (n=%d)",
                                        "\(mode)", cold, warm.mean, warm.p95, warm.max, warm.count))
                }
            }
            try? lines.joined(separator: "\n").appending("\n").write(toFile: "/tmp/nexus-bench.txt", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    @objc private func showOverlay() { overlay.show() }
    @objc private func openSettings() { overlay.hide(); settingsWindow.show() }
}
