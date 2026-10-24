import Foundation
import SQLite3
import CryptoKit

public enum ClipKind: String, CaseIterable {
    case text, url, image, file
}

public struct Clip: Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipKind
    public let text: String
    public let imagePath: String?
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let sourceBundle: String
    public let sourceName: String
    public let created: Date
    public let pinned: Bool
    /// Full length/word count of the stored text; `text` itself is cut to `ClipboardStore.previewLimit` characters.
    public let chars: Int
    public let words: Int
    public var isTruncated: Bool { chars > text.count }
}

public struct ClipDraft {
    public var kind: ClipKind
    public var text: String
    public var imagePath: String?
    public var width = 0
    public var height = 0
    public var bytes = 0
    public var sourceBundle = ""
    public var sourceName = ""
    public var rtf: Data?
    public var html: Data?
    public var chars = 0
    public var words = 0
    public var hash: String

    public init(kind: ClipKind, text: String, hash: String, imagePath: String? = nil) {
        self.kind = kind; self.text = text; self.hash = hash; self.imagePath = imagePath
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// SQLite-backed clipboard history. Single-threaded use (main queue).
public final class ClipboardStore: SQLiteStore {
    /// Lists/preview only load this many characters of a clip; paste uses `fullText`.
    public static let previewLimit = 20_000
    public override init(path: String) {
        super.init(path: path)
        exec("""
        CREATE TABLE IF NOT EXISTS clips(
          id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, text TEXT NOT NULL DEFAULT '',
          image_path TEXT, width INT DEFAULT 0, height INT DEFAULT 0, bytes INT DEFAULT 0,
          src_bundle TEXT DEFAULT '', src_name TEXT DEFAULT '', created REAL NOT NULL,
          pinned INT DEFAULT 0, hash TEXT NOT NULL UNIQUE, rtf BLOB, html BLOB)
        """)
        exec("CREATE INDEX IF NOT EXISTS clips_created ON clips(created)")
        // migrations for databases created by earlier builds (errors = column already exists)
        exec("ALTER TABLE clips ADD COLUMN chars INT DEFAULT 0")
        exec("ALTER TABLE clips ADD COLUMN words INT DEFAULT 0")
    }

    // MARK: writes

    /// Inserts, or bumps an existing identical entry to the top. Returns its id.
    @discardableResult
    public func insert(_ d: ClipDraft, now: Date = Date()) -> Int64 {
        var existing: Int64?
        query("SELECT id FROM clips WHERE hash = ?", [.text(d.hash)]) { existing = sqlite3_column_int64($0, 0) }
        if let id = existing {
            run("UPDATE clips SET created = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .int(id)])
            return id
        }
        run("""
        INSERT INTO clips(kind,text,image_path,width,height,bytes,src_bundle,src_name,created,hash,rtf,html,chars,words)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [.text(d.kind.rawValue), .text(d.text), d.imagePath.map { .text($0) } ?? .null,
              .int(Int64(d.width)), .int(Int64(d.height)), .int(Int64(d.bytes)),
              .text(d.sourceBundle), .text(d.sourceName), .double(now.timeIntervalSince1970),
              .text(d.hash), d.rtf.map { .blob($0) } ?? .null, d.html.map { .blob($0) } ?? .null,
              .int(Int64(d.chars)), .int(Int64(d.words))])
        return lastInsertID
    }

    public func setPinned(_ id: Int64, _ pinned: Bool) {
        run("UPDATE clips SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .int(id)])
    }

    /// Returns the image path (if any) so the caller can delete the file.
    @discardableResult
    public func delete(_ id: Int64) -> String? {
        var path: String?
        query("SELECT image_path FROM clips WHERE id = ?", [.int(id)]) { path = Self.str($0, 0) }
        run("DELETE FROM clips WHERE id = ?", [.int(id)])
        return path
    }

    /// Removes every entry with this content hash (used to scrub known secrets from history).
    public func delete(hash: String) { run("DELETE FROM clips WHERE hash = ?", [.text(hash)]) }

    /// Deletes everything unpinned (or everything). Returns image paths to remove.
    public func clear(includePinned: Bool = false) -> [String] {
        let w = includePinned ? "1=1" : "pinned = 0"
        var paths: [String] = []
        query("SELECT image_path FROM clips WHERE \(w) AND image_path IS NOT NULL", []) { if let p = Self.str($0, 0) { paths.append(p) } }
        run("DELETE FROM clips WHERE \(w)", [])
        return paths
    }

    /// Retention. `nil` cutoff = keep forever. Pinned entries are never purged. Returns image paths to remove.
    public func purge(textBefore: Date?, imagesBefore: Date?) -> [String] {
        var paths: [String] = []
        if let t = textBefore {
            run("DELETE FROM clips WHERE pinned = 0 AND kind != 'image' AND created < ?", [.double(t.timeIntervalSince1970)])
        }
        if let t = imagesBefore {
            query("SELECT image_path FROM clips WHERE pinned = 0 AND kind = 'image' AND created < ? AND image_path IS NOT NULL",
                  [.double(t.timeIntervalSince1970)]) { if let p = Self.str($0, 0) { paths.append(p) } }
            run("DELETE FROM clips WHERE pinned = 0 AND kind = 'image' AND created < ?", [.double(t.timeIntervalSince1970)])
        }
        return paths
    }

    // MARK: reads

    public func fetch(query q: String = "", kind: ClipKind? = nil, limit: Int = 500) -> [Clip] {
        var out: [Clip] = []
        let like = "%" + q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        query("""
        SELECT id,kind,substr(text,1,\(Self.previewLimit)),image_path,width,height,bytes,src_bundle,src_name,created,pinned,
               COALESCE(NULLIF(chars,0), length(text)), words FROM clips
        WHERE (? = '' OR text LIKE ? ESCAPE '\\') AND (? = '' OR kind = ?)
        ORDER BY pinned DESC, created DESC LIMIT ?
        """, [.text(q), .text(like), .text(kind?.rawValue ?? ""), .text(kind?.rawValue ?? ""), .int(Int64(limit))]) { s in
            out.append(Clip(id: sqlite3_column_int64(s, 0), kind: ClipKind(rawValue: Self.str(s, 1) ?? "text") ?? .text,
                            text: Self.str(s, 2) ?? "", imagePath: Self.str(s, 3),
                            width: Int(sqlite3_column_int(s, 4)), height: Int(sqlite3_column_int(s, 5)),
                            bytes: Int(sqlite3_column_int(s, 6)), sourceBundle: Self.str(s, 7) ?? "",
                            sourceName: Self.str(s, 8) ?? "", created: Date(timeIntervalSince1970: sqlite3_column_double(s, 9)),
                            pinned: sqlite3_column_int(s, 10) != 0,
                            chars: Int(sqlite3_column_int64(s, 11)), words: Int(sqlite3_column_int64(s, 12))))
        }
        return out
    }

    public func fullText(_ id: Int64) -> String? {
        var t: String?
        query("SELECT text FROM clips WHERE id = ?", [.int(id)]) { t = Self.str($0, 0) }
        return t
    }

    /// The most recent text/link copies, newest first, full text. Ignores pinning (unlike `fetch`).
    public func recentTexts(limit: Int) -> [String] {
        var out: [String] = []
        query("SELECT text FROM clips WHERE kind IN ('text','url') ORDER BY created DESC LIMIT ?", [.int(Int64(limit))]) {
            out.append(Self.str($0, 0) ?? "")
        }
        return out
    }

    public func rich(_ id: Int64) -> (rtf: Data?, html: Data?) {
        var r: (Data?, Data?) = (nil, nil)
        query("SELECT rtf, html FROM clips WHERE id = ?", [.int(id)]) { s in
            r = (Self.blob(s, 0), Self.blob(s, 1))
        }
        return r
    }
}
