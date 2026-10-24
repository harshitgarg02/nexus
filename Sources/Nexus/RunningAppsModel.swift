import AppKit

final class RunningAppsModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; applyFilter() } }
    @Published private(set) var items: [NSRunningApplication] = []
    @Published var selection = 0
    @Published var focusTick = 0
    /// Force Quit command: ↵ force-quits instead of asking nicely.
    private(set) var forceDefault = false
    private var all: [NSRunningApplication] = []

    var selected: NSRunningApplication? { items.indices.contains(selection) ? items[selection] : nil }
    var title: String { forceDefault ? "Force Quit Application" : "Quit Application" }
    var primaryLabel: String {
        guard let a = selected else { return forceDefault ? "Force Quit" : "Quit" }
        return (forceDefault ? "Force Quit " : "Quit ") + (a.localizedName ?? "App")
    }

    func open(force: Bool) {
        forceDefault = force
        query = ""
        selection = 0
        refresh()
        focusTick += 1
    }

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        all = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        applyFilter()
    }

    private func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        items = q.isEmpty ? all : all.filter { ($0.localizedName ?? "").lowercased().contains(q) }
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.refresh() }
    }

    func quit() { selected?.terminate(); refreshSoon() }
    func forceQuit() { selected?.forceTerminate(); refreshSoon() }
    func primary() { forceDefault ? forceQuit() : quit() }

    /// Quit, then reopen once it has actually exited (gives up after 6 s, e.g. if it's waiting on a save dialog).
    func restart() {
        guard let a = selected, let url = a.bundleURL else { return }
        a.terminate()
        var tries = 0
        func poll() {
            tries += 1
            if a.isTerminated { NSWorkspace.shared.openApplication(at: url, configuration: .init()); refreshSoon(); return }
            if tries < 24 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { poll() } }
        }
        poll()
    }

    var actions: [ActionItem] {
        guard let a = selected else { return [] }
        let n = a.localizedName ?? "App"
        var out = [
            ActionItem(title: "Quit \(n)", symbol: "xmark.circle", keepsOpen: true, run: { [self] in quit() }),
            ActionItem(title: "Force Quit \(n)", symbol: "bolt.slash", destructive: true, keepsOpen: true, run: { [self] in forceQuit() }),
            ActionItem(title: "Restart \(n)", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in restart() }),
        ]
        if forceDefault { out.swapAt(0, 1) }
        if let url = a.bundleURL {
            out.append(ActionItem(title: "Show in Finder", symbol: "folder", run: { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
        }
        return out
    }
}
