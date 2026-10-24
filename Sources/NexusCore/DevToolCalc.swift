import Foundation

/// Developer one-liners typed in the launcher: `base64 hello`, `unbase64 …`, `urlencode …`, `urldecode …`,
/// `sha256 …` (also md5, sha1, sha512, `hash`), `jwt <token>`, `packb {"a":1}` / `unpackb 81a16101` (MessagePack, hex or base64), `camel my var`, `case my var`,
/// and pasting a JWT or a `#ff5733` / `rgb(…)` / `hsl(…)` colour directly.
/// A keyword only triggers with text after it, so a bare word still searches apps.
enum DevToolCalc {
    static func rows(_ input: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if JWTTools.looksLikeJWT(text), let r = jwtRows(text, now: now, timeZone: timeZone) { return r }
        if text.hasPrefix("#") || text.contains("("), let c = RGBA.parse(text) { return colorRows(c) }

        if text.lowercased() == "lorem" { return loremRows("", now: now) }
        if text.lowercased() == "netinfo" { return NetworkInfo.liveRows(now: now) }
        // a bare cron expression ("*/5 * * * *", "@daily"): five fields with a * or / in them
        if text.hasPrefix("@") || (text.split(separator: " ").count == 5 && (text.contains("*") || text.contains("/"))),
           case .success = CronSchedule.parse(text) { return cronRows(text, now: now, timeZone: timeZone) }

        guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let key = text[..<space].lowercased()
        let payload = text[space...].trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }

