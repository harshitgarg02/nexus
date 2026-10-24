import Foundation

/// JSON with object key order preserved (Foundation's dictionaries lose it) and numbers kept as written.
indirect enum JSONValue {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

/// Strict JSON parser. Errors carry the offset so the message can say where.
struct OrderedJSONParser {
    struct Failure: Error { let message: String }

    private let chars: [Character]
    private var i = 0

    init(_ text: String) { chars = Array(text) }

    static func parse(_ text: String) -> Result<JSONValue, Failure> {
        var p = OrderedJSONParser(text)
        do {
            p.skipSpace()
            let v = try p.value()
            p.skipSpace()
            guard p.i == p.chars.count else { throw p.fail("unexpected “\(p.chars[p.i])”") }
            return .success(v)
        } catch let f as Failure { return .failure(f) } catch { return .failure(Failure(message: "unreadable")) }
    }

    private func fail(_ m: String) -> Failure { Failure(message: "\(m) at character \(i + 1)") }
    private mutating func skipSpace() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

    private mutating func value() throws -> JSONValue {
        guard i < chars.count else { throw fail("unexpected end of text") }
        switch chars[i] {
        case "{": return try object()
        case "[": return try array()
        case "\"": return .string(try string())
        case "t": try literal("true"); return .bool(true)
        case "f": try literal("false"); return .bool(false)
        case "n": try literal("null"); return .null
        case "-", "0"..."9": return .number(try number())
        default: throw fail("unexpected “\(chars[i])”")
        }
    }

    private mutating func literal(_ word: String) throws {
        guard i + word.count <= chars.count, String(chars[i..<i + word.count]) == word else { throw fail("expected “\(word)”") }
        i += word.count
    }

    private mutating func number() throws -> String {
        let start = i
        if chars[i] == "-" { i += 1 }
        guard i < chars.count, chars[i].isASCII, chars[i].isNumber else { throw fail("invalid number") }
        if chars[i] == "0" { i += 1 } else { while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 } }
        if i < chars.count, chars[i] == "." {
            i += 1
            guard i < chars.count, chars[i].isASCII, chars[i].isNumber else { throw fail("invalid number") }
            while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
        }
        if i < chars.count, chars[i] == "e" || chars[i] == "E" {
            i += 1
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
            guard i < chars.count, chars[i].isASCII, chars[i].isNumber else { throw fail("invalid number") }
            while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
        }
        return String(chars[start..<i])
    }

    private mutating func string() throws -> String {
        i += 1 // opening quote
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\"" { i += 1; return out }
            if c.unicodeScalars.first!.value < 0x20 { throw fail("control character in string") }
            if c == "\\" {
                i += 1
                guard i < chars.count else { break }
                switch chars[i] {
                case "n": out += "\n"
                case "t": out += "\t"
                case "r": out += "\r"
                case "b": out += "\u{8}"
                case "f": out += "\u{c}"
                case "\"", "\\", "/": out.append(chars[i])
                case "u":
                    guard var code = hex4(i + 1) else { throw fail("invalid \\u escape") }
                    i += 4
                    if (0xD800...0xDBFF).contains(code), i + 6 < chars.count, chars[i + 1] == "\\", chars[i + 2] == "u", let lo = hex4(i + 3), (0xDC00...0xDFFF).contains(lo) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
                        i += 6
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw fail("invalid \\u escape") }
                    out.unicodeScalars.append(scalar)
                default: throw fail("invalid escape “\\\(chars[i])”")
                }
                i += 1
                continue
            }
            out.append(c)
            i += 1
        }
        throw fail("unterminated string")
    }

    private func hex4(_ at: Int) -> UInt32? {
        guard at + 4 <= chars.count else { return nil }
        return UInt32(String(chars[at..<at + 4]), radix: 16)
    }

    private mutating func object() throws -> JSONValue {
        i += 1
        var pairs: [(key: String, value: JSONValue)] = []
        skipSpace()
        if i < chars.count, chars[i] == "}" { i += 1; return .object(pairs) }
        while true {
            skipSpace()
            guard i < chars.count, chars[i] == "\"" else { throw fail("expected a string key") }
            let k = try string()
            skipSpace()
            guard i < chars.count, chars[i] == ":" else { throw fail("expected “:”") }
            i += 1
            skipSpace()
            pairs.append((k, try value()))
            skipSpace()
            guard i < chars.count else { throw fail("unexpected end of text") }
            if chars[i] == "," { i += 1; continue }
            if chars[i] == "}" { i += 1; return .object(pairs) }
            throw fail("expected “,” or “}”")
        }
    }

    private mutating func array() throws -> JSONValue {
        i += 1
        var items: [JSONValue] = []
        skipSpace()
        if i < chars.count, chars[i] == "]" { i += 1; return .array(items) }
        while true {
            skipSpace()
            items.append(try value())
            skipSpace()
            guard i < chars.count else { throw fail("unexpected end of text") }
            if chars[i] == "," { i += 1; continue }
            if chars[i] == "]" { i += 1; return .array(items) }
            throw fail("expected “,” or “]”")
        }
    }
}

