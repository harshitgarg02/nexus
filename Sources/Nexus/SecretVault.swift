import Foundation
import Security
import LocalAuthentication

/// Secret snippet values live in the Keychain (not the snippet database).
enum SecretVault {
    static let snippets = AppIdentity.bundleID + ".snippets"
    static let totp = AppIdentity.bundleID + ".totp"

    private static func query(_ id: Int64, _ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: String(id)]
    }

    @discardableResult
    static func set(_ value: String, for id: Int64, service: String = snippets) -> Bool {
        SecItemDelete(query(id, service) as CFDictionary)
        var q = query(id, service)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { NSLog("Nexus: keychain add failed (\(status))") }
        return status == errSecSuccess
    }

    static func get(_ id: Int64, service: String = snippets) -> String? {
        var q = query(id, service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ id: Int64, service: String = snippets) { SecItemDelete(query(id, service) as CFDictionary) }
}

enum Auth {
    /// Touch ID, falling back to the Mac account password. The overlay must not auto-hide while the system
    /// password sheet takes key focus, so we flag it.
    static func verify(reason: String) async -> Bool {
        OverlayController.suppressAutoHide = true
        defer { OverlayController.suppressAutoHide = false }
        let ctx = LAContext()
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}
