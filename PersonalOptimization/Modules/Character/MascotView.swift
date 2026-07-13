import SwiftUI

/// Single mascot rendering entry point for app surfaces.
///
/// Resolution order:
/// 1. `<Variant>_<State>` PNG from `MascotAssets.xcassets` when the user has
///    installed generated art (the M6.5 Gemini workflow).
/// 2. `MascotIllustration`, the built-in vector ninja, otherwise.
///
/// Callers size it with `.frame` and attach their own accessibility labels
/// (the mascot's meaning is contextual: state + trigger reason).
struct MascotView: View {
    let state: CharacterState
    var variant: String = "ninja_male"

    var body: some View {
        let assetName = state.assetName(for: variant)
        if Self.assetExists(named: assetName) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            MascotIllustration(stateName: state.rawValue, palette: .forVariant(variant))
        }
    }

    /// Bundle probe for the PNG override. `UIImage(named:)` caches lookups,
    /// so repeated checks are cheap.
    static func assetExists(named name: String, bundle: Bundle = .main) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name, in: bundle, with: nil) != nil
        #else
        return false
        #endif
    }
}

#Preview {
    VStack(spacing: 20) {
        MascotView(state: .proud)
            .frame(width: 160, height: 160)
        MascotView(state: .fasting, variant: "ninja_female")
            .frame(width: 160, height: 160)
    }
    .padding()
}
