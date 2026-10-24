import Foundation

/// Bare epoch timestamps (s / ms / µs / ns) -> human date-time rows.
/// All math is integer microseconds; Double can't hold epoch µs exactly.
enum EpochCalc {
    static let maxSeconds: Int64 = 4_102_444_800 // 2100-01-01

    static func rows(_ input: String, timeZone: TimeZone, now: Date) -> [CalcRow]? {
        let parts = input.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, let intPart = parts.first, !intPart.isEmpty,
              intPart.allSatisfy(\.isASCII), intPart.allSatisfy(\.isNumber) else { return nil }
        let fracPart = parts.count == 2 ? parts[1] : nil
        if let f = fracPart, f.isEmpty || !f.allSatisfy(\.isNumber) { return nil }

        let micros: Int64
        var precise = false
        if let f = fracPart {
            // decimal => seconds
            guard intPart.count == 10, let s = Int64(intPart) else { return nil }
            let digits = String(f.prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)
            micros = s * 1_000_000 + Int64(digits)!
            precise = true
        } else {
            guard let n = Int64(intPart) else { return nil }
            switch intPart.count {
            case 10: micros = n * 1_000_000
            case 13: micros = n * 1_000; precise = n % 1000 != 0
            case 16: micros = n; precise = n % 1_000_000 != 0
            case 19: micros = n / 1000; precise = (n / 1000) % 1_000_000 != 0
            default: return nil
            }
        }
        guard micros >= 0, micros / 1_000_000 <= maxSeconds else { return nil }
        return rows(micros: micros, precise: precise, timeZone: timeZone, now: now)
    }

    static func rows(micros: Int64, precise: Bool, timeZone: TimeZone, now: Date) -> [CalcRow] {
        let secs = micros / 1_000_000
        let frac = String(format: "%06lld", micros % 1_000_000)
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let dot = precise ? ".\(frac)" : ""

        func fmt(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = tz
            f.dateFormat = pattern
            return f
        }
        let local = fmt("EEE d MMM yyyy, h:mm:ss", timeZone).string(from: date) + dot + fmt(" a zzz", timeZone).string(from: date)
        let utc = fmt("EEE d MMM yyyy, h:mm:ss", .gmt).string(from: date) + dot + " UTC"
        let iso = fmt("yyyy-MM-dd'T'HH:mm:ss", timeZone).string(from: date) + dot + fmt("XXX", timeZone).string(from: date)
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        let relative = rel.localizedString(for: date, relativeTo: now)

        return [
            CalcRow(title: local, subtitle: "Local"),
            CalcRow(title: utc, subtitle: "UTC"),
            CalcRow(title: iso, subtitle: "ISO 8601"),
            CalcRow(title: relative, subtitle: "Relative"),
            CalcRow(title: "\(secs).\(frac)", subtitle: "Epoch seconds (µs precision)"),
            CalcRow(title: "\(micros / 1000)", subtitle: "Epoch milliseconds"),
        ]
    }
}
