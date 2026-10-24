import AppKit
import NexusCore

/// One-time move of Keychain secrets and usage counts from a previous bundle identifier to the current one
/// (Keychain access is tied to the app's identity, so renaming the app hides the old items).
/// It only runs when `migrate-from-bundle-id.txt` exists in the data folder; that file names the old identifier,
/// so nothing about a previous identity is hard-coded in the source.
enum LegacyMigration {
    private static var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
    }
    private static var marker: URL { dataDir.appendingPathComponent("migrate-from-bundle-id.txt") }

    struct Outcome { var moved = 0, alreadyThere = 0, missing = 0 }

    static func runIfNeeded() {
        guard let old = (try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
              !old.isEmpty, old != AppIdentity.bundleID else { return }
        // Off the main thread: reading items made by the old identity can raise a Keychain prompt.
        DispatchQueue.global(qos: .utility).async {
            let outcome = migrate(from: old)
            try? FileManager.default.removeItem(at: marker) // runs once; re-create the file to try again
            DispatchQueue.main.async { report(outcome) }
        }
    }

    private static func migrate(from old: String) -> Outcome {
        var o = Outcome()
        let snippetIDs = SnippetStore(path: dataDir.appendingPathComponent("snippets.db").path).all().filter(\.isSecret).map(\.id)
        let totpIDs = TOTPStore(path: dataDir.appendingPathComponent("totp.db").path).all().map(\.id)
        for (ids, suffix, newService) in [(snippetIDs, ".snippets", SecretVault.snippets), (totpIDs, ".totp", SecretVault.totp)] {
            for id in ids {
                if SecretVault.get(id, service: newService) != nil { o.alreadyThere += 1; continue }
                guard let value = SecretVault.get(id, service: old + suffix) else { o.missing += 1; continue }
                // Only delete the old item once the new one reads back identical.
                guard SecretVault.set(value, for: id, service: newService), SecretVault.get(id, service: newService) == value else { o.missing += 1; continue }
                SecretVault.delete(id, service: old + suffix)
                o.moved += 1
            }
        }
        if let prev = UserDefaults(suiteName: old) {
            for key in ["launchCounts", "commandUsage"] where UserDefaults.standard.object(forKey: key) == nil {
                if let v = prev.object(forKey: key) { UserDefaults.standard.set(v, forKey: key) }
            }
        }
        return o
    }

    private static func report(_ o: Outcome) {
        guard o.moved > 0 || o.missing > 0 else { return }
        let a = NSAlert()
        a.messageText = "Moved \(o.moved) secret\(o.moved == 1 ? "" : "s") to this app's identity"
        var text = "Snippet secrets and 2FA keys were copied to the Keychain under the new identifier, and your usage history was kept."
        if o.missing > 0 { text += "\n\n\(o.missing) item\(o.missing == 1 ? "" : "s") couldn't be read (denied or not found). To try again, put the old bundle identifier in migrate-from-bundle-id.txt in ~/Library/Application Support/Nexus and relaunch." }
        text += "\n\nmacOS may ask for Accessibility again: the renamed app is a new app to it."
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
