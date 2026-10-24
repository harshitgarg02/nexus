import Foundation
import CryptoKit
import SQLite3

public enum TOTPAlgorithm: String, CaseIterable {
    case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
}

public struct OTPAuthURI: Equatable {
    public var name: String
    public var secret: String // base32, as given
    public var algorithm: TOTPAlgorithm
    public var digits: Int
    public var period: Int
}

/// RFC 6238 time-based one-time passwords.
public enum TOTP {
    public static func code(secret: [UInt8], at date: Date = Date(), period: Int = 30, digits: Int = 6,
                            algorithm: TOTPAlgorithm = .sha1) -> String {
        let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(period)
        var big = counter.bigEndian
        let msg = Data(bytes: &big, count: 8)
        let key = SymmetricKey(data: secret)
        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: key))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: msg, using: key))
        }
        let o = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[o] & 0x7f) << 24) | (UInt32(mac[o + 1]) << 16) | (UInt32(mac[o + 2]) << 8) | UInt32(mac[o + 3])
        var mod: UInt32 = 1
        for _ in 0..<digits { mod *= 10 }
        return String(format: "%0\(digits)d", bin % mod)
    }

    /// Seconds left in the current window, 1...period.
    public static func remaining(at date: Date = Date(), period: Int = 30) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    /// RFC 4648 base32; tolerant of case, spaces, dashes and padding. Nil if invalid or empty.
    public static func base32Decode(_ s: String) -> [UInt8]? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var out: [UInt8] = []
        for ch in s.uppercased() where ch != " " && ch != "-" && ch != "=" {
            guard let i = alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | i
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out.isEmpty ? nil : out
    }

    /// `otpauth://totp/Issuer:account?secret=…&issuer=…&algorithm=SHA1&digits=6&period=30`
    public static func parse(uri: String) -> OTPAuthURI? {
        guard let c = URLComponents(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "otpauth", c.host == "totp" else { return nil }
        let q = Dictionary(c.queryItems?.compactMap { i in i.value.map { (i.name.lowercased(), $0) } } ?? [], uniquingKeysWith: { a, _ in a })
        guard let secret = q["secret"], base32Decode(secret) != nil else { return nil }
        var label = String(c.path.dropFirst()).removingPercentEncoding ?? String(c.path.dropFirst())
        let issuer = q["issuer"]
        if let i = label.firstIndex(of: ":") {
            let prefix = String(label[..<i]), account = String(label[label.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            label = account.isEmpty ? prefix : (issuer == nil || issuer == prefix ? "\(prefix) · \(account)" : "\(prefix) · \(account)")
        } else if let issuer, !label.isEmpty { label = "\(issuer) · \(label)" }
        else if let issuer { label = issuer }
        let algo = TOTPAlgorithm(rawValue: (q["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
        let digits = Int(q["digits"] ?? "") .flatMap { (6...8).contains($0) ? $0 : nil } ?? 6
        let period = Int(q["period"] ?? "").flatMap { $0 > 0 ? $0 : nil } ?? 30
        return OTPAuthURI(name: label.isEmpty ? "Account" : label, secret: secret, algorithm: algo, digits: digits, period: period)
    }
}

public struct TOTPEntry: Identifiable, Equatable {
    public let id: Int64
    public var name: String
    public var algorithm: TOTPAlgorithm
    public var digits: Int
    public var period: Int
}

/// Entry metadata only. Secrets live in the Keychain, never here.
public final class TOTPStore: SQLiteStore {
    public override init(path: String) {
        super.init(path: path)
        exec("""
        CREATE TABLE IF NOT EXISTS totp(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, algorithm TEXT NOT NULL DEFAULT 'SHA1',
          digits INT NOT NULL DEFAULT 6, period INT NOT NULL DEFAULT 30, created REAL NOT NULL)
        """)
    }

    @discardableResult
    public func insert(name: String, algorithm: TOTPAlgorithm, digits: Int, period: Int) -> Int64 {
        run("INSERT INTO totp(name,algorithm,digits,period,created) VALUES(?,?,?,?,?)",
            [.text(name), .text(algorithm.rawValue), .int(Int64(digits)), .int(Int64(period)), .double(Date().timeIntervalSince1970)])
        return lastInsertID
    }

    public func update(_ id: Int64, name: String, algorithm: TOTPAlgorithm, digits: Int, period: Int) {
        run("UPDATE totp SET name=?, algorithm=?, digits=?, period=? WHERE id=?",
            [.text(name), .text(algorithm.rawValue), .int(Int64(digits)), .int(Int64(period)), .int(id)])
    }

    public func delete(_ id: Int64) { run("DELETE FROM totp WHERE id = ?", [.int(id)]) }

    public func all(query q: String = "") -> [TOTPEntry] {
        var out: [TOTPEntry] = []
        query("SELECT id,name,algorithm,digits,period FROM totp ORDER BY name COLLATE NOCASE", []) { s in
            out.append(TOTPEntry(id: sqlite3_column_int64(s, 0), name: Self.str(s, 1) ?? "",
                                 algorithm: TOTPAlgorithm(rawValue: Self.str(s, 2) ?? "") ?? .sha1,
                                 digits: Int(sqlite3_column_int(s, 3)), period: Int(sqlite3_column_int(s, 4))))
        }
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? out : out.filter { $0.name.lowercased().contains(t) }
    }
}
