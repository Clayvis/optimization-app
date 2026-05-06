import Foundation

enum PimsleurDeepLink {
    /// Pimsleur app's documented URL scheme is "pimsleur://". Apple does not provide
    /// a definitive answer about Pimsleur registering this scheme, so callers should
    /// also be ready to fall back to the App Store deep link.
    static let appURL = URL(string: "pimsleur://")!

    /// App Store fallback for installing Pimsleur if the deep link does not resolve.
    /// Pimsleur Premium item id 1422256900.
    static let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id1422256900")!

    /// Returns the URL the app should attempt first when the user taps "Open Pimsleur".
    static func preferredURL() -> URL {
        appURL
    }

    /// Returns the URL to open if the preferred deep link cannot be resolved.
    static func fallbackURL() -> URL {
        appStoreURL
    }
}
