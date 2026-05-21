import Foundation
import os

/// Resolves the shared App Group container URL used by every production
/// ModelContainer (phone, watch, complications). Falling back to the per-target
/// sandbox would mean the watch and complications would each open their own
/// local SwiftData store and rely entirely on CloudKit to reconcile, leaving
/// the complication one CloudKit cycle behind the watch app it sits next to.
enum AppGroupContainer {
    static let identifier = BuildConfig.appGroupID

    /// Shared store URL. nil if the App Group is not entitled for the running
    /// process (in that case callers should fall back to the default sandbox
    /// URL so the app still launches in unexpected configurations).
    static func storeURL() -> URL? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            Logger.persistence.warning("App Group container URL unavailable for \(identifier, privacy: .public); falling back to per-target sandbox.")
            return nil
        }
        return url.appendingPathComponent("default.store")
    }
}
