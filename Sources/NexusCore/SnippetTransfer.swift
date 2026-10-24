import Foundation

/// JSON snippet backup. Secret snippets are never exported: their values live only in the Keychain.
public struct SnippetExport: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var name: String
        public var content: String
        public var tags: [String]
        public var created: Date
        public var modified: Date
        /// Optional so exports from before snippet kinds still import (as text).
        public var kind: SnippetKind?
        public var language: String?

        public init(name: String, content: String, tags: [String], created: Date, modified: Date,
                    kind: SnippetKind? = nil, language: String? = nil) {
            self.name = name; self.content = content; self.tags = tags; self.created = created; self.modified = modified
            self.kind = kind; self.language = language
        }
    }

    public static let currentVersion = 1
    public var version: Int
    public var exportedAt: Date
    public var snippets: [Entry]
}

public enum TransferError: Error, LocalizedError, Equatable {
    case notSnippetFile
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notSnippetFile: return "This isn't a Nexus snippet export."
        case .unsupportedVersion(let v): return "This file is from a newer Nexus (format v\(v)). Update Nexus to import it."
        }
    }
}

public struct ImportSummary: Equatable {
    public var added = 0
    public var duplicates = 0
    public var renamed = 0
    public var invalid = 0
}

public enum SnippetTransfer {
    public static func export(_ all: [Snippet], now: Date = Date()) throws -> (data: Data, exported: Int, skippedSecrets: Int) {
        let plain = all.filter { !$0.isSecret }
        let file = SnippetExport(version: SnippetExport.currentVersion, exportedAt: now, snippets: plain.map {
            .init(name: $0.name, content: $0.content, tags: $0.tags, created: $0.created, modified: $0.modified,
                  kind: $0.kind, language: $0.language.isEmpty ? nil : $0.language)
        })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try enc.encode(file), plain.count, all.count - plain.count)
    }

    public static func decode(_ data: Data) throws -> [SnippetExport.Entry] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let file = try? dec.decode(SnippetExport.self, from: data) else { throw TransferError.notSnippetFile }
        guard file.version <= SnippetExport.currentVersion else { throw TransferError.unsupportedVersion(file.version) }
        return file.snippets
    }
}

extension SnippetStore {
    /// Merge rules: identical name+content is skipped; same name with different content is kept as
    /// "name (imported)" (numbered if needed) so nothing existing is overwritten; blank name/content is skipped.
    public func importEntries(_ entries: [SnippetExport.Entry]) -> ImportSummary {
        var summary = ImportSummary()
        var existing = all()
        for e in entries {
            let name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !e.content.isEmpty else { summary.invalid += 1; continue }
            if existing.contains(where: { !$0.isSecret && $0.name == name && $0.content == e.content }) { summary.duplicates += 1; continue }
            var finalName = name
            if existing.contains(where: { $0.name == name }) {
                finalName = "\(name) (imported)"
                var n = 2
                while existing.contains(where: { $0.name == finalName }) { finalName = "\(name) (imported \(n))"; n += 1 }
                summary.renamed += 1
            }
            let kind = e.kind ?? .text
            run("INSERT INTO snippets(name,content,tags,secret,created,modified,kind,language) VALUES(?,?,?,0,?,?,?,?)",
                [.text(finalName), .text(e.content), .text(Self.joinTags(e.tags)),
                 .double(e.created.timeIntervalSince1970), .double(e.modified.timeIntervalSince1970),
                 .text(kind.rawValue), .text(kind == .code ? (e.language ?? "") : "")])
            summary.added += 1
            existing = all()
        }
        return summary
    }
}
