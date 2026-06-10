import Foundation
import os

/// DEBUG-only convenience for local development. Reads an Anthropic API key
/// from a gitignored file at `.dev-secrets/anthropic_key.txt` (relative to the
/// repo root, copied into the bundle by the `Resources` build phase) and seeds
/// the Keychain with it on launch when the Keychain has no key yet.
///
/// Workflow:
///   1. Create `.dev-secrets/anthropic_key.txt` with the API key on its own
///      first line. The file is gitignored so the key never gets committed.
///   2. Launch the app in DEBUG. The bootstrap moves the key into Keychain.
///   3. After the first launch the file can be removed; the Keychain copy
///      survives `simctl erase` only if the simulator is not erased after.
///      In practice the file stays in place during dev so re-runs after erase
///      automatically restore the key.
///
/// Production (Release) builds never read this file; if the bundle ships
/// without a `.dev-secrets/` directory at all the bootstrap is a no-op.
enum DevSecretsBootstrap {
    private static let logger = Logger.keychain

    /// Run on app launch. Idempotent. Safe to call from production builds
    /// (compile-flag guarded so Release builds don't even reference the file
    /// path).
    static func bootstrapIfNeeded() {
        #if DEBUG
        do {
            let existing = try? KeychainService.shared.getApiKey()  // MARK: try? justified - best-effort decode/fetch; nil result is acceptable.
            if let existing, !existing.isEmpty { return }
            guard let key = readDevKey(), !key.isEmpty else { return }
            try KeychainService.shared.setApiKey(key)
            logger.info("Dev bootstrap: seeded Anthropic API key from .dev-secrets")
        } catch {
            logger.warning("Dev bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    #if DEBUG
    /// Looks for the dev-secrets file in the bundle resources. The file path
    /// is `.dev-secrets/anthropic_key.txt` from the repo root; project.yml
    /// pulls it into the iOS app bundle when the directory exists.
    private static func readDevKey() -> String? {
        guard let url = Bundle.main.url(forResource: "anthropic_key", withExtension: "txt") else {
            return nil
        }
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        guard let data = try? Data(contentsOf: url),  // MARK: try? justified - DEBUG-only optional secrets file; absence is the normal case.
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }
    #endif
}
