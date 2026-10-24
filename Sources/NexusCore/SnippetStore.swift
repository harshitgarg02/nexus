import Foundation
import SQLite3

public enum SnippetKind: String, Codable, CaseIterable {
    case text, code, command

    public var title: String {
        switch self {
        case .text: return "Text"
        case .code: return "Code"
        case .command: return "Command"
        }
    }
}

public struct Snippet: Identifiable, Equatable {
    public let id: Int64
    public var name: String
    /// Empty for secret snippets: their value lives in the Keychain, never in this database.
    public var content: String
    public var tags: [String]
    public var isSecret: Bool
    public let created: Date
    public var modified: Date
    public var lastUsed: Date?
    public var timesUsed: Int
    public var kind: SnippetKind
    /// Syntax label for code snippets (e.g. "swift"); empty otherwise.
    public var language: String
}

public final class SnippetStore: SQLiteStore {
    public override init(path: String) {
        super.init(path: path)
        exec("""
        CREATE TABLE IF NOT EXISTS snippets(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, content TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '', secret INT NOT NULL DEFAULT 0,
          created REAL NOT NULL, modified REAL NOT NULL, last_used REAL, times_used INT NOT NULL DEFAULT 0)
        """)
        // migrations for databases created before snippet kinds (errors = column already exists)
        exec("ALTER TABLE snippets ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'")
        exec("ALTER TABLE snippets ADD COLUMN language TEXT NOT NULL DEFAULT ''")
    }

    @discardableResult
    public func insert(name: String, content: String, tags: [String], secret: Bool, kind: SnippetKind = .text,
                       language: String = "", now: Date = Date()) -> Int64 {
        run("INSERT INTO snippets(name,content,tags,secret,created,modified,kind,language) VALUES(?,?,?,?,?,?,?,?)",
            [.text(name), .text(secret ? "" : content), .text(Self.joinTags(tags)), .int(secret ? 1 : 0),
             .double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970), .text(kind.rawValue), .text(kind == .code ? language : "")])
        return lastInsertID
    }

    public func update(_ id: Int64, name: String, content: String, tags: [String], secret: Bool, kind: SnippetKind = .text,
                       language: String = "", now: Date = Date()) {
        run("UPDATE snippets SET name=?, content=?, tags=?, secret=?, modified=?, kind=?, language=? WHERE id=?",
            [.text(name), .text(secret ? "" : content), .text(Self.joinTags(tags)), .int(secret ? 1 : 0),
             .double(now.timeIntervalSince1970), .text(kind.rawValue), .text(kind == .code ? language : ""), .int(id)])
    }

    public func delete(_ id: Int64) { run("DELETE FROM snippets WHERE id = ?", [.int(id)]) }

    public func markUsed(_ id: Int64, now: Date = Date()) {
        run("UPDATE snippets SET times_used = times_used + 1, last_used = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .int(id)])
    }

    /// Most recently used/created first. `tag` filters by exact tag.
    public func all(query q: String = "", tag: String? = nil) -> [Snippet] {
        var out: [Snippet] = []
        let like = "%" + q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        // Secret snippets match on name/tags only (their content isn't in the database).
        query("""
        SELECT id,name,content,tags,secret,created,modified,last_used,times_used,kind,language FROM snippets
        WHERE (? = '' OR name LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\')
        ORDER BY COALESCE(last_used, created) DESC
        """, [.text(q), .text(like), .text(like), .text(like)]) { s in
            let lu: Date? = sqlite3_column_type(s, 7) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 7))
            out.append(Snippet(id: sqlite3_column_int64(s, 0), name: Self.str(s, 1) ?? "", content: Self.str(s, 2) ?? "",
                               tags: Self.splitTags(Self.str(s, 3) ?? ""), isSecret: sqlite3_column_int(s, 4) != 0,
                               created: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
                               modified: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                               lastUsed: lu, timesUsed: Int(sqlite3_column_int(s, 8)),
                               kind: SnippetKind(rawValue: Self.str(s, 9) ?? "") ?? .text, language: Self.str(s, 10) ?? ""))
        }
        if let tag { out = out.filter { $0.tags.contains(tag) } }
        return out
    }

    public func allTags() -> [String] {
        Array(Set(all().flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func joinTags(_ t: [String]) -> String { t.joined(separator: ",") }
    public static func splitTags(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

public enum SnippetExpander {
    /// `{clipboard}`, `{date}` (yyyy-MM-dd), `{time}` (HH:mm), `{datetime}`. Unknown braces are left alone.
    public static func expand(_ s: String, clipboard: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard s.contains("{") else { return s }
        func fmt(_ p: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = p
            return f.string(from: now)
        }
        return s
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
            .replacingOccurrences(of: "{datetime}", with: fmt("yyyy-MM-dd HH:mm"))
            .replacingOccurrences(of: "{date}", with: fmt("yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: fmt("HH:mm"))
    }
}
