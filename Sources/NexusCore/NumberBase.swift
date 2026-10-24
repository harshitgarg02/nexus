import Foundation

/// Converts an integer between bases: decimal, hex, binary, octal (and base 36).
public enum NumberBase {
    public struct Value: Equatable {
        public let negative: Bool
        public let magnitude: UInt64

        public func string(radix: Int, prefix: String = "", uppercase: Bool = false) -> String {
            let digits = String(magnitude, radix: radix, uppercase: uppercase)
            return (negative && magnitude != 0 ? "-" : "") + prefix + digits
        }
    }

    /// `token` may carry a sign, a 0x / 0b / 0o prefix, and `_` or `,` separators. Without a prefix it is read
    /// in `radix` (default 10). Nil if empty, invalid for that base, or larger than 64 bits.
    public static func parse(_ token: String, radix: Int? = nil) -> Value? {
        var s = token.lowercased().filter { $0 != "_" && $0 != "," }
        var neg = false
        if s.hasPrefix("-") { neg = true; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        var r = radix ?? 10
        for (p, base) in [("0x", 16), ("0b", 2), ("0o", 8)] where s.hasPrefix(p) {
            if let given = radix, given != base { return nil } // "0xff" can't be read as base 10
            s.removeFirst(2); r = base
        }
        guard (2...36).contains(r), !s.isEmpty, let v = UInt64(s, radix: r) else { return nil }
        return Value(negative: neg, magnitude: v)
    }
}
