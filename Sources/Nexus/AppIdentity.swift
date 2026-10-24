import Foundation

enum AppIdentity {
    /// The bundle identifier. It also namespaces Keychain items and log subsystems, so a fork that builds under its
    /// own `BUNDLE_ID` never reads or overwrites another build's secrets.
    static let bundleID = Bundle.main.bundleIdentifier ?? "app.nexus.launcher"
}