/// Writes a JSONValue as block-style YAML (2-space indent). Strings that YAML would read as something else
/// (numbers, booleans, null, "key: value" shapes…) are double-quoted; multi-line strings become block scalars.
enum YAMLEmitter {
    static func emit(_ v: JSONValue) -> String { lines(v, level: 0).joined(separator: "\n") }

    private static let reserved: Set<String> = ["true", "false", "yes", "no", "on", "off", "y", "n", "null", "~"]
    private static let specialLeading = Set("-?:,[]{}#&*!|>'\"%@`")

    private static func looksNumeric(_ s: String) -> Bool {
        if Double(s) != nil { return true }
        let l = s.lowercased()
        return l.hasPrefix("0x") || l.hasPrefix("0o") || [".inf", "-.inf", "+.inf", ".nan"].contains(l)
            || s.range(of: #"^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil
    }

    static func needsQuotes(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if s != s.trimmingCharacters(in: .whitespaces) { return true }
        if specialLeading.contains(s.first!) { return true }
        if reserved.contains(s.lowercased()) || looksNumeric(s) { return true }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        return s.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" }
    }

    private static func quoted(_ s: String) -> String { "\"" + TextTransform.escape(s) + "\"" }
    private static func scalar(_ s: String) -> String { needsQuotes(s) ? quoted(s) : s }
    private static func key(_ s: String) -> String { needsQuotes(s) || s.contains("\n") ? quoted(s) : s }

    /// The inline form for scalars and empty containers; nil for things that need their own lines.
    private static func inline(_ v: JSONValue) -> String? {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return s.contains("\n") && !s.hasPrefix(" ") ? nil : scalar(s)
        case .object(let p): return p.isEmpty ? "{}" : nil
        case .array(let a): return a.isEmpty ? "[]" : nil
        }
    }

    private static func block(_ s: String, level: Int) -> (header: String, body: [String]) {
        let trailing = s.reversed().prefix(while: { $0 == "\n" }).count
        let header = trailing == 0 ? "|-" : trailing == 1 ? "|" : "|+"
        let core = s.hasSuffix("\n") ? String(s.dropLast(trailing)) : s
        var body = core.components(separatedBy: "\n").map { String(repeating: "  ", count: level) + $0 }
        if trailing > 1 { body.append(contentsOf: Array(repeating: "", count: trailing - 1)) }
        return (header, body)
    }

    private static func lines(_ v: JSONValue, level: Int) -> [String] {
        let pad = String(repeating: "  ", count: level)
        if let s = inline(v) { return [pad + s] }
        switch v {
        case .string(let s):
            let b = block(s, level: level)
            return [pad + b.header] + b.body
        case .object(let pairs):
            var out: [String] = []
            for (k, val) in pairs {
                if let s = inline(val) { out.append("\(pad)\(key(k)): \(s)") }
                else if case .string(let text) = val {
                    let b = block(text, level: level + 1)
                    out.append("\(pad)\(key(k)): \(b.header)"); out += b.body
                } else { out.append("\(pad)\(key(k)):"); out += lines(val, level: level + 1) }
            }
            return out
        case .array(let items):
            var out: [String] = []
            for item in items {
                if let s = inline(item) { out.append("\(pad)- \(s)"); continue }
                if case .string(let text) = item {
                    let b = block(text, level: level + 1)
                    out.append("\(pad)- \(b.header)"); out += b.body; continue
                }
                var sub = lines(item, level: level + 1)
                // the first line of a nested map/list rides on the dash
                sub[0] = pad + "- " + sub[0].dropFirst((level + 1) * 2)
                out += sub
            }
            return out
        default: return []
        }
    }
}
