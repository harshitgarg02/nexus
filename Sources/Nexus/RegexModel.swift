import AppKit
import NexusCore

/// Live regex tester: a pattern, flags and some text (prefilled from the clipboard) with the matches below.
final class RegexModel: ObservableObject {
    @Published var pattern = "" { didSet { recompute() } }
    @Published var ignoreCase = false { didSet { recompute() } }
    @Published var multiline = false { didSet { recompute() } }
    @Published var dotAll = false { didSet { recompute() } }
    @Published var text = "" { didSet { recompute() } }
    @Published private(set) var result: Result<[RegexMatch], TransformError> = .success([])
    @Published var focusTick = 0
    var dismiss: () -> Void = {}

    var flags: RegexFlags { RegexFlags(ignoreCase: ignoreCase, multiline: multiline, dotAll: dotAll) }
    var matches: [RegexMatch] { (try? result.get()) ?? [] }
    var allMatchesText: String { matches.map(\.text).joined(separator: "\n") }
    var primaryLabel: String { matches.isEmpty ? "Copy Pattern" : "Copy Matches" }

    func open() {
        pattern = ""
        ignoreCase = false; multiline = false; dotAll = false
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        text = String(clip.prefix(5000))
        focusTick += 1
    }

    private func recompute() { result = RegexTool.matches(pattern: pattern, flags: flags, in: text) }

    func submit() { matches.isEmpty ? copyPattern() : copy(allMatchesText) }
    func copyPattern() { copy(pattern) }

    private func copy(_ s: String) {
        guard !s.isEmpty else { return }
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(s, forType: .string) }
    }

    var actions: [ActionItem] {
        var a: [ActionItem] = []
        if !matches.isEmpty {
            a.append(ActionItem(title: "Copy All Matches", symbol: "doc.on.doc", run: { [self] in copy(allMatchesText) }))
            if let first = matches.first { a.append(ActionItem(title: "Copy First Match", symbol: "1.circle", run: { [self] in copy(first.text) })) }
        }
        if !pattern.isEmpty {
            a.append(ActionItem(title: "Copy Pattern", symbol: "chevron.left.forwardslash.chevron.right", run: { [self] in copyPattern() }))
            let letters = (ignoreCase ? "i" : "") + (multiline ? "m" : "") + (dotAll ? "s" : "")
            a.append(ActionItem(title: "Copy as /pattern/flags", symbol: "number", run: { [self] in copy("/\(pattern)/\(letters)") }))
        }
        return a
    }
}
