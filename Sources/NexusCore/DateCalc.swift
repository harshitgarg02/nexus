import Foundation

/// Date/time expressions: `25 dec - today`, `today + 90 days`, `9:30 - 6:45`, `3pm ist to pst`, `now`.
enum DateCalc {
    struct Atom { var date: Date; var hasTime: Bool }

    static let months = ["january", "february", "march", "april", "may", "june", "july",
                         "august", "september", "october", "november", "december"]

    static let tzAbbrev: [String: String] = [
        "ist": "Asia/Kolkata", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver",
        "utc": "GMT", "gmt": "GMT", "cet": "Europe/Paris", "cest": "Europe/Paris", "bst": "Europe/London",
        "jst": "Asia/Tokyo", "sgt": "Asia/Singapore", "aest": "Australia/Sydney", "uae": "Asia/Dubai",
    ]

    static func rows(_ input: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        let s = input.lowercased().trimmingCharacters(in: .whitespaces)
        let hasLetter = s.contains(where: \.isLetter)
        guard hasLetter || s.contains(":") || s.range(of: #"\d{4}-\d"#, options: .regularExpression) != nil else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        // named dates: "days until christmas", "how many days to christmas", "days since 1 jan", "until easter"
        let phrase = s.replacingOccurrences(of: "how many ", with: "")
        if let m = match(#"^(?:(?:days?|weeks?|sleeps)\s+(until|till|to|since|from)|(until|till|since))\s+(.+)$"#, phrase) {
            let word = m[0].isEmpty ? m[1] : m[0]
            guard let target = parseAtom(m[2], now: now, cal: cal) else { return nil }
            let today = Atom(date: cal.startOfDay(for: now), hasTime: false)
            let past = word == "since" || word == "from"
            var out = diffRows(past ? today : target, past ? target : today, input: input, cal: cal)
            if let h = Holidays.resolve(m[2], now: now, calendar: cal) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "EEE d MMM yyyy"
                out.insert(CalcRow(title: f.string(from: h.date), subtitle: h.name + (h.approximate ? " (approx.)" : "")), at: 1)
            }
            return out
        }

        // timezone conversion: `<atom> to|in <tz>`
        if let m = match(#"^(.+?)\s+(?:to|in)\s+(.+)$"#, s), let target = resolveTZ(m[1]) {
            guard let atom = parseAtom(m[0], now: now, cal: cal) else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = target
            f.dateFormat = "EEE d MMM yyyy, h:mm:ss a zzz"
            return [CalcRow(title: f.string(from: atom.date), subtitle: "\(m[0]) → \(m[1])")]
        }

        // binary: `<atom> +/- <atom|quantity>`
        if let m = match(#"^(.+?)\s+([+-])\s+(.+)$"#, s) {
            guard let a = parseAtom(m[0], now: now, cal: cal) else { return nil }
            if let b = parseAtom(m[2], now: now, cal: cal) {
                guard m[1] == "-" else { return nil }
                return diffRows(a, b, input: input, cal: cal)
            }
            if let q = parseQuantity(m[2]) {
                let sign = m[1] == "-" ? -1 : 1
                guard let (date, timeUnit) = shift(a.date, q, sign: sign, cal: cal) else { return nil }
                return dateRows(Atom(date: date, hasTime: a.hasTime || timeUnit), subtitle: input, tz: timeZone, cal: cal)
            }
            return nil
        }

        // a bare holiday name: date, days away, epoch
        if let h = Holidays.resolve(s, now: now, calendar: cal) {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: h.date).day ?? 0
            var out = dateRows(Atom(date: h.date, hasTime: false), subtitle: h.name + (h.approximate ? " (approx.)" : ""), tz: timeZone, cal: cal)
            let away = days == 0 ? "today" : days > 0 ? "in \(days) day\(days == 1 ? "" : "s")" : "\(-days) day\(days == -1 ? "" : "s") ago"
            out.insert(CalcRow(title: away, subtitle: "Until \(h.name)"), at: 1)
            return out
        }
        guard let a = parseAtom(s, now: now, cal: cal) else { return nil }
        return dateRows(a, subtitle: input, tz: timeZone, cal: cal)
    }

    // MARK: atoms

    static func parseAtom(_ text: String, now: Date, cal: Calendar) -> Atom? {
        var tokens = text.split(separator: " ").map(String.init)
        var cal = cal
        if tokens.count > 1, let last = tokens.last, let tz = tzAbbrev[last].flatMap(TimeZone.init(identifier:)) {
            cal.timeZone = tz
            tokens.removeLast()
        }
        let t = tokens.joined(separator: " ")
        switch t {
        case "now", "time", "time now", "epoch": return Atom(date: now, hasTime: true)
        case "today": return Atom(date: cal.startOfDay(for: now), hasTime: false)
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)).map { Atom(date: $0, hasTime: false) }
        case "yesterday": return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)).map { Atom(date: $0, hasTime: false) }
        default: break
        }
        let year = cal.component(.year, from: now)

        if let m = match(#"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ t](\d{1,2}):(\d{2})(?::(\d{2}))?)?$"#, t) {
            let hasTime = !m[3].isEmpty
            return make(cal, Int(m[0])!, Int(m[1])!, Int(m[2])!, Int(m[3]) ?? 0, Int(m[4]) ?? 0, Int(m[5]) ?? 0, hasTime)
        }
        if let m = match(#"^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})(?:,?\s+(\d{4}))?$"#, t), let mo = month(m[1]) {
            return make(cal, Int(m[2]) ?? year, mo, Int(m[0])!, 0, 0, 0, false)
        }
        if let m = match(#"^([a-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?$"#, t), let mo = month(m[0]) {
            return make(cal, Int(m[2]) ?? year, mo, Int(m[1])!, 0, 0, 0, false)
        }
        if let m = match(#"^(\d{1,2})(?::(\d{2}))?(?::(\d{2}))?\s*(am|pm)?$"#, t), !m[1].isEmpty || !m[3].isEmpty {
            var h = Int(m[0])!
            let ap = m[3]
            if !ap.isEmpty {
                guard (1...12).contains(h) else { return nil }
                h = h % 12 + (ap == "pm" ? 12 : 0)
            }
            guard h < 24 else { return nil }
            let c = cal.dateComponents([.year, .month, .day], from: now)
            return make(cal, c.year!, c.month!, c.day!, h, Int(m[1]) ?? 0, Int(m[2]) ?? 0, true)
        }
        if let h = Holidays.resolve(text, now: now, calendar: cal) { return Atom(date: h.date, hasTime: false) }
        return nil
    }

    private static func make(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ hasTime: Bool) -> Atom? {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        guard let date = cal.date(from: c), cal.component(.day, from: date) == d else { return nil }
        return Atom(date: date, hasTime: hasTime)
    }

    private static func month(_ s: String) -> Int? {
        guard s.count >= 3 else { return nil }
        return months.firstIndex { $0.hasPrefix(s) }.map { $0 + 1 }
    }

    static func resolveTZ(_ s: String) -> TimeZone? {
        if let id = tzAbbrev[s] { return TimeZone(identifier: id) }
        let key = s.replacingOccurrences(of: " ", with: "_")
        guard key.count >= 3 else { return nil }
        let hit = TimeZone.knownTimeZoneIdentifiers.first { $0.split(separator: "/").last.map { $0.lowercased() == key } ?? false }
        return hit.flatMap(TimeZone.init(identifier:))
    }

    // MARK: quantity / shift

    enum QUnit { case day, week, month, year, hour, minute, second, businessDay }

    static func parseQuantity(_ s: String) -> (Double, QUnit)? {
        guard let m = match(#"^(\d+(?:\.\d+)?)\s*([a-z]+)$"#, s), let n = Double(m[0]) else { return nil }
        let u: QUnit
        switch m[1] {
        case "d", "day", "days": u = .day
        case "w", "wk", "week", "weeks": u = .week
        case "mo", "month", "months": u = .month
        case "y", "yr", "year", "years": u = .year
        case "h", "hr", "hrs", "hour", "hours": u = .hour
        case "min", "mins", "minute", "minutes": u = .minute
        case "s", "sec", "secs", "second", "seconds": u = .second
        case "bd": u = .businessDay
        default: return nil
        }
        return (n, u)
    }

    /// Returns new date and whether the unit was a time-of-day unit.
    static func shift(_ d: Date, _ q: (Double, QUnit), sign: Int, cal: Calendar) -> (Date, Bool)? {
        let (n, u) = q
        let whole = n == n.rounded()
        let k = Int(n) * sign
        switch u {
        case .hour: return (d.addingTimeInterval(Double(sign) * n * 3600), true)
        case .minute: return (d.addingTimeInterval(Double(sign) * n * 60), true)
        case .second: return (d.addingTimeInterval(Double(sign) * n), true)
        default: break
        }
        guard whole else { return nil }
        switch u {
        case .day: return cal.date(byAdding: .day, value: k, to: d).map { ($0, false) }
        case .week: return cal.date(byAdding: .day, value: 7 * k, to: d).map { ($0, false) }
        case .month: return cal.date(byAdding: .month, value: k, to: d).map { ($0, false) }
        case .year: return cal.date(byAdding: .year, value: k, to: d).map { ($0, false) }
        case .businessDay:
            var cur = d
            var left = abs(k)
            let step = k < 0 ? -1 : 1
            while left > 0 {
                cur = cal.date(byAdding: .day, value: step, to: cur)!
                if !cal.isDateInWeekend(cur) { left -= 1 }
            }
            return (cur, false)
        default: return nil
        }
    }

    // MARK: output

    static func dateRows(_ a: Atom, subtitle: String, tz: TimeZone, cal: Calendar) -> [CalcRow] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = a.hasTime ? "EEE d MMM yyyy, h:mm:ss a zzz" : "EEE d MMM yyyy"
        let micros = Int64((a.date.timeIntervalSince1970 * 1_000_000).rounded())
        let epoch = EpochCalc.rows(micros: micros, precise: false, timeZone: tz, now: a.date).suffix(2)
        return [CalcRow(title: f.string(from: a.date), subtitle: subtitle)] + epoch
    }

    static func diffRows(_ a: Atom, _ b: Atom, input: String, cal: Calendar) -> [CalcRow] {
        if !a.hasTime && !b.hasTime {
            let days = cal.dateComponents([.day], from: b.date, to: a.date).day ?? 0
            var rows = [CalcRow(title: "\(days) \(abs(days) == 1 ? "day" : "days")", subtitle: input, copy: "\(days)")]
            let (lo, hi) = days < 0 ? (a.date, b.date) : (b.date, a.date)
            let sign = days < 0 ? "-" : ""
            if abs(days) >= 7 {
                let w = abs(days) / 7, d = abs(days) % 7
                rows.append(CalcRow(title: sign + join([(w, "week"), (d, "day")]), subtitle: "Weeks"))
            }
            if abs(days) >= 28 {
                let c = cal.dateComponents([.year, .month, .day], from: lo, to: hi)
                rows.append(CalcRow(title: sign + join([(c.year ?? 0, "year"), (c.month ?? 0, "month"), (c.day ?? 0, "day")]), subtitle: "Calendar"))
            }
            return rows
        }
        let total = a.date.timeIntervalSince(b.date)
        let secs = Int64(total.rounded())
        let abs_ = abs(secs)
        let sign = secs < 0 ? "-" : ""
        let parts = join([(Int(abs_ / 86400), "d"), (Int(abs_ % 86400 / 3600), "h"), (Int(abs_ % 3600 / 60), "m"), (Int(abs_ % 60), "s")], short: true)
        return [
            CalcRow(title: sign + (parts.isEmpty ? "0s" : parts), subtitle: input),
            CalcRow(title: sign + String(format: "%lld:%02lld", abs_ / 3600, abs_ % 3600 / 60), subtitle: "H:MM"),
            CalcRow(title: sign + String(format: "%lld:%02lld:%02lld", abs_ / 3600, abs_ % 3600 / 60, abs_ % 60), subtitle: "H:MM:SS"),
            CalcRow(title: Calculator.format(Double(secs) / 3600, grouped: false) + " hours", subtitle: "Total hours"),
            CalcRow(title: "\(secs) seconds", subtitle: "Total seconds"),
        ]
    }

    private static func join(_ parts: [(Int, String)], short: Bool = false) -> String {
        parts.filter { $0.0 != 0 }.map { n, u in
            short ? "\(n)\(u)" : "\(n) \(u)\(n == 1 ? "" : "s")"
        }.joined(separator: short ? " " : " ")
    }

    // MARK: regex

    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : String(s[Range(r, in: s)!])
        }
    }
}
