import Foundation

public enum TransformError: Error, LocalizedError, Equatable {
    case empty
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .empty: return "The clipboard has no text."
        case .invalid(let m): return m
        }
    }
}

/// Text operations offered as launcher commands; each one reads the clipboard and shows the result.
public enum TextTransform: String, CaseIterable {
    case formatJSON, minifyJSON, jsonToYAML
    case sortLines, sortLinesDescending, reverseLines, dedupeLines, removeEmptyLines, trimWhitespace
    case upper, lower, titleCase
    case escape, unescape
    case joinWithComma, splitCommas
    case statistics

    public var title: String {
        switch self {
        case .formatJSON: return "Format JSON"
        case .minifyJSON: return "Minify JSON"
        case .jsonToYAML: return "Convert JSON to YAML"
        case .sortLines: return "Sort Lines (A→Z)"
        case .sortLinesDescending: return "Sort Lines (Z→A)"
        case .reverseLines: return "Reverse Lines"
        case .dedupeLines: return "Remove Duplicate Lines"
        case .removeEmptyLines: return "Remove Empty Lines"
        case .trimWhitespace: return "Trim Whitespace"
        case .upper: return "Convert to UPPERCASE"
        case .lower: return "Convert to lowercase"
        case .titleCase: return "Convert to Title Case"
        case .escape: return "Escape String"
        case .unescape: return "Unescape String"
        case .joinWithComma: return "Join Lines with Commas"
        case .splitCommas: return "Split Commas into Lines"
        case .statistics: return "Text Statistics (count words, characters, lines)"
        }
    }

    public var keywords: [String] {
        switch self {
        case .formatJSON: return ["json", "format", "pretty", "beautify", "indent"]
        case .minifyJSON: return ["json", "minify", "compact", "compress"]
        case .jsonToYAML: return ["json", "yaml", "yml", "convert", "config"]
        case .sortLines, .sortLinesDescending: return ["sort", "lines", "alphabetical", "order"]
        case .reverseLines: return ["reverse", "lines", "flip"]
        case .dedupeLines: return ["duplicate", "duplicates", "dedupe", "unique", "lines"]
        case .removeEmptyLines: return ["empty", "blank", "lines", "remove"]
        case .trimWhitespace: return ["trim", "whitespace", "spaces", "strip"]
        case .upper: return ["uppercase", "upper", "capital", "case"]
        case .lower: return ["lowercase", "lower", "case"]
        case .titleCase: return ["title", "case", "capitalize"]
        case .escape: return ["escape", "quote", "string", "backslash"]
        case .unescape: return ["unescape", "unquote", "string", "backslash"]
        case .joinWithComma: return ["join", "comma", "csv", "lines"]
        case .splitCommas: return ["split", "comma", "csv", "lines"]
        case .statistics: return ["count", "words", "characters", "length", "lines", "stats", "statistics"]
        }
    }

    public var symbol: String {
        switch self {
        case .formatJSON, .minifyJSON, .jsonToYAML: return "curlybraces"
        case .sortLines, .sortLinesDescending, .reverseLines: return "arrow.up.arrow.down"
        case .dedupeLines, .removeEmptyLines: return "text.line.first.and.arrowtriangle.forward"
        case .trimWhitespace: return "scissors"
        case .upper, .lower, .titleCase: return "textformat"
        case .escape, .unescape: return "quote.opening"
        case .joinWithComma, .splitCommas: return "list.bullet"
        case .statistics: return "number"
        }
    }

