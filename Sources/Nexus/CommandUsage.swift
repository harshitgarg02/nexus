import Foundation

/// How often each command has been run, so the ones you use float to the top of the list.
enum CommandUsage {
    private static let key = "commandUsage"

    static var counts: [String: Int] { UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }

    static func record(_ id: String) {
        var c = counts
        c[id, default: 0] += 1
        UserDefaults.standard.set(c, forKey: key)
    }
}
