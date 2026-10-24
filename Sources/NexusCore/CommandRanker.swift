import Foundation

/// Orders launcher commands. With a query, better matches come first (title prefix, then a title word, then a
/// keyword, then anywhere in the title). Ties go to the commands you use most, then to a fixed group order
/// (your modules, scripts, system, generators, dev tools, text transforms), then alphabetical.
/// With no query it's usage, then group, then alphabetical.
public enum CommandRanker {
    public struct Entry: Equatable {
        public let id: String
        public let title: String
        public let keywords: [String]
        public let group: Int

        public init(id: String, title: String, keywords: [String], group: Int) {
            self.id = id; self.title = title; self.keywords = keywords; self.group = group
        }
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// 0 = title starts with the query … 3 = it appears inside the title. Nil = no match.
    public static func tier(query: String, title: String, keywords: [String]) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return 0 }
        let t = title.lowercased()
        let tw = words(title), kw = keywords.map { $0.lowercased() }
        let qw = words(q)
        if t.hasPrefix(q) { return 0 }
        if !qw.isEmpty, qw.allSatisfy({ w in tw.contains { $0.hasPrefix(w) } }) { return 1 }
        if !qw.isEmpty, qw.allSatisfy({ w in tw.contains { $0.hasPrefix(w) } || kw.contains { $0.hasPrefix(w) } }) { return 2 }
        if t.contains(q) { return 3 }
        return nil
    }

    /// Ids of the matching entries, best first.
    public static func order(_ entries: [Entry], query: String, usage: [String: Int] = [:]) -> [String] {
        entries.compactMap { e in tier(query: query, title: e.title, keywords: e.keywords).map { (e, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                let (ua, ub) = (usage[a.0.id] ?? 0, usage[b.0.id] ?? 0)
                if ua != ub { return ua > ub }
                if a.0.group != b.0.group { return a.0.group < b.0.group }
                return a.0.title.localizedCaseInsensitiveCompare(b.0.title) == .orderedAscending
            }
            .map(\.0.id)
    }
}
