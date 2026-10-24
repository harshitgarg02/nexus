import AppKit
import NexusCore

/// Line diff of your two most recent text copies (older → newer).
final class DiffModel: ObservableObject {
    @Published private(set) var rows: [DiffRow] = []
    @Published private(set) var message: String?
    @Published private(set) var stats = (added: 0, removed: 0)
    @Published private(set) var swapped = false
    var dismiss: () -> Void = {}

    private var older = "", newer = ""
    private var lines: [DiffLine] = []

    var primaryLabel: String { lines.isEmpty ? "Close" : "Copy Diff" }
    var direction: String { swapped ? "newer → older" : "older → newer" }

    func open() {
        swapped = false
        let t = ClipboardService.shared.store.recentTexts(limit: 2)
        guard t.count == 2 else {
            message = "Copy two texts first. Nexus compares your last two text copies."
            rows = []; lines = []
            return
        }
        (newer, older) = (t[0], t[1])
        compute()
    }

    func swap() { swapped.toggle(); compute() }

    private func compute() {
        switch LineDiff.diff(swapped ? newer : older, swapped ? older : newer) {
        case .failure(let e): message = e.localizedDescription; rows = []; lines = []
        case .success(let d):
            lines = d
            stats = LineDiff.stats(d)
            message = stats.added + stats.removed == 0 ? "No differences. The last two copies have the same lines." : nil
            rows = message == nil ? LineDiff.rows(d) : []
        }
    }

    func submit() { lines.isEmpty || message != nil ? dismiss() : copy() }

    func copy() {
        let text = LineDiff.unified(lines)
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(text, forType: .string) }
    }

    var actions: [ActionItem] {
        var a: [ActionItem] = []
        if message == nil, !lines.isEmpty { a.append(ActionItem(title: "Copy Diff", symbol: "doc.on.doc", run: { [self] in copy() })) }
        if !lines.isEmpty || message != nil { a.append(ActionItem(title: "Swap Direction (\(swapped ? "older → newer" : "newer → older"))", symbol: "arrow.left.arrow.right", keepsOpen: true, run: { [self] in swap() })) }
        return a
    }
}
