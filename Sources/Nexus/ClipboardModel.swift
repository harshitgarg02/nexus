import AppKit
import NexusCore

enum ClipFilter: String, CaseIterable {
    case all = "All Types", text = "Text", link = "Links", image = "Images", file = "Files"

    var kind: ClipKind? {
        switch self {
        case .all: return nil
        case .text: return .text
        case .link: return .url
        case .image: return .image
        case .file: return .file
        }
    }

    var symbol: String {
        switch self {
        case .all: return "list.bullet"
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

final class ClipboardModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; reload() } }
    @Published var filter: ClipFilter = .all { didSet { selection = 0; reload() } }
    @Published private(set) var items: [Clip] = []
    @Published var selection = 0 { didSet { if oldValue != selection { previewSelection = "" } } }
    /// Substring selected in the preview pane; ↵ pastes only this when non-empty.
    @Published var previewSelection = ""
    @Published var focusTick = 0
    var targetApp: NSRunningApplication?
    var dismiss: () -> Void = {}

    private var store: ClipboardStore { ClipboardService.shared.store }

    var selected: Clip? { items.indices.contains(selection) ? items[selection] : nil }
    var targetName: String { targetApp?.localizedName ?? "Frontmost App" }

    func open() {
        query = ""
        filter = .all
        selection = 0
        previewSelection = ""
        reload()
        focusTick += 1
    }

    func reload() {
        items = store.fetch(query: query, kind: filter.kind)
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    // MARK: paste

    private var formattedDefault: Bool { Settings.shared.data.pasteFormattedByDefault }

    private func hasRich(_ c: Clip) -> Bool {
        guard c.kind == .text else { return false }
        let r = store.rich(c.id)
        return r.rtf != nil || r.html != nil
    }

    var primaryLabel: String {
        guard let c = selected else { return "Paste" }
        if !previewSelection.isEmpty { return "Paste Selection to \(targetName)" }
        if c.kind == .text, !(formattedDefault && hasRich(c)) { return "Paste as Plain Text to \(targetName)" }
        return "Paste to \(targetName)"
    }

    func paste(formatted: Bool? = nil) { put(paste: true, formatted: formatted ?? formattedDefault) }
    func copy() { put(paste: false, formatted: formattedDefault) }

    private func put(paste: Bool, formatted: Bool) {
        guard let c = selected else { return }
        let sel = previewSelection
        let rich = formatted && sel.isEmpty ? store.rich(c.id) : (nil, nil)
        let fullText = c.kind == .text || c.kind == .url ? (store.fullText(c.id) ?? c.text) : c.text
        let target = targetApp
        dismiss()
        target?.activate() // normally already frontmost; harmless
        ClipboardService.shared.write(paste: paste) { pb in
            if !sel.isEmpty { pb.setString(sel, forType: .string); return }
            switch c.kind {
            case .image:
                if let p = c.imagePath, let d = try? Data(contentsOf: URL(fileURLWithPath: p)) { pb.setData(d, forType: .png) }
            case .file:
                pb.writeObjects(c.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL })
            case .text, .url:
                pb.setString(fullText, forType: .string)
                if let r = rich.0 { pb.setData(r, forType: .rtf) }
                if let h = rich.1 { pb.setData(h, forType: .html) }
            }
        }
    }

    func togglePin() {
        guard let c = selected else { return }
        store.setPinned(c.id, !c.pinned)
        reload()
    }

    func deleteSelected() {
        guard let c = selected else { return }
        if let p = store.delete(c.id) { ClipboardService.shared.removeImage(p) }
        reload()
    }

    func clearAll() {
        ClipboardService.shared.clearAll()
        reload()
    }

    var actions: [ActionItem] {
        guard let c = selected else { return [] }
        var a = [ActionItem(title: primaryLabel, symbol: "arrow.right.doc.on.clipboard", run: { [self] in paste() })]
        if c.kind == .text {
            let rich = hasRich(c)
            if formattedDefault || rich {
                a.append(ActionItem(title: formattedDefault ? "Paste as Plain Text" : "Paste with Formatting",
                                    symbol: "textformat", run: { [self] in paste(formatted: !formattedDefault) }))
            }
        }
        a.append(ActionItem(title: "Copy to Clipboard", symbol: "doc.on.doc", run: { [self] in copy() }))
        a.append(ActionItem(title: c.pinned ? "Unpin" : "Pin", symbol: c.pinned ? "pin.slash" : "pin", keepsOpen: true, run: { [self] in togglePin() }))
        a.append(ActionItem(title: "Delete", symbol: "trash", destructive: true, keepsOpen: true, run: { [self] in deleteSelected() }))
        a.append(ActionItem(title: "Clear All History", symbol: "trash.slash", destructive: true, keepsOpen: true, run: { [self] in clearAll() }))
        return a
    }

    // MARK: grouping

    static func group(for c: Clip, now: Date = Date()) -> String {
        if c.pinned { return "Pinned" }
        let cal = Calendar.current
        if cal.isDateInToday(c.created) { return "Today" }
        if cal.isDateInYesterday(c.created) { return "Yesterday" }
        if let d = cal.dateComponents([.day], from: c.created, to: now).day, d < 7 { return "Last 7 Days" }
        return "Older"
    }
}
