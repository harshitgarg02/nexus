import Foundation

/// What to do with a script's standard output.
public enum ScriptMode: String, CaseIterable {
    case output     // show it in the overlay (default)
    case clipboard  // copy it
    case paste      // paste it into the frontmost app
    case silent     // run and show nothing (errors still surface)
}

public struct ScriptInfo: Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let description: String
    /// SF Symbol name.
    public let icon: String
    public let mode: ScriptMode
    public let keywords: [String]
    /// Placeholder text for a single text argument passed as `$1`; nil = the script takes none.
    public let argument: String?
}

/// Script commands are plain files with a comment header, e.g.:
///
///     #!/bin/bash
///     # @nexus.title Say Hello
///     # @nexus.description Greets someone
///     # @nexus.icon hand.wave
///     # @nexus.mode output
///     # @nexus.keywords hi, greet
///     # @nexus.argument Your name
///
/// Only files with a `@nexus.title` become commands, so stray files in the folder are never exposed.
public enum ScriptMetadata {
    private static let line = try! NSRegularExpression(pattern: #"^\s*(?:#|//|--)\s*@nexus\.([A-Za-z]+)\s*(.*?)\s*$"#)

    public static func parse(_ source: String, path: String) -> ScriptInfo? {
        var f: [String: String] = [:]
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            let s = String(raw)
            guard let m = line.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let k = Range(m.range(at: 1), in: s), let v = Range(m.range(at: 2), in: s) else { continue }
            let key = s[k].lowercased()
            if f[key] == nil { f[key] = String(s[v]) } // first occurrence wins
        }
        guard let title = f["title"], !title.isEmpty else { return nil }
        let keywords = (f["keywords"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        return ScriptInfo(path: path, title: title, description: f["description"] ?? "",
                          icon: (f["icon"]?.isEmpty == false ? f["icon"]! : "terminal"),
                          mode: f["mode"].flatMap { ScriptMode(rawValue: $0.lowercased()) } ?? .output,
                          keywords: keywords,
                          argument: f["argument"].map { $0.isEmpty ? "Argument" : $0 })
    }
}
