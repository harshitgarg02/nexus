import Foundation

/// Exchange rates relative to `base` (units of each currency per 1 base). Cached on disk by the app.
public struct CurrencyRates: Codable, Equatable {
    public var base: String
    public var rates: [String: Double]
    /// When the provider says the rates were computed.
    public var updated: Date
    /// When we downloaded them (drives the refresh schedule).
    public var fetched: Date

    public init(base: String, rates: [String: Double], updated: Date, fetched: Date) {
        self.base = base; self.rates = rates; self.updated = updated; self.fetched = fetched
    }

    func rate(_ code: String) -> Double? { code == base ? 1 : rates[code] }

    /// open.er-api.com `v6/latest/USD` response.
    public static func parse(_ data: Data, fetched: Date = Date()) -> CurrencyRates? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["result"] as? String == "success",
              let base = obj["base_code"] as? String,
              let raw = obj["rates"] as? [String: Any] else { return nil }
        var rates: [String: Double] = [:]
        for (k, v) in raw { if let d = (v as? NSNumber)?.doubleValue, d > 0 { rates[k] = d } }
        guard rates.count > 10 else { return nil }
        let updated = (obj["time_last_update_unix"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? fetched
        return CurrencyRates(base: base, rates: rates, updated: updated, fetched: fetched)
    }
}

public enum CurrencyState {
    case disabled              // setting off: never touches the network
    case loading               // enabled, no rates yet
    case ready(CurrencyRates)
}

enum CurrencyCalc {
    static let symbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR"]
    /// Used to recognise "100 usd to inr" even when conversion is off/loading, so we can show a hint.
    static let common: Set<String> = ["USD", "EUR", "GBP", "INR", "JPY", "AUD", "CAD", "CHF", "CNY", "SGD", "AED", "HKD", "NZD",
                                      "SEK", "NOK", "DKK", "KRW", "MXN", "BRL", "ZAR", "THB", "IDR", "MYR", "PHP", "SAR", "TRY"]

    // case-insensitive: "100 USD TO inr" must work
    private static let codeForm = try! NSRegularExpression(
        pattern: #"^\s*([\d.,]+)\s*([A-Za-z]{3})\s+(?:to|in|->|as)\s+([A-Za-z]{3})\s*$"#, options: [.caseInsensitive])
    private static let symbolForm = try! NSRegularExpression(
        pattern: #"^\s*([$€£¥₹])\s*([\d.,]+)\s*(?:to|in|->|as)\s+([A-Za-z]{3})\s*$"#, options: [.caseInsensitive])

    static func rows(_ input: String, state: CurrencyState, now: Date) -> [CalcRow]? {
        guard let (amountText, from, to) = parse(input), let amount = Double(amountText.replacingOccurrences(of: ",", with: "")) else { return nil }
        switch state {
        case .disabled:
            guard common.contains(from), common.contains(to) else { return nil }
            return [CalcRow(title: "Currency conversion is off", subtitle: "Turn it on in Settings → Calculator")]
        case .loading:
            guard common.contains(from), common.contains(to) else { return nil }
            return [CalcRow(title: "Fetching exchange rates…", subtitle: "Try again in a moment")]
        case .ready(let r):
            guard let rf = r.rate(from), let rt = r.rate(to) else { return nil }
            let out = amount / rf * rt
            let unit = rt / rf
            return [
                CalcRow(title: "\(Calculator.format(round2(out))) \(to)", subtitle: "\(Calculator.format(amount)) \(from)",
                        copy: Calculator.format(round2(out), grouped: false)),
                CalcRow(title: "1 \(from) = \(sig(unit)) \(to)", subtitle: "Rate · \(age(r.updated, now: now))", copy: sig(unit)),
                CalcRow(title: "1 \(to) = \(sig(1 / unit)) \(from)", subtitle: "Inverse rate", copy: sig(1 / unit)),
            ]
        }
    }

    private static func parse(_ input: String) -> (String, String, String)? {
        let ns = input as NSString
        let all = NSRange(location: 0, length: ns.length)
        if let m = codeForm.firstMatch(in: input, range: all) {
            return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)).uppercased(), ns.substring(with: m.range(at: 3)).uppercased())
        }
        if let m = symbolForm.firstMatch(in: input, range: all), let ch = ns.substring(with: m.range(at: 1)).first, let code = symbols[ch] {
            return (ns.substring(with: m.range(at: 2)), code, ns.substring(with: m.range(at: 3)).uppercased())
        }
        return nil
    }

    /// Money to 2 decimals, but keep precision for tiny amounts (e.g. JPY→BTC-sized fractions).
    private static func round2(_ v: Double) -> Double { abs(v) >= 0.01 ? (v * 100).rounded() / 100 : v }
    private static func sig(_ v: Double) -> String { String(format: "%.6g", v) }

    static func age(_ d: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 3600 { return "updated \(max(1, s / 60)) min ago" }
        if s < 86_400 { return "updated \(s / 3600) h ago" }
        return "updated \(s / 86_400) d ago"
    }
}
