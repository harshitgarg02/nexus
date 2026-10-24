import Foundation

public struct Holiday: Equatable {
    public let name: String
    public let date: Date
    /// Depends on moon sighting / a lunar-calendar table: may be off by a day or more. Shown as "(approx.)".
    public let approximate: Bool
}

/// Named dates for the calculator ("days until christmas"). Everything is computed for any year: fixed dates,
/// nth-weekday rules, Easter, the Chinese calendar, and Eid/Ramadan from the Umm al-Qura calendar (approximate:
/// the real date follows moon sighting). Hindu lunisolar festivals (Diwali, Holi…) are intentionally absent:
/// they can't be derived from the system calendars and a hand-kept table would rot.
public enum Holidays {

    private enum Rule {
        case fixed(Int, Int)                 // month, day
        case nthWeekday(Int, Int, Int)       // month, weekday (1=Sun), nth
        case easter(Int)                     // days after Easter Sunday
        case chineseNewYear
        case islamic(month: Int, day: Int)
    }

    private static let rules: [(names: [String], title: String, rule: Rule, approx: Bool)] = [
        (["new year", "new years", "new years day", "newyear"], "New Year's Day", .fixed(1, 1), false),
        (["new years eve", "new year eve"], "New Year's Eve", .fixed(12, 31), false),
        (["republic day"], "Republic Day", .fixed(1, 26), false),
        (["valentines day", "valentines", "valentine day"], "Valentine's Day", .fixed(2, 14), false),
        (["independence day"], "Independence Day (India)", .fixed(8, 15), false),
        (["gandhi jayanti"], "Gandhi Jayanti", .fixed(10, 2), false),
        (["teachers day"], "Teachers' Day (India)", .fixed(9, 5), false),
        (["childrens day"], "Children's Day (India)", .fixed(11, 14), false),
        (["labour day", "may day"], "Labour Day", .fixed(5, 1), false),
        (["halloween"], "Halloween", .fixed(10, 31), false),
        (["christmas eve"], "Christmas Eve", .fixed(12, 24), false),
        (["christmas", "xmas", "christmas day"], "Christmas", .fixed(12, 25), false),
        (["easter", "easter sunday"], "Easter", .easter(0), false),
        (["good friday"], "Good Friday", .easter(-2), false),
        (["thanksgiving"], "Thanksgiving (US)", .nthWeekday(11, 5, 4), false),
        (["mothers day"], "Mother's Day (US)", .nthWeekday(5, 1, 2), false),
        (["fathers day"], "Father's Day (US)", .nthWeekday(6, 1, 3), false),
        (["labor day"], "Labor Day (US)", .nthWeekday(9, 2, 1), false),
        (["chinese new year", "lunar new year"], "Chinese New Year", .chineseNewYear, false),
        (["eid", "eid al fitr", "eid ul fitr"], "Eid al-Fitr", .islamic(month: 10, day: 1), true),
        (["eid al adha", "eid ul adha", "bakrid", "bakri eid"], "Eid al-Adha", .islamic(month: 12, day: 10), true),
        (["ramadan"], "Ramadan (first day)", .islamic(month: 9, day: 1), true),
    ]

    /// `text` is a holiday name with an optional 4-digit year ("christmas", "easter 2027").
    /// Without a year, the next occurrence on or after today.
    public static func resolve(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Holiday? {
        var t = text.lowercased().replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("the ") { t.removeFirst(4) }
        var year: Int?
        if let r = t.range(of: #"\s+\d{4}$"#, options: .regularExpression) {
            year = Int(t[r].trimmingCharacters(in: .whitespaces))
            t = String(t[..<r.lowerBound])
        }
        guard let entry = rules.first(where: { $0.names.contains(t) }) else { return nil }
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let today = cal.startOfDay(for: now)
        let thisYear = cal.component(.year, from: now)

        func date(_ y: Int) -> Date? { compute(entry.rule, year: y, calendar: cal) }
        if let y = year {
            return date(y).map { Holiday(name: entry.title, date: $0, approximate: entry.approx) }
        }
        for y in [thisYear, thisYear + 1] {
            if let d = date(y), d >= today { return Holiday(name: entry.title, date: d, approximate: entry.approx) }
        }
        return nil
    }

    private static func compute(_ rule: Rule, year: Int, calendar cal: Calendar) -> Date? {
        func make(_ m: Int, _ d: Int) -> Date? { cal.date(from: DateComponents(year: year, month: m, day: d)) }
        switch rule {
        case .fixed(let m, let d): return make(m, d)
        case .easter(let offset):
            guard let e = easter(year: year, calendar: cal) else { return nil }
            return cal.date(byAdding: .day, value: offset, to: e)
        case .nthWeekday(let m, let wd, let n):
            guard let first = make(m, 1) else { return nil }
            let firstWd = cal.component(.weekday, from: first)
            let delta = (wd - firstWd + 7) % 7 + (n - 1) * 7
            return cal.date(byAdding: .day, value: delta, to: first)
        case .chineseNewYear:
            var chinese = Calendar(identifier: .chinese)
            chinese.timeZone = cal.timeZone
            return scan(year: year, calendar: cal, from: (1, 15), days: 50) { d in
                let c = chinese.dateComponents([.month, .day, .isLeapMonth], from: d)
                return c.month == 1 && c.day == 1 && c.isLeapMonth != true
            }
        case .islamic(let month, let day):
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = cal.timeZone
            return scan(year: year, calendar: cal, from: (1, 1), days: 366) { d in
                let c = islamic.dateComponents([.month, .day], from: d)
                return c.month == month && c.day == day
            }
        }
    }

    private static func scan(year: Int, calendar cal: Calendar, from: (Int, Int), days: Int, _ match: (Date) -> Bool) -> Date? {
        guard var d = cal.date(from: DateComponents(year: year, month: from.0, day: from.1)) else { return nil }
        for _ in 0..<days {
            if match(d), cal.component(.year, from: d) == year { return d }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return nil
    }

    /// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    static func easter(year y: Int, calendar cal: Calendar) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return cal.date(from: DateComponents(year: y, month: month, day: day))
    }
}
