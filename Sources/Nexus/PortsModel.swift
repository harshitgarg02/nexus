import AppKit
import NexusCore

final class PortsModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; applyFilter() } }
    @Published private(set) var items: [ListeningPort] = []
    @Published var selection = 0
    @Published var focusTick = 0
    var dismiss: () -> Void = {}
    private var all: [ListeningPort] = []

    var selected: ListeningPort? { items.indices.contains(selection) ? items[selection] : nil }
    /// ↵ is deliberately harmless. Killing is one step away in ⌘K.
    var primaryLabel: String { selected.map { "Copy Port \($0.port)" } ?? "Copy Port" }

    func copySelectedPort() {
        guard let p = selected else { return }
        PortActions.copyPort(p)
        dismiss()
    }

    func open() {
        query = ""
        selection = 0
        refresh()
        focusTick += 1
    }

    func refresh() {
        all = PortActions.visiblePorts()
        applyFilter()
    }

    private func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        items = q.isEmpty ? all : all.filter { String($0.port).contains(q) || $0.name.lowercased().contains(q) || String($0.pid).contains(q) }
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    private func afterKill() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func killSelected(signal: Int32 = SIGTERM) {
        guard let p = selected else { return }
        PortActions.kill(p, signal: signal)
        afterKill()
    }

    var actions: [ActionItem] {
        guard let p = selected else { return [] }
        return [
            ActionItem(title: "Copy Port \(p.port)", symbol: "doc.on.doc", run: { PortActions.copyPort(p) }),
            ActionItem(title: "Kill Process (PID \(p.pid))", symbol: "xmark.octagon", keepsOpen: true, run: { [self] in killSelected() }),
            ActionItem(title: "Killall Process (PID \(p.pid))", symbol: "xmark.octagon.fill", destructive: true, keepsOpen: true,
                       run: { [self] in PortActions.killAll(p); afterKill() }),
            ActionItem(title: "Force Kill (PID \(p.pid))", symbol: "bolt.slash", destructive: true, keepsOpen: true,
                       run: { [self] in killSelected(signal: SIGKILL) }),
            ActionItem(title: "Open localhost:\(p.port)", symbol: "safari", run: { PortActions.openInBrowser(p) }),
            ActionItem(title: "Refresh", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in refresh() }),
        ]
    }
}
