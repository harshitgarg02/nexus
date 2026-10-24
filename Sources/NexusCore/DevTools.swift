import Foundation
import CryptoKit

// MARK: - Base64

public enum Base64Tools {
    public static func encode(_ data: Data, urlSafe: Bool = false) -> String {
        let s = data.base64EncodedString()
        guard urlSafe else { return s }
        return s.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Accepts standard and URL-safe alphabets, missing padding, and stray whitespace.
    public static func decode(_ text: String) -> Data? {
        var s = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }) else { return nil }
        s = s.replacingOccurrences(of: "=", with: "")
        guard s.count % 4 != 1 else { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}

// MARK: - URL encoding

public enum URLTools {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encodes everything except RFC 3986 unreserved characters (like JavaScript's encodeURIComponent, but stricter).
    public static func encode(_ s: String, spaceAsPlus: Bool = false) -> String {
        let e = s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
        return spaceAsPlus ? e.replacingOccurrences(of: "%20", with: "+") : e
    }

    public static func decode(_ s: String, plusAsSpace: Bool = false) -> String? {
        (plusAsSpace ? s.replacingOccurrences(of: "+", with: " ") : s).removingPercentEncoding
    }
}

// MARK: - Hashes

public enum Hashes {
    public enum Algorithm: String, CaseIterable {
        case md5, sha1, sha256, sha512
        public var label: String { rawValue == "md5" ? "MD5" : rawValue.uppercased() }
    }

    public static func hex(_ a: Algorithm, _ data: Data) -> String {
        func h<D: Digest>(_ d: D) -> String { d.map { String(format: "%02x", $0) }.joined() }
        switch a {
        case .md5: return h(Insecure.MD5.hash(data: data))
        case .sha1: return h(Insecure.SHA1.hash(data: data))
        case .sha256: return h(SHA256.hash(data: data))
        case .sha512: return h(SHA512.hash(data: data))
        }
    }
}

// MARK: - JWT (decode only; the signature is never verified)

public struct DecodedJWT {
    public let header: [String: Any]
    public let payload: [String: Any]
    public let signature: String
}

public enum JWTTools {
    private static let shape = try! NSRegularExpression(pattern: #"^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$"#)

    public static func looksLikeJWT(_ s: String) -> Bool {
        shape.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    public static func decode(_ token: String) -> DecodedJWT? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeJWT(t) else { return nil }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let h = Base64Tools.decode(parts[0]), let p = Base64Tools.decode(parts[1]),
              let header = (try? JSONSerialization.jsonObject(with: h)) as? [String: Any],
              let payload = (try? JSONSerialization.jsonObject(with: p)) as? [String: Any] else { return nil }
        return DecodedJWT(header: header, payload: payload, signature: parts[2])
    }

    public static func json(_ obj: [String: Any], pretty: Bool) -> String {
        let opts: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: obj, options: opts)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

// MARK: - Colors

public struct RGBA: Equatable {
    public var r: Double, g: Double, b: Double, a: Double // 0...1

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    public static func parse(_ text: String) -> RGBA? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var h = String(s.dropFirst())
            guard h.allSatisfy(\.isHexDigit) else { return nil }
            if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
            let hasA = h.count == 8
            let rgb = hasA ? v >> 8 : v
            return RGBA(r: Double((rgb >> 16) & 255) / 255, g: Double((rgb >> 8) & 255) / 255, b: Double(rgb & 255) / 255,
                        a: hasA ? Double(v & 255) / 255 : 1)
        }
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let fn = s[..<open].trimmingCharacters(in: .whitespaces)
        let body = s[s.index(after: open)..<s.index(before: s.endIndex)]
        let nums = body.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "%°")) }.compactMap(Double.init)
        guard nums.count == 3 || nums.count == 4 else { return nil }
        let a = nums.count == 4 ? max(0, min(1, nums[3] > 1 ? nums[3] / 100 : nums[3])) : 1
        switch fn {
        case "rgb", "rgba":
            guard nums[0...2].allSatisfy({ (0...255).contains($0) }) else { return nil }
            return RGBA(r: nums[0] / 255, g: nums[1] / 255, b: nums[2] / 255, a: a)
        case "hsl", "hsla":
            guard (0...360).contains(nums[0]), (0...100).contains(nums[1]), (0...100).contains(nums[2]) else { return nil }
            return fromHSL(h: nums[0], s: nums[1] / 100, l: nums[2] / 100, a: a)
        default: return nil
        }
    }

    static func fromHSL(h: Double, s: Double, l: Double, a: Double) -> RGBA {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return RGBA(r: r1 + m, g: g1 + m, b: b1 + m, a: a)
    }

    var bytes: (Int, Int, Int) { (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }

    public var hex: String {
        let (r, g, b) = bytes
        let base = String(format: "#%02X%02X%02X", r, g, b)
        return a < 1 ? base + String(format: "%02X", Int((a * 255).rounded())) : base
    }

    public var rgbString: String {
        let (r, g, b) = bytes
        return a < 1 ? "rgba(\(r), \(g), \(b), \(Self.trim(a)))" : "rgb(\(r), \(g), \(b))"
    }

    public var hslString: String {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if d > 0 {
            s = d / (1 - abs(2 * l - 1))
            switch mx {
            case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let (hh, ss, ll) = (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
        return a < 1 ? "hsla(\(hh), \(ss)%, \(ll)%, \(Self.trim(a)))" : "hsl(\(hh), \(ss)%, \(ll)%)"
    }

    public var swiftUIString: String {
        let c = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f", r, g, b)
        return a < 1 ? c + ", opacity: \(Self.trim(a)))" : c + ")"
    }

    private static func trim(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
}

// MARK: - Case conversion

public enum CaseTools {
    /// Splits on separators, lower→Upper boundaries and acronym ends: "getHTTPResponse_code" → get, HTTP, Response, code.
    public static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            guard c.isLetter || c.isNumber else { if !cur.isEmpty { out.append(cur); cur = "" }; continue }
            if !cur.isEmpty, c.isUppercase {
                let prev = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) { out.append(cur); cur = "" }
            }
            cur.append(c)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func cap(_ w: String) -> String { w.prefix(1).uppercased() + w.dropFirst().lowercased() }

    public static func camel(_ s: String) -> String { let w = words(s); return (w.first?.lowercased() ?? "") + w.dropFirst().map(cap).joined() }
    public static func pascal(_ s: String) -> String { words(s).map(cap).joined() }
    public static func snake(_ s: String) -> String { words(s).map { $0.lowercased() }.joined(separator: "_") }
    public static func kebab(_ s: String) -> String { words(s).map { $0.lowercased() }.joined(separator: "-") }
    public static func constant(_ s: String) -> String { words(s).map { $0.uppercased() }.joined(separator: "_") }
    public static func title(_ s: String) -> String { words(s).map(cap).joined(separator: " ") }
    public static func lower(_ s: String) -> String { words(s).map { $0.lowercased() }.joined(separator: " ") }
    public static func upper(_ s: String) -> String { words(s).map { $0.uppercased() }.joined(separator: " ") }
}
