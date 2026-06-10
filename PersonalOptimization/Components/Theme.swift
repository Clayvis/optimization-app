import SwiftUI
import UIKit

/// Ninja / samurai modern design system.
///
/// Aesthetic: sumi-e ink grounds, `kurenai` crimson as the blade accent, `kin`
/// gold reserved for earned moments (streaks, achievement), `ai` indigo for
/// water, `matcha` jade for "done / active". Adaptive by design: a lacquer-dark
/// palette in Dark Mode, warm washi-paper in Light Mode, so the app keeps a
/// cohesive identity without fighting the system appearance.
///
/// Tokens live here. Reusable surfaces (cards, rings, headers) live in
/// `DojoComponents.swift`. No image assets: every motif is drawn in SwiftUI, in
/// keeping with the zero-dependency / minimal-asset constraint.
enum Theme {

    // MARK: - Palette (adaptive)

    /// Deepest ground, behind everything (lacquer black / warm paper).
    static let inkVoid = dyn(light: hex(0xF3EFE7), dark: hex(0x0A0B0D))
    /// Primary screen background.
    static let inkBase = dyn(light: hex(0xEDE7DB), dark: hex(0x111317))
    /// Raised card surface.
    static let inkRaised = dyn(light: hex(0xFBF8F1), dark: hex(0x1A1D23))
    /// A second elevation for nested fills (progress tracks, chips).
    static let inkSunken = dyn(light: hex(0xE4DCCB), dark: hex(0x24282F))

    /// Hairline stroke (a fine inlay edge on cards and dividers).
    static let hairline = dyn(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.08))

    /// Primary text (sumi ink / washi paper).
    static let textPrimary = dyn(light: hex(0x16130E), dark: hex(0xECEAE3))
    /// Secondary text (faded ink / mist).
    static let textSecondary = dyn(light: hex(0x5A554C), dark: hex(0x9AA0AB))
    /// Tertiary / disabled.
    static let textTertiary = dyn(light: hex(0x8A857A), dark: hex(0x646B76))

    // MARK: - Pigments (brand accents, stable across appearance)

    /// Kurenai — deep crimson. The blade. Primary accent + brand tint.
    static let kurenai = hex(0xE6394A)
    static let kurenaiDeep = hex(0x9E1B28)
    /// Kin — gold leaf. Reserved for streaks, achievement, "earned" moments.
    static let kin = hex(0xD7A23B)
    static let kinDeep = hex(0x9A6E1E)
    /// Ai — Japanese indigo. Water / hydration.
    static let ai = hex(0x3E78C9)
    /// Matcha — jade. Active / complete / go.
    static let matcha = hex(0x4Fae7c)
    /// Murasaki — muted violet. Learning / focus.
    static let murasaki = hex(0x8A6FC4)

    // MARK: - Gradients

    /// Crimson blade gradient (primary buttons, key rings).
    static let bladeGradient = LinearGradient(
        colors: [kurenai, kurenaiDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Gold leaf gradient (streak flame, achievement crest).
    static let goldGradient = LinearGradient(
        colors: [hex(0xF0C969), kin, kinDeep],
        startPoint: .top, endPoint: .bottom
    )
    /// Deep ground gradient painted behind screens.
    static var groundGradient: LinearGradient {
        LinearGradient(colors: [inkVoid, inkBase], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Metrics

    enum Radius {
        static let chip: CGFloat = 10
        static let card: CGFloat = 18
        static let sheet: CGFloat = 26
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Typography

    /// Large tracked numerals (the master metric, timers). SF Rounded.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Section eyebrow: small, uppercase, wide tracking (a stamped-seal feel).
    static let eyebrow = Font.system(size: 12, weight: .semibold, design: .rounded)

    // MARK: - Global chrome

    /// One-shot UIKit appearance pass for chrome SwiftUI cannot style
    /// directly: heavy rounded navigation titles (modern, matches the
    /// numeral face) on a clear bar so the dojo ground shows through.
    /// Call once at app launch.
    @MainActor
    static func installAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        let large = UIFont.systemFont(ofSize: 34, weight: .heavy)
        let title = UIFont.systemFont(ofSize: 17, weight: .semibold)
        if let largeRounded = large.fontDescriptor.withDesign(.rounded) {
            nav.largeTitleTextAttributes = [.font: UIFont(descriptor: largeRounded, size: 34)]
        }
        if let titleRounded = title.fontDescriptor.withDesign(.rounded) {
            nav.titleTextAttributes = [.font: UIFont(descriptor: titleRounded, size: 17)]
        }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    // MARK: - Helpers

    /// Build an adaptive `Color` from a light and dark variant.
    static func dyn(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// 0xRRGGBB literal to `Color`.
    static func hex(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
