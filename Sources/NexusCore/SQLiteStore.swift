import Foundation
import SQLite3

/// Thin SQLite wrapper shared by the stores. Single-threaded use (main queue).
public class SQLiteStore {
    var db: OpaquePointer?
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) {
        guard sqlite3_open(path, &db) == SQLITE_OK else { fatalError("cannot open database at \(path)") }
        exec("PRAGMA journal_mode=WAL")
    }

    deinit { sqlite3_close(db) }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(db) }

    // MARK: sqlite plumbing

    enum Bind { case text(String), int(Int64), double(Double), blob(Data), null }

    func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    func prepare(_ sql: String, _ binds: [Bind]) -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            NSLog("Nexus sqlite: \(String(cString: sqlite3_errmsg(db))) in \(sql)")
            return nil
        }
        for (i, b) in binds.enumerated() {
            let n = Int32(i + 1)
            switch b {
            case .text(let s): sqlite3_bind_text(st, n, s, -1, Self.transient)
            case .int(let v): sqlite3_bind_int64(st, n, v)
            case .double(let v): sqlite3_bind_double(st, n, v)
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(st, n, $0.baseAddress, Int32(d.count), Self.transient) }
            case .null: sqlite3_bind_null(st, n)
            }
        }
        return st
    }

    func run(_ sql: String, _ binds: [Bind]) {
        guard let st = prepare(sql, binds) else { return }
        sqlite3_step(st)
        sqlite3_finalize(st)
    }

    func query(_ sql: String, _ binds: [Bind], row: (OpaquePointer) -> Void) {
        guard let st = prepare(sql, binds) else { return }
        while sqlite3_step(st) == SQLITE_ROW { row(st) }
        sqlite3_finalize(st)
    }

    static func str(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(s, i).map { String(cString: $0) }
    }

    static func blob(_ s: OpaquePointer, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(s, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(s, i)))
    }
}
