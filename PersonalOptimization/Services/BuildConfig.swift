import Foundation

/// Centralized app-identity constants. Sourced from the Info.plist key
/// `TeamBundlePrefix` (set via the `TEAM_BUNDLE_PREFIX` build setting in
/// project.yml) so a single rename propagates to every target — keychain
/// service id, App Group id, CloudKit container id, BG task id, OS Log
/// subsystem. The literal fallback keeps the app launching even if the
/// Info.plist key is absent.
enum BuildConfig {
    static let bundlePrefix: String = {
        if let info = Bundle.main.infoDictionary?["TeamBundlePrefix"] as? String,
           !info.isEmpty, info != "$(TEAM_BUNDLE_PREFIX)" {
            return info
        }
        return "com.rawlins.PersonalOptimization"
    }()

    static let loggingSubsystem: String = bundlePrefix
    static let appGroupID: String = "group.\(bundlePrefix)"
    static let cloudKitContainer: String = "iCloud.\(bundlePrefix)"
    static let keychainServiceID: String = bundlePrefix
    static let bgArchiveTaskID: String = "\(bundlePrefix).archiveRollup"
}