    public func apply(_ input: String) -> Result<String, TransformError> {
        guard !input.isEmpty else { return .failure(.empty) }
        switch self {
        case .formatJSON: return Self.json(input, pretty: true)
        case .minifyJSON: return Self.json(input, pretty: false)
        case .jsonToYAML:
            switch OrderedJSONParser.parse(input) {
            case .success(let v): return .success(YAMLEmitter.emit(v))
            case .failure(let f): return .failure(.invalid("Not valid JSON: \(f.message)."))
            }
        case .sortLines: return .success(Self.mapLines(input) { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } })
        case .sortLinesDescending: return .success(Self.mapLines(input) { $0.sorted { $0.localizedStandardCompare($1) == .orderedDescending } })
        case .reverseLines: return .success(Self.mapLines(input) { Array($0.reversed()) })
        case .dedupeLines:
            return .success(Self.mapLines(input) { var seen = Set<String>(); return $0.filter { seen.insert($0).inserted } })
        case .removeEmptyLines: return .success(Self.mapLines(input) { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } })
        case .trimWhitespace: return .success(Self.mapLines(input) { $0.map { $0.trimmingCharacters(in: .whitespaces) } })
        case .upper: return .success(input.uppercased())
        case .lower: return .success(input.lowercased())
        case .titleCase: return .success(input.capitalized)
        case .escape: return .success(Self.escape(input))
        case .unescape: return .success(Self.unescape(input))
        case .joinWithComma:
            let items = Self.splitLines(input).lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .success(items.joined(separator: ", "))
        case .splitCommas:
            return .success(input.split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n"))
        case .statistics:
            let lines = Self.splitLines(input).lines.count
            let words = input.split(whereSeparator: \.isWhitespace).count
            return .success("Characters: \(input.count)\nWords: \(words)\nLines: \(lines)\nBytes (UTF-8): \(input.utf8.count)")
        }
    }

    // MARK: lines

    static func splitLines(_ s: String) -> (lines: [String], trailingNewline: Bool) {
        var lines = s.components(separatedBy: .newlines)
        let trailing = s.hasSuffix("\n") && lines.last == ""
        if trailing { lines.removeLast() }
        return (lines, trailing)
    }

    private static func mapLines(_ s: String, _ f: ([String]) -> [String]) -> String {
        let (lines, trailing) = splitLines(s)
        return f(lines).joined(separator: "\n") + (trailing ? "\n" : "")
    }

    // MARK: JSON (formats the text as written: key order, numbers and escapes are preserved)

    static func json(_ s: String, pretty: Bool) -> Result<String, TransformError> {
        do { _ = try JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]) }
        catch let e as NSError {
            let detail = (e.userInfo[NSDebugDescriptionErrorKey] as? String) ?? e.localizedDescription
            return .failure(.invalid("Not valid JSON: \(detail)"))
        }
        // Newer Foundation parsers are lenient (trailing commas, comments); this tool should be strict JSON.
        if let problem = strictnessProblem(s) { return .failure(.invalid("Not valid JSON: \(problem)")) }
        var out = ""
        var level = 0
        var inString = false, escaped = false
        let chars = Array(s)
        func newline() { out += "\n" + String(repeating: "  ", count: level) }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"": inString = true; out.append(c)
            case "{", "[":
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == (c == "{" ? "}" : "]") { out.append(c); out.append(chars[j]); i = j } // keep {} and [] compact
                else { out.append(c); level += 1; if pretty { newline() } }
            case "}", "]": level -= 1; if pretty { newline() }; out.append(c)
            case ",": out.append(c); if pretty { newline() }
            case ":": out += pretty ? ": " : ":"
            case " ", "\n", "\r", "\t": break
            default: out.append(c)
            }
            i += 1
        }
        return .success(out)
    }

    /// Things strict JSON forbids but lenient parsers accept: trailing commas, comments, single quotes.
    private static func strictnessProblem(_ s: String) -> String? {
        var inString = false, escaped = false, pendingComma = false
        for c in s {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c.isWhitespace { continue }
            if pendingComma, c == "}" || c == "]" { return "trailing comma before “\(c)”." }
            pendingComma = c == ","
            switch c {
            case "\"": inString = true
            case "/": return "comments are not allowed."
            case "'": return "strings must use double quotes."
            default: break
            }
        }
        return nil
    }

    // MARK: escape / unescape

    static func escape(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out += u.value < 0x20 ? String(format: "\\u%04x", u.value) : String(u)
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        let u = Array(s.unicodeScalars)
        var i = 0
        func hex4(_ at: Int) -> UInt32? {
            guard at + 4 <= u.count else { return nil }
            return UInt32(String(String.UnicodeScalarView(u[at..<at + 4])), radix: 16)
        }
        while i < u.count {
            guard u[i] == "\\", i + 1 < u.count else { out.unicodeScalars.append(u[i]); i += 1; continue }
            let n = u[i + 1]
            switch n {
            case "n": out += "\n"; i += 2
            case "r": out += "\r"; i += 2
            case "t": out += "\t"; i += 2
            case "\"", "\\", "/": out.unicodeScalars.append(n); i += 2
            case "u":
                guard let hi = hex4(i + 2) else { out += "\\u"; i += 2; continue }
                if (0xD800...0xDBFF).contains(hi), i + 12 <= u.count, u[i + 6] == "\\", u[i + 7] == "u", let lo = hex4(i + 8), (0xDC00...0xDFFF).contains(lo),
                   let scalar = Unicode.Scalar(0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)) {
                    out.unicodeScalars.append(scalar); i += 12
                } else if let scalar = Unicode.Scalar(hi) {
                    out.unicodeScalars.append(scalar); i += 6
                } else { out += "\\u"; i += 2 }
            default: out += "\\"; i += 1 // unknown escape: keep the backslash
            }
        }
        return out
    }
}