        switch key {
        case "base64", "b64":
            let d = Data(payload.utf8)
            return [CalcRow(title: Base64Tools.encode(d), subtitle: "Base64"),
                    CalcRow(title: Base64Tools.encode(d, urlSafe: true), subtitle: "Base64 URL-safe, no padding")]
        case "unbase64", "b64d", "base64d":
            guard let d = Base64Tools.decode(payload) else { return nil }
            if let s = String(data: d, encoding: .utf8) { return [CalcRow(title: s, subtitle: "Decoded (UTF-8)")] }
            let hex = d.map { String(format: "%02x", $0) }.joined()
            return [CalcRow(title: hex, subtitle: "Decoded: \(d.count) bytes, not text (hex)")]
        case "urlencode", "urle":
            return [CalcRow(title: URLTools.encode(payload), subtitle: "Percent-encoded"),
                    CalcRow(title: URLTools.encode(payload, spaceAsPlus: true), subtitle: "Form-encoded (space as +)")]
        case "urldecode", "urld":
            guard let plain = URLTools.decode(payload) else { return nil }
            var out = [CalcRow(title: plain, subtitle: "Percent-decoded")]
            if payload.contains("+"), let form = URLTools.decode(payload, plusAsSpace: true) {
                out.append(CalcRow(title: form, subtitle: "Form-decoded (+ as space)"))
            }
            return out
        case "hash":
            return Hashes.Algorithm.allCases.map { CalcRow(title: Hashes.hex($0, Data(payload.utf8)), subtitle: $0.label) }
        case "md5", "sha1", "sha256", "sha512":
            let a = Hashes.Algorithm(rawValue: String(key))!
            return [CalcRow(title: Hashes.hex(a, Data(payload.utf8)), subtitle: a.label)]
        case "jwt":
            return jwtRows(payload, now: now, timeZone: timeZone)
        case "packb":
            guard case .success(let v) = OrderedJSONParser.parse(payload) else { return nil }
            let d = MsgPack.encode(v)
            return [CalcRow(title: hex(d), subtitle: "MessagePack hex · \(d.count) bytes"),
                    CalcRow(title: pythonLiteral(d), subtitle: "Python bytes literal"),
                    CalcRow(title: Base64Tools.encode(d), subtitle: "MessagePack Base64")]
        case "unpackb":
            return unpackRows(payload)
        case "http":
            let found = HTTPStatus.lookup(payload).prefix(10)
            return found.isEmpty ? nil : found.map { CalcRow(title: "\($0.code) \($0.name)", subtitle: "\($0.category) · \($0.meaning)") }
        case "base": return baseRows(payload)
        case "lorem": return loremRows(payload, now: now)
        case "cron": return cronRows(payload, now: now, timeZone: timeZone)
        case "regex": return regexRows(payload)
        case "case":
            return [("camelCase", CaseTools.camel), ("PascalCase", CaseTools.pascal), ("snake_case", CaseTools.snake),
                    ("kebab-case", CaseTools.kebab), ("CONSTANT_CASE", CaseTools.constant), ("Title Case", CaseTools.title),
                    ("lower case", CaseTools.lower), ("UPPER CASE", CaseTools.upper)]
                .map { CalcRow(title: $0.1(payload), subtitle: $0.0) }
        case "camel": return [CalcRow(title: CaseTools.camel(payload), subtitle: "camelCase")]
        case "pascal": return [CalcRow(title: CaseTools.pascal(payload), subtitle: "PascalCase")]
        case "snake": return [CalcRow(title: CaseTools.snake(payload), subtitle: "snake_case")]
        case "kebab": return [CalcRow(title: CaseTools.kebab(payload), subtitle: "kebab-case")]
        case "constant": return [CalcRow(title: CaseTools.constant(payload), subtitle: "CONSTANT_CASE")]
        default: return nil
        }
    }

    // MARK: MessagePack

    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// What Python's `repr(bytes)` prints: printable ASCII as itself, everything else as `\xNN`.
    private static func pythonLiteral(_ d: Data) -> String {
        let quote: UInt8 = d.contains(0x27) && !d.contains(0x22) ? 0x22 : 0x27 // Python switches to " when the data has only '
        let body = d.map { b -> String in
            switch b {
            case quote: return "\\" + String(UnicodeScalar(b))
            case 0x5c: return "\\\\"
            case 9: return "\\t"
            case 10: return "\\n"
            case 13: return "\\r"
            case 0x20...0x7e: return String(UnicodeScalar(b))
            default: return String(format: "\\x%02x", b)
            }
        }.joined()
        let q = String(UnicodeScalar(quote))
        return "b" + q + body + q
    }

    /// A Python bytes repr: `\x81\xa1a\x01`, with printable characters standing for themselves; `b'…'` quotes are optional.
    private static func pythonBytes(_ s: String) -> [UInt8]? {
        var t = Substring(s)
        if t.hasPrefix("b'") || t.hasPrefix("b\""), let q = t.last, q == t[t.index(after: t.startIndex)] { t = t.dropFirst(2).dropLast() }
        var out = [UInt8](), it = t.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out += Array(String(c).utf8); continue }
            switch it.next() {
            case "x":
                guard let a = it.next(), let b = it.next(), let v = UInt8(String([a, b]), radix: 16) else { return nil }
                out.append(v)
            case "n": out.append(10)
            case "r": out.append(13)
            case "t": out.append(9)
            case "\\": out.append(0x5c)
            case "'": out.append(0x27)
            case "\"": out.append(0x22)
            default: return nil
            }
        }
        return out
    }

    /// Input is hex (`81a16101`, `0x81 a1 61 01`), a Python bytes repr (`\x81\xa1a\x01`), or Base64.
    private static func unpackRows(_ payload: String) -> [CalcRow]? {
        var h = payload.filter { !$0.isWhitespace && $0 != "," }
        if h.lowercased().hasPrefix("0x") { h.removeFirst(2) }
        let isHex = !h.isEmpty && h.count % 2 == 0 && h.allSatisfy(\.isHexDigit)
        let bytes: Data
        var kind = isHex ? "hex" : "Base64"
        if payload.contains("\\x"), let b = pythonBytes(payload) {
            bytes = Data(b); kind = "bytes literal"
        } else if isHex {
            bytes = Data(stride(from: 0, to: h.count, by: 2).map { k -> UInt8 in
                let a = h.index(h.startIndex, offsetBy: k)
                return UInt8(h[a..<h.index(a, offsetBy: 2)], radix: 16)!
            })
        } else if let d = Base64Tools.decode(payload) { bytes = d } else { return nil }
        guard case .success(let v) = MsgPack.decode(bytes) else { return nil }
        let compact = MsgPack.json(v)
        var rows = [CalcRow(title: compact, subtitle: "Decoded MessagePack · \(bytes.count) bytes (\(kind))")]
        if case .success(let pretty) = TextTransform.json(compact, pretty: true), pretty.contains("\n") {
            rows.append(CalcRow(title: "Copy formatted JSON", subtitle: "Pretty-printed · \(pretty.split(separator: "\n").count) lines", copy: pretty))
        }
        return rows
    }

    // MARK: number base

    private static func baseRows(_ payload: String) -> [CalcRow]? {
        let t = payload.split(separator: " ").map(String.init)
        guard (1...2).contains(t.count) else { return nil }
        var radix: Int?
        if t.count == 2 {
            switch t[1].lowercased() {
            case "hex": radix = 16
            case "bin": radix = 2
            case "oct": radix = 8
            case "dec": radix = 10
            default: radix = Int(t[1])
            }
            guard radix != nil else { return nil }
        }
        guard let v = NumberBase.parse(t[0], radix: radix) else { return nil }
        return [CalcRow(title: v.string(radix: 10), subtitle: "Decimal"),
                CalcRow(title: v.string(radix: 16, prefix: "0x", uppercase: true), subtitle: "Hexadecimal"),
                CalcRow(title: v.string(radix: 2, prefix: "0b"), subtitle: "Binary"),
                CalcRow(title: v.string(radix: 8, prefix: "0o"), subtitle: "Octal"),
                CalcRow(title: v.string(radix: 36), subtitle: "Base 36")]
    }

    // MARK: lorem ipsum

    /// `lorem`, `lorem 3`, `lorem 40 words`, `lorem 2 sentences`, `lorem 4 paragraphs`
    private static func loremRows(_ payload: String, now: Date) -> [CalcRow]? {
        let t = payload.lowercased().split(separator: " ").map(String.init)
        guard t.count <= 2 else { return nil }
        let n = t.first.flatMap(Int.init) ?? (t.isEmpty ? 1 : nil)
        guard let n, n >= 1 else { return nil }
        let unit = t.count == 2 ? t[1] : "paragraphs"
        let text: String, label: String
        switch unit {
        case "p", "paragraph", "paragraphs":
            let p = Lorem.paragraphs(n)
            text = p.joined(separator: "\n\n"); label = "\(p.count) paragraph\(p.count == 1 ? "" : "s")"
        case "w", "word", "words":
            text = Lorem.words(n); label = "\(min(n, Lorem.maxWords)) words"
        case "s", "sentence", "sentences":
            text = Lorem.sentences(n); label = "\(min(n, 200)) sentence\(n == 1 ? "" : "s")"
        default: return nil
        }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let preview = text.replacingOccurrences(of: "\n\n", with: " ¶ ")
        return [CalcRow(title: String(preview.prefix(90)) + (preview.count > 90 ? "…" : ""),
                        subtitle: "Lorem ipsum · \(label) · \(words) words", copy: text)]
    }

    // MARK: cron

    private static func cronRows(_ expr: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        switch CronSchedule.parse(expr) {
        case .failure(let e):
            return [CalcRow(title: e.localizedDescription, subtitle: "Not a valid cron expression", copy: "")]
        case .success(let s):
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "EEE d MMM yyyy, HH:mm zzz"
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .full
            let iso = ISO8601DateFormatter()
            iso.timeZone = timeZone
            var out = [CalcRow(title: s.describe(), subtitle: "In plain English")]
            let runs = s.nextRuns(after: now, count: 5, calendar: cal)
            if runs.isEmpty { out.append(CalcRow(title: "Never runs", subtitle: "No matching date in the next 8 years", copy: "")) }
            for (i, d) in runs.enumerated() {
                out.append(CalcRow(title: f.string(from: d), subtitle: "Run \(i + 1) · \(rel.localizedString(for: d, relativeTo: now))", copy: iso.string(from: d)))
            }
            return out
        }
    }

    // MARK: regex (typed form: regex /pattern/flags text)

    private static func regexRows(_ payload: String) -> [CalcRow]? {
        guard let p = RegexTool.parseTyped(payload) else {
            return [CalcRow(title: "Usage: regex /pattern/flags your text", subtitle: "Flags: i ignore case, m multiline, s dot matches newline", copy: "")]
        }
        let label = "/\(p.pattern)/"
        switch RegexTool.matches(pattern: p.pattern, flags: p.flags, in: p.text) {
        case .failure(let e): return [CalcRow(title: e.localizedDescription, subtitle: label, copy: "")]
        case .success(let m):
            guard !m.isEmpty else { return [CalcRow(title: "No matches", subtitle: label, copy: "")] }
            var out = [CalcRow(title: "\(m.count) match\(m.count == 1 ? "" : "es")", subtitle: label, copy: m.map(\.text).joined(separator: "\n"))]
            for (i, x) in m.prefix(10).enumerated() {
                let groups = x.groups.enumerated().map { "$\($0.offset + 1)=\($0.element ?? "∅")" } + x.named.map { "\($0.name)=\($0.text ?? "∅")" }
                out.append(CalcRow(title: x.text.isEmpty ? "(empty match)" : x.text,
                                   subtitle: (["#\(i + 1)", "\(x.range.location)–\(x.range.location + x.range.length)"] + groups).joined(separator: " · "),
                                   copy: x.text))
            }
            return out
        }
    }

    // MARK: colour

    private static func colorRows(_ c: RGBA) -> [CalcRow] {
        [CalcRow(title: c.hex, subtitle: "Hex"), CalcRow(title: c.rgbString, subtitle: "RGB"),
         CalcRow(title: c.hslString, subtitle: "HSL"), CalcRow(title: c.swiftUIString, subtitle: "SwiftUI")]
    }

    // MARK: JWT

    private static func jwtRows(_ token: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        guard let jwt = JWTTools.decode(token) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "EEE d MMM yyyy, h:mm:ss a zzz"
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone

        func claim(_ key: String, _ label: (Bool) -> String) -> CalcRow? {
            guard let secs = (jwt.payload[key] as? NSNumber)?.doubleValue else { return nil }
            let d = Date(timeIntervalSince1970: secs)
            return CalcRow(title: f.string(from: d), subtitle: "\(label(d <= now)) \(rel.localizedString(for: d, relativeTo: now))",
                           copy: iso.string(from: d))
        }
        var out: [CalcRow] = []
        if let exp = claim("exp", { $0 ? "Expired" : "Expires" }) { out.append(exp) }
        out.append(CalcRow(title: JWTTools.json(jwt.payload, pretty: false), subtitle: "Payload", copy: JWTTools.json(jwt.payload, pretty: true)))
        out.append(CalcRow(title: JWTTools.json(jwt.header, pretty: false), subtitle: "Header", copy: JWTTools.json(jwt.header, pretty: true)))
        if let iat = claim("iat", { _ in "Issued" }) { out.append(iat) }
        if let nbf = claim("nbf", { $0 ? "Valid since" : "Not valid before" }) { out.append(nbf) }
        out.append(CalcRow(title: "Signature not verified", subtitle: "Decoded locally; the token is never sent anywhere", copy: jwt.signature))
        return out
    }
}
