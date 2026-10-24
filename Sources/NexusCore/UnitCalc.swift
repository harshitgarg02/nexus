import Foundation

enum UnitCalc {
    enum Category { case length, mass, volume, data, time, speed, temp }

    /// name -> (category, factor to the category's base unit)
    static let units: [String: (Category, Double)] = {
        var u: [String: (Category, Double)] = [:]
        func add(_ c: Category, _ f: Double, _ names: [String]) { for n in names { u[n] = (c, f) } }
        add(.length, 1, ["m", "meter", "meters", "metre", "metres"])
        add(.length, 1000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add(.length, 0.01, ["cm", "centimeter", "centimeters"])
        add(.length, 0.001, ["mm", "millimeter", "millimeters"])
        add(.length, 1609.344, ["mi", "mile", "miles"])
        add(.length, 0.9144, ["yd", "yard", "yards"])
        add(.length, 0.3048, ["ft", "foot", "feet"])
        add(.length, 0.0254, ["in", "inch", "inches"])
        add(.mass, 1, ["kg", "kilogram", "kilograms"])
        add(.mass, 0.001, ["g", "gram", "grams"])
        add(.mass, 0.000001, ["mg"])
        add(.mass, 0.45359237, ["lb", "lbs", "pound", "pounds"])
        add(.mass, 0.028349523125, ["oz", "ounce", "ounces"])
        add(.mass, 1000, ["t", "tonne", "tonnes"])
        add(.volume, 1, ["l", "liter", "liters", "litre", "litres"])
        add(.volume, 0.001, ["ml", "milliliter", "milliliters"])
        add(.volume, 3.785411784, ["gal", "gallon", "gallons"])
        add(.volume, 0.2365882365, ["cup", "cups"])
        add(.data, 1, ["b", "byte", "bytes"])
        add(.data, 1e3, ["kb"]); add(.data, 1e6, ["mb"]); add(.data, 1e9, ["gb"]); add(.data, 1e12, ["tb"])
        add(.data, 1024, ["kib"]); add(.data, 1_048_576, ["mib"])
        add(.data, 1_073_741_824, ["gib"]); add(.data, 1_099_511_627_776, ["tib"])
        add(.time, 1, ["s", "sec", "secs", "second", "seconds"])
        add(.time, 0.001, ["ms"])
        add(.time, 60, ["min", "mins", "minute", "minutes"])
        add(.time, 3600, ["h", "hr", "hrs", "hour", "hours"])
        add(.time, 86400, ["d", "day", "days"])
        add(.time, 604_800, ["w", "wk", "week", "weeks"])
        add(.speed, 1, ["m/s", "mps"])
        add(.speed, 1 / 3.6, ["kmh", "km/h", "kph"])
        add(.speed, 0.44704, ["mph"])
        add(.speed, 0.514444, ["kn", "knot", "knots"])
        add(.temp, 1, ["c", "f", "k", "celsius", "fahrenheit", "kelvin"])
        return u
    }()

    static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(-?[\d.,]+)\s*([a-zA-Z/°]+)\s+(?:to|in|as|->)\s+([a-zA-Z/°]+)\s*$"#)

    static func rows(_ input: String) -> [CalcRow]? {
        let ns = input as NSString
        guard let m = pattern.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
        let from = ns.substring(with: m.range(at: 2)).lowercased().replacingOccurrences(of: "°", with: "")
        let to = ns.substring(with: m.range(at: 3)).lowercased().replacingOccurrences(of: "°", with: "")
        guard let value = Double(numStr), let a = units[from], let b = units[to], a.0 == b.0 else { return nil }
        let out: Double
        if a.0 == .temp {
            out = fromKelvin(toKelvin(value, from), to)
        } else {
            out = value * a.1 / b.1
        }
        let t = Calculator.format(out)
        return [CalcRow(title: "\(t) \(to)", subtitle: "\(Calculator.format(value)) \(from)", copy: Calculator.format(out, grouped: false))]
    }

    private static func toKelvin(_ v: Double, _ u: String) -> Double {
        switch u {
        case "c", "celsius": return v + 273.15
        case "f", "fahrenheit": return (v - 32) * 5 / 9 + 273.15
        default: return v
        }
    }

    private static func fromKelvin(_ k: Double, _ u: String) -> Double {
        switch u {
        case "c", "celsius": return k - 273.15
        case "f", "fahrenheit": return (k - 273.15) * 9 / 5 + 32
        default: return k
        }
    }
}
