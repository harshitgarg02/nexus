import AppKit
import NexusCore

struct SnippetEditor {
    var id: Int64?
    var name = ""
    var tags = ""
    var isSecret = false
    var kind = SnippetKind.text
    var language = ""
    var content = ""
    var error: String?
}

final class SnippetsModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; reload() } }
    @Published var tagFilter: String? { didSet { selection = 0; reload() } }
    @Published private(set) var items: [Snippet] = []
    @Published private(set) var tags: [String] = []
    @Published var selection = 0 { didSet { if oldValue != selection { revealed = nil } } }
    @Published var editor: SnippetEditor?
    /// Secret value shown (after auth) for the currently selected snippet only.
    @Published private(set) var revealed: String?
    @Published var focusTick = 0
    var targetApp: NSRunningApplication?
    var dismiss: () -> Void = {}

    /// Shared so Settings can import/export without going through the overlay's model.
    static let sharedStore: SnippetStore = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SnippetStore(path: dir.appendingPathComponent("snippets.db").path)
    }()
    var store: SnippetStore { Self.sharedStore }

    var selected: Snippet? { items.indices.contains(selection) ? items[selection] : nil }
    var targetName: String { targetApp?.localizedName ?? "Frontmost App" }
    var primaryLabel: String { selected == nil ? "Paste" : "Paste to \(targetName)" }

    func open() {
        query = ""
        tagFilter = nil
        selection = 0
        editor = nil
        revealed = nil
        reload()
        focusTick += 1
    }

    func reload() {
        items = store.all(query: query, tag: tagFilter)
        tags = store.allTags()
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    // MARK: values

    private func value(of s: Snippet) -> String? { s.isSecret ? SecretVault.get(s.id) : s.content }

    enum Variant { case plain, markdownBlock, run }

    func paste(_ v: Variant = .plain) { put(paste: true, variant: v) }
    func copy() { put(paste: false) }

    private func put(paste: Bool, variant: Variant = .plain) {
        guard let s = selected, let raw = value(of: s) else { return }
        let target = targetApp
        let secret = s.isSecret
        let clearAfter = secret ? TimeInterval(Settings.shared.data.secretClearSeconds) : nil
        if secret { ClipboardService.shared.block(value: raw) }
        let current = NSPasteboard.general.string(forType: .string)
        var text = SnippetExpander.expand(raw, clipboard: current)
        if variant == .markdownBlock {
            text = "```\(s.language)\n" + text.trimmingCharacters(in: CharacterSet(charactersIn: "\n")) + "\n```"
        }
        store.markUsed(s.id)
        dismiss()
        target?.activate()
        ClipboardService.shared.write(paste: paste, clearAfter: clearAfter, thenReturn: variant == .run) { $0.setString(text, forType: .string) }
        reload()
    }

    // MARK: editing (secrets require the Mac login)

    func beginNew(kind: SnippetKind = .text, content: String = "") {
        revealed = nil
        editor = SnippetEditor(kind: kind, content: content)
        focusTick += 1
    }

    func beginNewFromClipboard() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        beginNew(kind: clip.contains("\n") ? .code : .text, content: clip)
    }

    func beginEdit() {
        guard let s = selected else { return }
        authorized(s, reason: "Edit the secret snippet “\(s.name)”") { [self] in
            editor = SnippetEditor(id: s.id, name: s.name, tags: s.tags.joined(separator: ", "), isSecret: s.isSecret,
                                   kind: s.kind, language: s.language, content: value(of: s) ?? "")
            focusTick += 1
        }
    }

    func reveal() {
        guard let s = selected, s.isSecret else { return }
        authorized(s, reason: "Reveal the secret snippet “\(s.name)”") { [self] in
            revealed = SecretVault.get(s.id)
            if let r = revealed { ClipboardService.shared.block(value: r) }
        }
    }

    func deleteSelected() {
        guard let s = selected else { return }
        authorized(s, reason: "Delete the secret snippet “\(s.name)”") { [self] in
            store.delete(s.id)
            if s.isSecret { SecretVault.delete(s.id) }
            reload()
        }
    }

    func saveEditor() {
        guard var e = editor else { return }
        let name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { e.error = "Name is required."; editor = e; return }
        guard !e.content.isEmpty else { e.error = "Content is required."; editor = e; return }
        let tags = SnippetStore.splitTags(e.tags)
        let id: Int64
        if let existing = e.id {
            store.update(existing, name: name, content: e.content, tags: tags, secret: e.isSecret, kind: e.kind,
                         language: e.language.trimmingCharacters(in: .whitespaces))
            id = existing
        } else {
            id = store.insert(name: name, content: e.content, tags: tags, secret: e.isSecret, kind: e.kind,
                              language: e.language.trimmingCharacters(in: .whitespaces))
        }
        if e.isSecret {
            guard SecretVault.set(e.content, for: id) else {
                e.error = "Couldn't save to the Keychain."; editor = e; return
            }
        } else {
            SecretVault.delete(id) // was secret before
        }
        if e.isSecret { ClipboardService.shared.block(value: e.content) }
        editor = nil
        reload()
        if let i = items.firstIndex(where: { $0.id == id }) { selection = i }
        focusTick += 1
    }

    func cancelEditor() { editor = nil; focusTick += 1 }

    private func authorized(_ s: Snippet, reason: String, _ action: @escaping () -> Void) {
        guard s.isSecret else { return action() }
        Task { @MainActor in if await Auth.verify(reason: reason) { action() } }
    }

    var actions: [ActionItem] {
        let creators: [ActionItem] = [
            ActionItem(title: "New Snippet", symbol: "plus", keepsOpen: true, run: { [self] in beginNew() }),
            ActionItem(title: "New Code Snippet", symbol: "chevron.left.forwardslash.chevron.right", keepsOpen: true,
                       run: { [self] in beginNew(kind: .code) }),
            ActionItem(title: "New Terminal Command", symbol: "terminal", keepsOpen: true, run: { [self] in beginNew(kind: .command) }),
            ActionItem(title: "New from Clipboard", symbol: "doc.on.clipboard", keepsOpen: true, run: { [self] in beginNewFromClipboard() }),
        ]
        var a = creators
        guard let s = selected else { return a + transferActions }
        a.insert(ActionItem(title: primaryLabel, symbol: "arrow.right.doc.on.clipboard", run: { [self] in paste() }), at: 0)
        a.insert(ActionItem(title: s.isSecret ? "Copy (clears in \(Settings.shared.data.secretClearSeconds)s)" : "Copy to Clipboard",
                            symbol: "doc.on.doc", run: { [self] in copy() }), at: 1)
        if s.isSecret { a.insert(ActionItem(title: "Reveal…", symbol: "eye", keepsOpen: true, run: { [self] in reveal() }), at: 2) }
        if s.kind == .command {
            a.insert(ActionItem(title: "Paste and Run (adds Return)", symbol: "play.fill", run: { [self] in paste(.run) }), at: 1)
        }
        if s.kind == .code {
            a.insert(ActionItem(title: "Paste as Markdown Code Block", symbol: "number", run: { [self] in paste(.markdownBlock) }), at: 1)
        }
        a.append(ActionItem(title: s.isSecret ? "Edit… (needs login)" : "Edit", symbol: "pencil", keepsOpen: true, run: { [self] in beginEdit() }))
        a.append(ActionItem(title: s.isSecret ? "Delete… (needs login)" : "Delete", symbol: "trash", destructive: true, keepsOpen: true,
                            run: { [self] in deleteSelected() }))
        a.append(contentsOf: transferActions)
        return a
    }

    private var transferActions: [ActionItem] {
        [ActionItem(title: "Import Snippets…", symbol: "square.and.arrow.down", run: { SnippetTransferUI.importFile() }),
         ActionItem(title: "Export Snippets…", symbol: "square.and.arrow.up", run: { SnippetTransferUI.export() })]
    }

    static func group(for s: Snippet, now: Date = Date()) -> String {
        let d = s.lastUsed ?? s.created
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if let days = cal.dateComponents([.day], from: d, to: now).day, days < 7 { return "This Week" }
        if cal.isDate(d, equalTo: now, toGranularity: .month) { return "This Month" }
        return "Older"
    }
}
