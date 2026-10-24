import AppKit
import NexusCore

/// Port listing + kill actions, shared by the menu-bar item and the overlay.
enum PortActions {
    static func kill(_ p: ListeningPort, signal: Int32 = SIGTERM) {
        if Foundation.kill(p.pid, signal) != 0 {
            let reason = errno == EPERM ? "Not permitted. The process belongs to another user (e.g. root)." : String(cString: strerror(errno))
            alert("Couldn't kill \(p.name) (PID \(p.pid))", reason)
        }
    }

    /// Every process with this name. Never Nexus itself.
    static func killAll(_ p: ListeningPort) {
        guard p.name != "Nexus", p.pid != ProcessInfo.processInfo.processIdentifier else {
            alert("Not killing Nexus", "Killall skips Nexus itself."); return
        }
        if Settings.shared.data.portsConfirmKillall {
            let a = NSAlert()
            a.messageText = "Kill all “\(p.name)” processes?"
            a.informativeText = "This sends SIGTERM to every process named \(p.name), not just PID \(p.pid)."
            a.addButton(withTitle: "Killall")
            a.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [p.name]
        let err = Pipe()
        task.standardError = err
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            alert("Killall \(p.name) failed", msg.isEmpty ? "Exit status \(task.terminationStatus)" : msg)
        }
    }

    static func copyPort(_ p: ListeningPort) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(p.port), forType: .string)
    }

    static func openInBrowser(_ p: ListeningPort) {
        if let u = URL(string: "http://localhost:\(p.port)") { NSWorkspace.shared.open(u) }
    }

    static func visiblePorts() -> [ListeningPort] {
        let all = PortScanner.scan()
        return Settings.shared.data.portsHideRoot ? all.filter { $0.uid != 0 } : all
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

/// Menu-bar item: `port · name` rows; hovering a row opens Kill / Killall with the PID.
final class PortsMenu: NSObject, NSMenuDelegate {
    static let shared = PortsMenu()
    private var statusItem: NSStatusItem?
    private var keep: [MenuAction] = []

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Open Ports")
        item.button?.toolTip = "Open Ports"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        keep.removeAll()
        menu.addHeader("Open Ports")
        let ports = PortActions.visiblePorts()
        if ports.isEmpty { menu.addHeader("No listening ports") }
        for p in ports {
            let row = NSMenuItem(title: "\(p.port) · \(p.name)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addHeader(p.name)
            sub.add("Kill Process (PID \(p.pid))", keep: &keep) { PortActions.kill(p) }
            sub.add("Killall Process (PID \(p.pid))", keep: &keep) { PortActions.killAll(p) }
            sub.addItem(.separator())
            sub.add("Force Kill (PID \(p.pid))", keep: &keep) { PortActions.kill(p, signal: SIGKILL) }
            sub.add("Copy Port", keep: &keep) { PortActions.copyPort(p) }
            sub.add("Open localhost:\(p.port)", keep: &keep) { PortActions.openInBrowser(p) }
            row.submenu = sub
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.add("Refresh", keep: &keep) { }
    }
}
