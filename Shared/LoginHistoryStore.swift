import Foundation
import Security

/// Opt-in memory of the domains where the user has entered credentials
/// (PLAN.md §7). Off by default. Stored in the Keychain — encrypted at rest,
/// `ThisDeviceOnly` so it never syncs to iCloud, and purgeable in one call.
///
/// Shared by the app (settings + purge) and the extension (record + lookup)
/// through the app group's shared Keychain access group. Only host strings are
/// stored — never URLs, never page content.
struct LoginHistoryStore {
    static let shared = LoginHistoryStore()

    private let service = "com.ouweis.impostor.login-history"
    // One entry per registrable domain; the account is the domain itself.

    /// Whether the feature is enabled lives in the shared app-group defaults so
    /// both processes agree.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.ouweis.impostor") ?? .standard
    }

    var isEnabled: Bool {
        defaults.bool(forKey: "rememberLoginDomains")
    }

    /// Has this login domain been seen before? Returns nil when the feature is
    /// off (the signal must not fire at all in that case).
    func hasSeen(domain: String) -> Bool? {
        guard isEnabled else { return nil }
        var query: [String: Any] = baseQuery(domain: domain)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Record that the user reached a credential form on this domain. No-op when
    /// the feature is off.
    func record(domain: String) {
        guard isEnabled, !domain.isEmpty else { return }
        var query = baseQuery(domain: domain)
        query[kSecValueData as String] = Data("1".utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil) // errSecDuplicateItem is fine.
    }

    /// Purge everything — the one-gesture erase from Settings.
    func purge() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
    }

    private func baseQuery(domain: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: domain,
        ]
    }
}
