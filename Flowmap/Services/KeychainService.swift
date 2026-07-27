import Foundation
import Security

/// Keychain storage for API keys.
///
/// Key *values* live here and nowhere else: never in SwiftData, never in
/// CloudKit, never in `UserDefaults`, never in logs. `AppSettings` stores only
/// the provider and model identifiers.
public enum KeychainService {
    /// Namespaced so a key cannot collide with another app's item.
    private static let service = "com.flowmap.app.secrets"

    public enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            // Deliberately vague: an error string must never carry the secret.
            "The key could not be saved to your Keychain."
        }
    }

    /// Stores or replaces the value for `account`. An empty value deletes it.
    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(account: account) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    public static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func hasKey(account: String) -> Bool {
        get(account: account) != nil
    }

    /// What Settings shows instead of the key.
    ///
    /// Deliberately carries no characters of the secret at all — not even the
    /// last few. The only thing the user needs to know here is whether a key is
    /// present, and a trailing fragment is still part of the key.
    public static func maskedDescription(account: String) -> String {
        hasKey(account: account) ? "Saved · ••••••••" : "No key saved"
    }

    /// Strips anything that looks like a key from text heading for a log or an
    /// error message shown to the user.
    public static func redact(_ text: String) -> String {
        var redacted = text
        for pattern in ["sk-ant-[A-Za-z0-9_\\-]+", "sk-[A-Za-z0-9_\\-]{16,}", "Bearer [A-Za-z0-9_\\-\\.]+"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                range: NSRange(redacted.startIndex..., in: redacted),
                withTemplate: "[redacted]"
            )
        }
        return redacted
    }
}
