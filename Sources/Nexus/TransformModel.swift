import AppKit
import NexusCore

/// Runs a TextTransform on the clipboard's text and shows the result: ↵ copies it, ⌘K pastes it.
final class TransformModel: ObservableObject {
    private static let previewLimit = 20_000

    @Published private(set) var transform: TextTransform?
    @Published private(set) var input = ""
    @Published private(set) var result: Result<String, TransformError> = .failure(.empty)
    var targetApp: NSRunningApplication?
    var dismiss: () -> Void = {}

    var output: String? { if case .success(let s) = result { return s } else { return nil } }
    var preview: String { output.map { String($0.prefix(Self.previewLimit)) } ?? "" }
    var isTruncated: Bool { (output?.count ?? 0) > Self.previewLimit }
    var primaryLabel: String { output == nil ? "Close" : "Copy Result" }

    func open(_ t: TextTransform) {
        transform = t
        input = NSPasteboard.general.string(forType: .string) ?? ""
        result = t.apply(input)
    }

    func submit() {
        guard output != nil else { dismiss(); return }
        copy()
    }

    func copy() {
        guard let out = output else { return }
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(out, forType: .string) }
    }

    func paste() {
        guard let out = output else { return }
        let target = targetApp
        dismiss()
        target?.activate()
        ClipboardService.shared.write(paste: true) { $0.setString(out, forType: .string) }
    }

    var actions: [ActionItem] {
        guard output != nil else { return [] }
        return [ActionItem(title: "Copy Result", symbol: "doc.on.doc", run: { [self] in copy() }),
                ActionItem(title: "Paste Result to \(targetApp?.localizedName ?? "Frontmost App")", symbol: "arrow.right.doc.on.clipboard",
                           run: { [self] in paste() })]
    }

    /// "12 lines, 340 characters → 9 lines, 280 characters"
    var summary: String {
        func size(_ s: String) -> String {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(lines) line\(lines == 1 ? "" : "s"), \(s.count.formatted()) character\(s.count == 1 ? "" : "s")"
        }
        guard let out = output else { return "" }
        return transform == .statistics ? "" : "\(size(input)) → \(size(out))"
    }
}
