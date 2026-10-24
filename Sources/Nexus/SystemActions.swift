import AppKit
import ApplicationServices

/// One-shot system commands exposed in the overlay.
enum SystemActions {
    // MARK: sleep / lock

    static func sleepMac() { run("/usr/bin/pmset", ["sleepnow"]) }
    static func sleepDisplay() { run("/usr/bin/pmset", ["displaysleepnow"]) }

    /// ⌃⌘Q, the system's lock shortcut. Needs Accessibility (same grant as pasting); otherwise sleeps the display,
    /// which locks immediately when "Require password" is set to immediately.
    static func lockScreen() {
        guard AXIsProcessTrusted() else { sleepDisplay(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: down)
                e?.flags = [.maskControl, .maskCommand]
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: Finder / appearance (AppleScript; macOS asks for Automation permission the first time)

    static func emptyTrash() {
        guard confirm("Empty the Trash?", "Items in the Trash will be permanently deleted. This can't be undone.", button: "Empty Trash") else { return }
        if let err = script(#"tell application "Finder" to empty trash"#) { alert("Couldn't empty the Trash", err) }
    }

    static func toggleDarkMode() {
        let src = #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        if let err = script(src) { alert("Couldn't toggle dark mode", err) }
    }

    // MARK: Nexus itself

    static func restartNexus() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: network

    /// Asks api.ipify.org for your public IP (a plain GET: the only thing sent is that request itself),
    /// copies it, and shows it. Runs only when you pick the command.
    static func lookUpPublicIP() {
        var req = URLRequest(url: URL(string: "https://api.ipify.org")!)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, error in
            let ip = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let ip, !ip.isEmpty, ip.count < 64, !ip.contains("<") else {
                    alert("Couldn't look up your public IP", error?.localizedDescription ?? "Unexpected response."); return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
                alert("Your public IP is \(ip)", "Copied to the clipboard. Looked up via api.ipify.org.")
            }
        }.resume()
    }

    // MARK: helpers

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); return true } catch { return false }
    }

    /// Nil on success, else the AppleScript error text.
    private static func script(_ source: String) -> String? {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        guard let err else { return nil }
        let msg = err[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        let num = err[NSAppleScript.errorNumber] as? Int
        return num == -1743 ? "Nexus isn't allowed to control that app. Allow it in System Settings → Privacy & Security → Automation." : msg
    }

    private static func confirm(_ title: String, _ text: String, button: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
