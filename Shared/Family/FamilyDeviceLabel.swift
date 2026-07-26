import Foundation

/// How this device identifies itself to relatives — and the switch that turns
/// family mode on at all.
///
/// An empty label means off. That is not a shortcut: it makes "we have nothing
/// to call this device" and "do not publish anything" the same state, so there
/// is no way to end up publishing with a placeholder name, and no separate
/// boolean that could drift out of step with it.
///
/// Read from the Safari extension as well as the app, hence the shared keychain
/// access group. Keychain rather than an App Group because access groups are
/// derived from the team prefix and need no identifier registered anywhere —
/// one less thing to provision, and it is already how `LoginHistoryStore` works.
///
/// Never derived from `UIDevice.name`: that is very often a full legal name the
/// user never chose to publish to anyone.
enum FamilyDeviceLabel {
    private static let service = "com.ouweis.avert.family-label"
    private static let account = "device-label"

    static var current: String {
        get { read() ?? "" }
    }

    static func set(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(trimmed.prefix(FamilyAlert.maxLabelLength))
        clipped.isEmpty ? delete() : write(clipped)
    }

    static var isEnabled: Bool { !current.isEmpty }

    // MARK: - Keychain

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Available to the extension while the device is locked: a warning
            // can be ignored without the phone being unlocked afterwards.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }

    private static func read() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        SecItemDelete(query() as CFDictionary)
        var q = query()
        q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func delete() {
        SecItemDelete(query() as CFDictionary)
    }
}
