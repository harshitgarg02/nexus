import Foundation
import NexusCore

/// Downloads daily exchange rates, only while "Currency conversion" is on in Settings → Calculator.
/// Plain GET to open.er-api.com (ExchangeRate-API's open endpoint); nothing about you is sent.
final class CurrencyService {
    static let shared = CurrencyService()
    static let updatedNotification = Notification.Name("NexusCurrencyRatesUpdated")
    private static let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
    private static let refreshInterval: TimeInterval = 24 * 3600

    private(set) var rates: CurrencyRates?
    private(set) var lastError: String?
    private var fetching = false
    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rates.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: cacheURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .secondsSince1970
            rates = try? dec.decode(CurrencyRates.self, from: d)
        }
    }

    var isEnabled: Bool { Settings.shared.data.currencyEnabled }

    var state: CurrencyState {
        guard isEnabled else { return .disabled }
        return rates.map(CurrencyState.ready) ?? .loading
    }

    func start() {
        refreshIfNeeded()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.refreshIfNeeded() }
        RunLoop.main.add(t, forMode: .common)
    }

    func refreshIfNeeded(force: Bool = false) {
        guard isEnabled, !fetching else { return }
        if !force, let r = rates, Date().timeIntervalSince(r.fetched) < Self.refreshInterval { return }
        fetching = true
        var req = URLRequest(url: Self.url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                if let data, let parsed = CurrencyRates.parse(data) {
                    self.rates = parsed
                    self.lastError = nil
                    let enc = JSONEncoder()
                    enc.dateEncodingStrategy = .secondsSince1970
                    try? enc.encode(parsed).write(to: self.cacheURL, options: .atomic)
                } else {
                    // keep serving the cached rates (their age is shown in the result)
                    self.lastError = error?.localizedDescription ?? "Unexpected response from the rates provider."
                }
                NotificationCenter.default.post(name: Self.updatedNotification, object: nil)
            }
        }.resume()
    }
}
