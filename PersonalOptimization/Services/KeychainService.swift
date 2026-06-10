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
    private let service = BuildConfig.keychainServiceID

    private init() {}

    /// Default-iCloud-sync overload preserved for back-compat. New code
    /// should use the explicit-posture overload below and read the user's
    /// preference from UserProfile.apiKeyICloudSync.
    func setApiKey(_ key: String) throws {
        try setApiKey(key, iCloudSync: true)
    }

    /// Writes the API key with the requested sync posture.
    /// - `iCloudSync: true` → `kSecAttrSynchronizable` so the key follows the
    ///   user across their Apple devices via iCloud Keychain (M4.2 default).
    /// - `iCloudSync: false` → `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
    ///   so the key never leaves this device (stronger security posture).
    /// Both variants are cleaned up first so toggling never leaves stale items.
    func setApiKey(_ key: String, iCloudSync: Bool) throws {
        // MARK: - try? justified because variant-cleanup is best-effort. The
        // new write below targets a specific posture; pre-deleting the
        // opposite posture prevents stale Keychain items, and its failure
        // (typically errSecItemNotFound) must not block the primary set
        // operation, which has its own error path.
        try? delete(key: "anthropic_api_key", synchronizableSpecific: true)  // MARK: try? justified - best-effort; failure logged inside the called function.
        try? delete(key: "anthropic_api_key", synchronizableSpecific: false)  // MARK: try? justified - best-effort; failure logged inside the called function.
        try set(key: "anthropic_api_key", value: key, iCloudSync: iCloudSync)
    }

    func getApiKey() throws -> String {
        try get(key: "anthropic_api_key")
    }

    func deleteApiKey() throws {
        try delete(key: "anthropic_api_key")
    }

    /// Returns the current storage posture of the API key, or nil if no key
    /// is stored at all. Used by Diagnostics + Settings to surface
    /// "Stored on this device only" vs "Synced via iCloud Keychain".
    func apiKeySyncPosture() -> KeyStoragePosture? {
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        if (try? getSpecific(key: "anthropic_api_key", synchronizable: true)) != nil {
            return .iCloudSynced
        }
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        if (try? getSpecific(key: "anthropic_api_key", synchronizable: false)) != nil {
            return .thisDeviceOnly
        }
        return nil
    }

    /// M4.2: one-time migration from the legacy `ThisDeviceOnly` keychain
    /// item to the iCloud-synced replacement. Idempotent — re-runs are no-ops.
    /// One-shot, best-effort migration of a legacy device-only API key item to
    /// the iCloud-synced posture, gated on the user's CURRENT sync preference.
    /// When the user opted out of sync (`syncDesired == false`) this is a no-op,
    /// so a launch-time migration can never silently revert a device-only choice.
    func migrateApiKeyToICloudSyncedIfDesired(_ syncDesired: Bool) {
        guard syncDesired else { return }
        migrateApiKeyToICloudSynced()
    }

    /// Call once on app launch. Safe sequence: copy first, then delete the old
    /// item only after the new write succeeds.
    private func migrateApiKeyToICloudSynced() {
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

    private func set(key: String, value: String, iCloudSync: Bool = true) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        if iCloudSync {
            // M4.2: API key persists across uninstall AND syncs to other Apple
            // devices via iCloud Keychain.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        } else {
            // ThisDeviceOnly posture: stronger security; key never leaves
            // this device. Surface via Settings opt-out toggle.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        }
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

    /// Fetch only the variant matching `synchronizable`. Distinct from `get`
    /// which finds either variant. Used by `apiKeySyncPosture()` to discover
    /// which posture is currently active.
    private func getSpecific(key: String, synchronizable: Bool) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: (synchronizable ? kCFBooleanTrue : kCFBooleanFalse) as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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

    /// Variant-scoped delete used by `setApiKey(_:iCloudSync:)` to cleanly
    /// purge the opposite posture before writing.
    private func delete(key: String, synchronizableSpecific: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: (synchronizableSpecific ? kCFBooleanTrue : kCFBooleanFalse) as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeyStoragePosture: String, Sendable {
    case thisDeviceOnly
    case iCloudSynced

    var displayLabel: String {
        switch self {
        case .thisDeviceOnly: return "Stored on this device only"
        case .iCloudSynced: return "Synced via iCloud Keychain"
        }
    }
}
