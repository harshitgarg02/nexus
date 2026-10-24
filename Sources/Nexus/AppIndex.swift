import AppKit

struct AppEntry {
    let name: String
    let url: URL
}

/// Installed-app index plus launch-count frecency.
final class AppIndex {
    static let shared = AppIndex()
    private(set) var apps: [AppEntry] = []
    private let lock = NSLock()
    private let defaultsKey = "launchCounts"

    private var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                        "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            var found: [AppEntry] = []
            var seen = Set<String>()
            for d in dirs {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
                for i in items where i.hasSuffix(".app") {
                    let folder = String(i.dropLast(4))
                    if seen.insert(folder).inserted {
                        let url = URL(fileURLWithPath: d + "/" + i)
                        found.append(AppEntry(name: Self.displayName(url, fallback: folder), url: url))
                    }
                }
            }
            self.lock.lock(); self.apps = found; self.lock.unlock()
        }
    }

    /// Prefer the bundle's own display name ("Logi Options+") over the folder name ("logioptionsplus").
    private static func displayName(_ url: URL, fallback: String) -> String {
        guard let b = Bundle(url: url) else { return fallback }
        let local = b.localizedInfoDictionary
        let info = b.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let n = (local?[key] ?? info?[key]) as? String, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
        }
        return fallback
    }

    func recordLaunch(_ app: AppEntry) {
        var c = counts
        c[app.url.path, default: 0] += 1
        counts = c
    }

    func score(_ app: AppEntry, query q: String, counts: [String: Int]) -> Int? {
        let n = app.name.lowercased()
        let bonus = min(counts[app.url.path] ?? 0, 20)
        if q.isEmpty { return bonus > 0 ? bonus : nil }
        var base: Int
        if n == q { base = 120 }
        else if n.hasPrefix(q) { base = 100 }
        else if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { base = 80 }
        else if n.contains(q) { base = 60 }
        else if Self.isSubsequence(q, of: n) { base = 30 }
        else { return nil }
        base -= min(n.count / 4, 10) // prefer shorter names
        return base + bonus
    }

    func search(_ query: String, limit: Int) -> [AppEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        lock.lock(); let all = apps; lock.unlock()
        let counts = self.counts // one UserDefaults read per search, not one per app
        return all.compactMap { a in score(a, query: q, counts: counts).map { (a, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(limit).map(\.0)
    }

    private static func isSubsequence(_ q: String, of s: String) -> Bool {
        var qi = q.startIndex
        for c in s where qi < q.endIndex && c == q[qi] { qi = q.index(after: qi) }
        return qi == q.endIndex
    }
}
