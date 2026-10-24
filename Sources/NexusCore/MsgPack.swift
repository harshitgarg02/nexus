import Foundation

/// MessagePack <-> JSON. JSON can't say "bytes" or "extension", so `bin` decodes to `"base64:…"` and
/// `ext` to `"ext<type>:<hex>"`. Integers pack to the smallest encoding; other numbers pack as float64 (like Python's packb).
enum MsgPack {
    struct Failure: Error { let message: String }

    static func decode(_ data: Data) -> Result<JSONValue, Failure> {
        var r = Reader(bytes: [UInt8](data))
        do {
            let v = try r.value(depth: 0)
            guard r.i == r.bytes.count else { throw Failure(message: "\(r.bytes.count - r.i) trailing bytes") }
            return .success(v)
        } catch let f as Failure { return .failure(f) } catch { return .failure(Failure(message: "unreadable")) }
    }

    static func encode(_ v: JSONValue) -> Data {
        var out = [UInt8]()
        write(v, to: &out)
        return Data(out)
    }

    /// Compact JSON text for a decoded value.
    static func json(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return "\"" + TextTransform.escape(s) + "\""
        case .array(let a): return "[" + a.map(json).joined(separator: ",") + "]"
        case .object(let o): return "{" + o.map { "\"" + TextTransform.escape($0.key) + "\":" + json($0.value) }.joined(separator: ",") + "}"
        }
    }

    // MARK: decode

    private struct Reader {
        let bytes: [UInt8]
        var i = 0

        mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, n <= bytes.count - i else { throw Failure(message: "truncated at byte \(i)") }
            defer { i += n }
            return bytes[i..<i + n]
        }
        mutating func uint(_ n: Int) throws -> UInt64 { try take(n).reduce(0) { $0 << 8 | UInt64($1) } }
        mutating func int(_ n: Int) throws -> Int64 {
            let shift = 64 - 8 * n
            return Int64(bitPattern: try uint(n) << UInt64(shift)) >> shift
        }
        mutating func length(_ n: Int) throws -> Int { Int(clamping: try uint(n)) }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < 100 else { throw Failure(message: "nested too deeply") }
            let b = try take(1).first!
            switch b {
            case 0x00...0x7f: return .number(String(b))
            case 0x80...0x8f: return try map(Int(b & 0x0f), depth)
            case 0x90...0x9f: return try array(Int(b & 0x0f), depth)
            case 0xa0...0xbf: return try string(Int(b & 0x1f))
            case 0xc0: return .null
            case 0xc2: return .bool(false)
            case 0xc3: return .bool(true)
            case 0xc4...0xc6: return .string("base64:" + (try take(try length(1 << Int(b - 0xc4)))).withBase64())
            case 0xc7...0xc9: return try ext(try length(1 << Int(b - 0xc7)))
            case 0xca:
                let f = Float(bitPattern: UInt32(try uint(4)))
                return .number(f.isFinite ? "\(f)" : "\"\(f)\"")
            case 0xcb:
                let d = Double(bitPattern: try uint(8))
                return .number(d.isFinite ? "\(d)" : "\"\(d)\"")
            case 0xcc...0xcf: return .number(String(try uint(1 << Int(b - 0xcc))))
            case 0xd0...0xd3: return .number(String(try int(1 << Int(b - 0xd0))))
            case 0xd4...0xd8: return try ext(1 << Int(b - 0xd4))
            case 0xd9...0xdb: return try string(try length(1 << Int(b - 0xd9)))
            case 0xdc, 0xdd: return try array(try length(2 << Int(b - 0xdc)), depth)
            case 0xde, 0xdf: return try map(try length(2 << Int(b - 0xde)), depth)
            case 0xe0...0xff: return .number(String(Int8(bitPattern: b)))
            default: throw Failure(message: "invalid type byte 0xc1")
            }
        }

        mutating func string(_ n: Int) throws -> JSONValue {
            guard let s = String(bytes: try take(n), encoding: .utf8) else { throw Failure(message: "string isn't UTF-8") }
            return .string(s)
        }

        mutating func ext(_ n: Int) throws -> JSONValue {
            let type = Int8(bitPattern: try take(1).first!)
            return .string("ext\(type):" + (try take(n)).map { String(format: "%02x", $0) }.joined())
        }

        mutating func array(_ n: Int, _ depth: Int) throws -> JSONValue {
            var out = [JSONValue]()
            for _ in 0..<n { out.append(try value(depth: depth + 1)) }
            return .array(out)
        }

        mutating func map(_ n: Int, _ depth: Int) throws -> JSONValue {
            var out = [(key: String, value: JSONValue)]()
            for _ in 0..<n {
                let k = try value(depth: depth + 1)
                if case .string(let s) = k { out.append((s, try value(depth: depth + 1))) } // non-string keys keep their JSON text
                else { out.append((MsgPack.json(k), try value(depth: depth + 1))) }
            }
            return .object(out)
        }
    }

    // MARK: encode

    private static func be(_ v: UInt64, _ n: Int, to out: inout [UInt8]) {
        for s in stride(from: 8 * (n - 1), through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: v >> UInt64(s))) }
    }

    private static func header(_ n: Int, fix: (max: Int, tag: UInt8), sizes: [(tag: UInt8, bytes: Int)], to out: inout [UInt8]) {
        if n <= fix.max { out.append(fix.tag | UInt8(n)); return }
        let s = sizes.first { n < 1 << (8 * $0.bytes) } ?? sizes.last!
        out.append(s.tag)
        be(UInt64(n), s.bytes, to: &out)
    }

    private static func write(_ v: JSONValue, to out: inout [UInt8]) {
        switch v {
        case .null: out.append(0xc0)
        case .bool(let b): out.append(b ? 0xc3 : 0xc2)
        case .number(let n):
            if let i = Int64(n) { writeInt(i, to: &out) }
            else if let u = UInt64(n) { out.append(0xcf); be(u, 8, to: &out) }
            else { out.append(0xcb); be(Double(n)?.bitPattern ?? 0, 8, to: &out) }
        case .string(let s):
            let u = Array(s.utf8)
            header(u.count, fix: (31, 0xa0), sizes: [(0xd9, 1), (0xda, 2), (0xdb, 4)], to: &out)
            out += u
        case .array(let a):
            header(a.count, fix: (15, 0x90), sizes: [(0xdc, 2), (0xdd, 4)], to: &out)
            for e in a { write(e, to: &out) }
        case .object(let o):
            header(o.count, fix: (15, 0x80), sizes: [(0xde, 2), (0xdf, 4)], to: &out)
            for (k, e) in o { write(.string(k), to: &out); write(e, to: &out) }
        }
    }

    private static func writeInt(_ i: Int64, to out: inout [UInt8]) {
        switch i {
        case 0...0x7f: out.append(UInt8(i))
        case 0x80...0xff: out.append(0xcc); be(UInt64(i), 1, to: &out)
        case 0x100...0xffff: out.append(0xcd); be(UInt64(i), 2, to: &out)
        case 0x10000...0xffff_ffff: out.append(0xce); be(UInt64(i), 4, to: &out)
        case 0x1_0000_0000...: out.append(0xcf); be(UInt64(i), 8, to: &out)
        case -32...(-1): out.append(UInt8(bitPattern: Int8(i)))
        case -128...(-33): out.append(0xd0); be(UInt64(bitPattern: i), 1, to: &out)
        case -32768...(-129): out.append(0xd1); be(UInt64(bitPattern: i), 2, to: &out)
        case Int64(Int32.min)...(-32769): out.append(0xd2); be(UInt64(bitPattern: i), 4, to: &out)
        default: out.append(0xd3); be(UInt64(bitPattern: i), 8, to: &out)
        }
    }
}

private extension ArraySlice where Element == UInt8 {
    func withBase64() -> String { Data(self).base64EncodedString() }
}
