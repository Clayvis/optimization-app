import Foundation
import Security
import os

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Item not found in Keychain"
        case .duplicateItem: return "Item already exists in Keychain"
        case .unexpectedStatus(let status): return "Keychain operation failed: \(status)"
        }
    }
}

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let logger = Logger.keychain
    private let service = "com.rawlins.PersonalOptimization"

    private init() {}

    func setApiKey(_ key: String) throws {
        try set(key: "anthropic_api_key", value: key)
    }

    func getApiKey() throws -> String {
        try get(key: "anthropic_api_key")
    }

    func deleteApiKey() throws {
        try delete(key: "anthropic_api_key")
    }

    /// M4.2: one-time migration from the legacy `ThisDeviceOnly` keychain
    /// item to the iCloud-synced replacement. Idempotent — re-runs are no-ops.
    /// Call once on app launch. Safe sequence: copy first, then delete the old
    /// item only after the new write succeeds.
    func migrateApiKeyToICloudSynced() {
        // Probe the old item using the explicit ThisDeviceOnly attribute set.
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "anthropic_api_key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let probe = SecItemCopyMatching(oldQuery as CFDictionary, &result)
        guard probe == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return
        }
        // Write the new (synchronizable) item. If this fails, we keep the old.
        do {
            try set(key: "anthropic_api_key", value: value)
        } catch {
            logger.warning("Keychain iCloud migration: new-item write failed, keeping legacy")
            return
        }
        // Only delete the old after the new write succeeded.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "anthropic_api_key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        logger.info("Keychain migrated API key to iCloud-synced item")
    }

    private func set(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }
        // M4.2: API key now persists across uninstall AND syncs to other Apple
        // devices via iCloud Keychain. The user is the sole owner of the key
        // and their iCloud; no threat-model change vs. SwiftData CloudKit.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain set failed status=\(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func get(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Match items regardless of which sync state they're stored in so
            // we find both pre- and post-migration items.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        return value
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
