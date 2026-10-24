import Foundation

public struct RegexFlags: Equatable {
    public var ignoreCase = false
    public var multiline = false   // ^ and $ match at line boundaries
    public var dotAll = false      // . matches newlines

    public init(ignoreCase: Bool = false, multiline: Bool = false, dotAll: Bool = false) {
        self.ignoreCase = ignoreCase; self.multiline = multiline; self.dotAll = dotAll
    }

    /// "gi" style letters: i, m, s; g is accepted (always global) and anything else is ignored.
    public init(letters: String) {
        ignoreCase = letters.contains("i"); multiline = letters.contains("m"); dotAll = letters.contains("s")
    }
}

public struct RegexMatch: Equatable {
    public let range: NSRange
    public let text: String
    /// Capture groups 1…n; nil when the group didn't take part in the match.
    public let groups: [String?]
    public let named: [(name: String, text: String?)]

    public static func == (a: RegexMatch, b: RegexMatch) -> Bool {
        a.range == b.range && a.text == b.text && a.groups == b.groups
    }
}

public enum RegexTool {
    public static let matchLimit = 500
    private static let nameFinder = try! NSRegularExpression(pattern: #"\(\?<([A-Za-z][A-Za-z0-9]*)>"#)

    public static func matches(pattern: String, flags: RegexFlags = RegexFlags(), in text: String) -> Result<[RegexMatch], TransformError> {
        guard !pattern.isEmpty else { return .success([]) }
        var opts: NSRegularExpression.Options = []
        if flags.ignoreCase { opts.insert(.caseInsensitive) }
        if flags.multiline { opts.insert(.anchorsMatchLines) }
        if flags.dotAll { opts.insert(.dotMatchesLineSeparators) }
        let re: NSRegularExpression
        do { re = try NSRegularExpression(pattern: pattern, options: opts) }
        catch { return .failure(.invalid("Invalid pattern: " + ((error as NSError).userInfo[NSLocalizedFailureReasonErrorKey] as? String ?? error.localizedDescription))) }

        let ns = text as NSString
        let names = nameFinder.matches(in: pattern, range: NSRange(location: 0, length: (pattern as NSString).length))
            .map { (pattern as NSString).substring(with: $0.range(at: 1)) }
        var out: [RegexMatch] = []
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m else { return }
            func sub(_ r: NSRange) -> String? { r.location == NSNotFound ? nil : ns.substring(with: r) }
            out.append(RegexMatch(range: m.range, text: ns.substring(with: m.range),
                                  groups: (m.numberOfRanges > 1 ? Array(1..<m.numberOfRanges) : []).map { sub(m.range(at: $0)) },
                                  named: names.map { ($0, sub(m.range(withName: $0))) }))
            if out.count >= matchLimit { stop.pointee = true }
        }
        return .success(out)
    }

    /// `/pattern/flags some text` → its parts. The closing slash is the first one not escaped with a backslash.
    public static func parseTyped(_ s: String) -> (pattern: String, flags: RegexFlags, text: String)? {
        let chars = Array(s)
        guard chars.first == "/" else { return nil }
        var i = 1, escaped = false
        while i < chars.count {
            if escaped { escaped = false } else if chars[i] == "\\" { escaped = true } else if chars[i] == "/" { break }
            i += 1
        }
        guard i < chars.count, i > 1 else { return nil }
        let pattern = String(chars[1..<i])
        var j = i + 1
        var letters = ""
        while j < chars.count, chars[j].isLetter { letters.append(chars[j]); j += 1 }
        let rest = String(chars[j...]).drop(while: { $0 == " " })
        return (pattern, RegexFlags(letters: letters), String(rest))
    }
}
