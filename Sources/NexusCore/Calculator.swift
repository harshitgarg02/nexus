import Foundation

public struct CalcRow: Equatable {
    public let title: String
    public let subtitle: String
    public let copy: String
    /// A freshly generated value (uuid, password…): the UI offers "Generate Another".
    public let generated: Bool

    public init(title: String, subtitle: String, copy: String? = nil, generated: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.copy = copy ?? title
        self.generated = generated
    }
}

public enum Calculator {
    /// Rows for a query, best first. Empty when the input isn't a calculation.
    public static func evaluate(_ raw: String, now: Date = Date(), timeZone: TimeZone = .current,
                                currency: CurrencyState = .disabled) -> [CalcRow] {
        let input = raw.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return [] }
        if let rows = EpochCalc.rows(input, timeZone: timeZone, now: now) { return rows }
        if let rows = GeneratorCalc.rows(input, now: now, timeZone: timeZone) { return rows }
        if let rows = DevToolCalc.rows(input, now: now, timeZone: timeZone) { return rows }
        if let rows = DateCalc.rows(input, now: now, timeZone: timeZone) { return rows }
        if let rows = UnitCalc.rows(input) { return rows }
        if let rows = CurrencyCalc.rows(input, state: currency, now: now) { return rows }
        return MathCalc.rows(input)
    }

    // MARK: formatting

    static func format(_ v: Double, grouped: Bool = true) -> String {
        if v.isNaN || v.isInfinite { return "NaN" }
        if v == v.rounded(), abs(v) < 1e15 {
            return grouped ? groupFmt.string(from: NSNumber(value: v)) ?? "\(Int64(v))" : "\(Int64(v))"
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.usesGroupingSeparator = grouped
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private static let groupFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()
}

// MARK: - Math

enum MathCalc {
    struct Failure: Error {}

    static func rows(_ input: String) -> [CalcRow] {
        var s = input
        var radix: (Int, String)?
        let lower = input.lowercased()
        for (suffix, r, label) in [(" to hex", 16, "hex"), (" to bin", 2, "binary"), (" to oct", 8, "octal")] where lower.hasSuffix(suffix) {
            s = String(input.dropLast(suffix.count))
            radix = (r, label)
        }
        guard s.contains(where: \.isNumber) else { return [] }
        var p = Parser(tokens: tokenize(s))
        guard let v = try? p.parseAll(), p.sawOperation || radix != nil, !v.isNaN else { return [] }
        if let (r, label) = radix, v == v.rounded(), abs(v) < 9e18 {
            let prefix = r == 16 ? "0x" : r == 2 ? "0b" : "0o"
            let str = prefix + String(Int64(v), radix: r)
            return [CalcRow(title: str, subtitle: label)]
        }
        return [CalcRow(title: Calculator.format(v), subtitle: input, copy: Calculator.format(v, grouped: false))]
    }

    enum Tok: Equatable { case num(Double), id(String), op(Character) }

    static func tokenize(_ s: String) -> [Tok] {
        var out: [Tok] = []
        let c = Array(s.lowercased())
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == " " { i += 1; continue }
            if ch.isNumber || (ch == "." && i + 1 < c.count && c[i + 1].isNumber) {
                if ch == "0", i + 1 < c.count, c[i + 1] == "x" {
                    var j = i + 2
                    while j < c.count, c[j].isHexDigit { j += 1 }
                    out.append(.num(Double(Int64(String(c[(i + 2)..<j]), radix: 16) ?? 0)))
                    i = j; continue
                }
                var j = i
                var txt = ""
                while j < c.count {
                    if c[j].isNumber || c[j] == "." { txt.append(c[j]) }
                    else if c[j] == ",", j + 3 < c.count, c[(j + 1)...(j + 3)].allSatisfy(\.isNumber) { }
                    else { break }
                    j += 1
                }
                var v = Double(txt) ?? .nan
                if j < c.count, c[j] == "k", !(j + 1 < c.count && c[j + 1].isLetter) { v *= 1000; j += 1 }
                out.append(.num(v))
                i = j; continue
            }
            if ch.isLetter {
                var j = i
                while j < c.count, c[j].isLetter { j += 1 }
                out.append(.id(String(c[i..<j])))
                i = j; continue
            }
            switch ch {
            case "×": out.append(.op("*"))
            case "÷": out.append(.op("/"))
            case "+", "-", "*", "/", "^", "(", ")", "%": out.append(.op(ch))
            default: out.append(.op("?"))
            }
            i += 1
        }
        return out
    }

    struct Val { var v: Double; var pct = false }

    struct Parser {
        let tokens: [Tok]
        var pos = 0
        var sawOperation = false
        init(tokens: [Tok]) { self.tokens = tokens }

        var peek: Tok? { pos < tokens.count ? tokens[pos] : nil }
        mutating func next() -> Tok? { defer { pos += 1 }; return peek }

        mutating func parseAll() throws -> Double {
            let v = try expr()
            if pos != tokens.count { throw Failure() }
            return v.v
        }

        mutating func expr() throws -> Val {
            var l = try term()
            while case .op(let o)? = peek, o == "+" || o == "-" {
                pos += 1; sawOperation = true
                let r = try term()
                let sign: Double = o == "+" ? 1 : -1
                l = Val(v: r.pct ? l.v * (1 + sign * r.v) : l.v + sign * r.v)
            }
            return l
        }

        mutating func term() throws -> Val {
            var l = try unary()
            while true {
                if case .op(let o)? = peek, o == "*" || o == "/" {
                    pos += 1; sawOperation = true
                    let r = try unary()
                    l = Val(v: o == "*" ? l.v * r.v : l.v / r.v)
                } else if case .id("of")? = peek {
                    pos += 1; sawOperation = true
                    let r = try unary()
                    l = Val(v: l.v * r.v)
                } else { return l }
            }
        }

        mutating func unary() throws -> Val {
            if case .op("-")? = peek { pos += 1; sawOperation = true; return Val(v: -(try unary()).v) }
            if case .op("+")? = peek { pos += 1; return try unary() }
            return try power()
        }

        mutating func power() throws -> Val {
            let b = try postfix()
            if case .op("^")? = peek {
                pos += 1; sawOperation = true
                return Val(v: pow(b.v, try unary().v))
            }
            return b
        }

        mutating func postfix() throws -> Val {
            var v = try primary()
            if case .op("%")? = peek { pos += 1; sawOperation = true; v = Val(v: v.v / 100, pct: true) }
            return v
        }

        mutating func primary() throws -> Val {
            guard let t = next() else { throw Failure() }
            switch t {
            case .num(let n): return Val(v: n)
            case .op("("):
                let v = try expr()
                guard case .op(")")? = next() else { throw Failure() }
                return v
            case .id(let name):
                switch name {
                case "pi": return Val(v: .pi)
                case "e": return Val(v: M_E)
                default:
                    sawOperation = true
                    guard case .op("(")? = peek else {
                        // allow `sqrt 16`
                        return Val(v: try apply(name, try unary().v))
                    }
                    pos += 1
                    let a = try expr().v
                    guard case .op(")")? = next() else { throw Failure() }
                    return Val(v: try apply(name, a))
                }
            default: throw Failure()
            }
        }

        func apply(_ f: String, _ x: Double) throws -> Double {
            switch f {
            case "sqrt": return sqrt(x)
            case "sin": return sin(x)
            case "cos": return cos(x)
            case "tan": return tan(x)
            case "asin": return asin(x)
            case "acos": return acos(x)
            case "atan": return atan(x)
            case "ln": return log(x)
            case "log": return log10(x)
            case "log2": return log2(x)
            case "abs": return abs(x)
            case "round": return x.rounded()
            case "floor": return floor(x)
            case "ceil": return ceil(x)
            case "exp": return exp(x)
            default: throw Failure()
            }
        }
    }
}
