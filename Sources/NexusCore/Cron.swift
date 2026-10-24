import Foundation

public enum CronError: Error, LocalizedError, Equatable {
    case wrongFieldCount(Int)
    case badField(name: String, value: String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .wrongFieldCount(let n): return "A cron expression has 5 fields (minute hour day-of-month month day-of-week), found \(n)."
        case .badField(let name, let v): return "Invalid \(name): “\(v)”."
        case .unsupported(let m): return m
        }
    }
}

/// Standard 5-field cron (Vixie semantics: when both day-of-month and day-of-week are restricted, either may match).
public struct CronSchedule: Equatable {
    let fields: [String]
    let minutes: [Int], hours: [Int], daysOfMonth: [Int], months: [Int], daysOfWeek: [Int] // sorted; Sunday = 0
    let domRestricted: Bool, dowRestricted: Bool

    private static let macros = ["@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
                                 "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    public static func parse(_ expression: String) -> Result<CronSchedule, CronError> {
        var text = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "@reboot" { return .failure(.unsupported("@reboot runs once when the system starts, so it has no schedule.")) }
        if let m = macros[text] { text = m }
        let f = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard f.count == 5 else { return .failure(.wrongFieldCount(f.count)) }
        let specs: [(String, ClosedRange<Int>, [String])] = [
            ("minute", 0...59, []), ("hour", 0...23, []), ("day of month", 1...31, []),
            ("month", 1...12, monthNames), ("day of week", 0...7, dayNames),
        ]
        var sets: [[Int]] = []
        for (i, spec) in specs.enumerated() {
            guard var values = field(f[i], range: spec.1, names: spec.2, firstName: i == 3 ? 1 : 0) else {
                return .failure(.badField(name: spec.0, value: f[i]))
            }
            if i == 4 { values = Array(Set(values.map { $0 % 7 })) } // 7 is also Sunday
            sets.append(values.sorted())
        }
        return .success(CronSchedule(fields: f, minutes: sets[0], hours: sets[1], daysOfMonth: sets[2], months: sets[3], daysOfWeek: sets[4],
                                     domRestricted: !f[2].hasPrefix("*"), dowRestricted: !f[4].hasPrefix("*")))
    }

    /// `*`, `*/n`, `a`, `a-b`, `a-b/n`, `a/n`, and comma lists, with month/day names.
    private static func field(_ s: String, range: ClosedRange<Int>, names: [String], firstName: Int) -> [Int]? {
        var out = Set<Int>()
        for part in s.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard !part.isEmpty else { return nil }
            let stepSplit = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard stepSplit.count <= 2 else { return nil }
            var step = 1
            if stepSplit.count == 2 { guard let n = Int(stepSplit[1]), n >= 1 else { return nil }; step = n }
            func value(_ t: String) -> Int? {
                if let n = Int(t) { return range.contains(n) ? n : nil }
                return names.firstIndex(of: t).map { $0 + firstName }
            }
            let lo: Int, hi: Int
            if stepSplit[0] == "*" { (lo, hi) = (range.lowerBound, names.isEmpty && range.upperBound == 7 ? 6 : range.upperBound) }
            else if stepSplit[0].contains("-") {
                let r = stepSplit[0].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard r.count == 2, let a = value(r[0]), let b = value(r[1]), a <= b else { return nil }
                (lo, hi) = (a, b)
            } else {
                guard let a = value(stepSplit[0]) else { return nil }
                (lo, hi) = (a, stepSplit.count == 2 ? range.upperBound : a)
            }
            for v in stride(from: lo, through: hi, by: step) { out.insert(v) }
        }
        return out.isEmpty ? nil : Array(out)
    }

    // MARK: next runs

    /// The next `count` run times strictly after `date`, searching up to 8 years ahead (covers Feb 29).
    public func nextRuns(after date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let start = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)
        var day = cal.startOfDay(for: start)
        var out: [Date] = []
        for _ in 0..<(366 * 8) {
            let c = cal.dateComponents([.month, .day, .weekday], from: day)
            if matches(month: c.month!, day: c.day!, weekday: c.weekday! - 1) {
                for h in hours {
                    for m in minutes {
                        guard let t = cal.date(bySettingHour: h, minute: m, second: 0, of: day), t >= start,
                              cal.component(.hour, from: t) == h else { continue } // skip times that don't exist (DST gap)
                        out.append(t)
                        if out.count == count { return out }
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    private func matches(month: Int, day: Int, weekday: Int) -> Bool {
        guard months.contains(month) else { return false }
        let dom = daysOfMonth.contains(day), dow = daysOfWeek.contains(weekday)
        if domRestricted && dowRestricted { return dom || dow }
        if domRestricted { return dom }
        if dowRestricted { return dow }
        return true
    }

    // MARK: English

    public func describe() -> String {
        let (m, h) = (fields[0], fields[1])
        let time: String
        if m == "*" && h == "*" { time = "Every minute" }
        else if m.hasPrefix("*/"), h == "*" { time = "Every \(m.dropFirst(2)) minutes" }
        else if let mm = single(minutes, m), h == "*" { time = mm == 0 ? "At the start of every hour" : "At minute \(mm) of every hour" }
        else if let mm = single(minutes, m), let hh = single(hours, h) { time = String(format: "At %02d:%02d", hh, mm) }
        else if let mm = single(minutes, m), h.hasPrefix("*/") { time = "At minute \(mm) of every \(h.dropFirst(2)) hours" }
        else if m == "*" { time = "Every minute during \(hours.count == 1 ? "hour" : "hours") \(Self.list(hours))" }
        else { time = "At \(minutes.count == 1 ? "minute" : "minutes") \(Self.list(minutes)), past \(hours.count == 1 ? "hour" : "hour") \(h == "*" ? "every hour" : Self.list(hours))" }

        var parts: [String] = []
        var day: [String] = []
        if domRestricted { day.append("day \(Self.list(daysOfMonth)) of the month") }
        if dowRestricted { day.append(Self.weekdays(daysOfWeek)) }
        if !day.isEmpty { parts.append("on " + day.joined(separator: " or on ")) }
        if months.count != 12 { parts.append("in " + Self.monthList(months)) }
        if parts.isEmpty { parts.append("every day") }
        return time + " " + parts.joined(separator: " ")
    }

    private func single(_ values: [Int], _ raw: String) -> Int? {
        values.count == 1 && !raw.contains("/") && !raw.contains("-") && !raw.contains(",") && raw != "*" ? values[0] : nil
    }

    private static func list(_ v: [Int]) -> String {
        // collapse runs: 9,10,11,12 → 9–12
        var runs: [String] = [], i = 0
        while i < v.count {
            var j = i
            while j + 1 < v.count, v[j + 1] == v[j] + 1 { j += 1 }
            runs.append(j - i >= 2 ? "\(v[i])–\(v[j])" : v[i...j].map(String.init).joined(separator: ", "))
            i = j + 1
        }
        return runs.joined(separator: ", ")
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthFull = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    private static func weekdays(_ v: [Int]) -> String {
        if v == [1, 2, 3, 4, 5] { return "Monday through Friday" }
        if v == [0, 6] { return "weekends" }
        return named(v.map { weekdayNames[$0] })
    }

    private static func monthList(_ v: [Int]) -> String { named(v.map { monthFull[$0 - 1] }) }

    private static func named(_ n: [String]) -> String {
        n.count <= 2 ? n.joined(separator: " and ") : n.dropLast().joined(separator: ", ") + " and " + n.last!
    }
}
