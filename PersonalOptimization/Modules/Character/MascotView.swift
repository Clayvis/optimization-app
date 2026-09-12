import SwiftUI

private struct MascotReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mascotReducedMotion: Bool {
        get { self[MascotReducedMotionKey.self] }
        set { self[MascotReducedMotionKey.self] = newValue }
    }
}

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
            MascotIllustration(stateName: state.artworkState.rawValue, palette: .forVariant(variant))
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

/// Native motion around the existing art. Animators exist only while visible
/// and active; Reduce Motion removes them, including tap and win reactions.
/// No unstructured sleeping tasks can outlive a screen or overlap rapid taps.
struct AnimatedMascotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mascotReducedMotion) private var appReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    let state: CharacterState
    var variant: String = "ninja_male"
    var size: CGFloat = 160
    var interactionCount = 0

    private struct Reaction: Equatable {
        let state: CharacterState
        let interactionCount: Int
    }

    private struct Pose {
        var lift: Double = 0
    }

    var body: some View {
        ZStack {
            if isVisible && scenePhase == .active && !reduceMotion && !appReduceMotion {
                art
                    .phaseAnimator([false, true]) { content, raised in
                        content
                            .scaleEffect(raised ? 1.015 : 1)
                            .offset(y: raised ? -size * idleLift : 0)
                            .rotationEffect(.degrees(raised ? idleTilt : -idleTilt))
                    } animation: { _ in
                        .easeInOut(duration: idleDuration)
                    }
                    .keyframeAnimator(initialValue: Pose(),
                                      trigger: Reaction(state: state, interactionCount: interactionCount)) { content, pose in
                        content
                            .scaleEffect(1 + pose.lift * 0.05)
                            .offset(y: -size * pose.lift * 0.045)
                            .rotationEffect(.degrees(state == .comeback ? pose.lift * 5 : 0))
                    } keyframes: { _ in
                        KeyframeTrack(\.lift) {
                            CubicKeyframe(-0.2, duration: 0.1)
                            SpringKeyframe(1, duration: 0.24, spring: .bouncy)
                            CubicKeyframe(0, duration: 0.3)
                        }
                    }
            } else {
                art
            }
            if let symbol = state.reactionSymbol {
                Image(systemName: symbol)
                    .font(.system(size: max(12, min(22, size * 0.16)), weight: .semibold))
                    .foregroundStyle(state == .celebrating ? Theme.kin : Theme.matcha)
                    .padding(size * 0.045)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: size * 0.32, y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var art: some View {
        MascotView(state: state, variant: variant)
            .frame(width: size, height: size)
            // The pose changes immediately. Only the outer transforms animate;
            // otherwise an idle phase blends two PNGs for several seconds.
            .transaction { $0.animation = nil }
    }

    private var idleDuration: Double {
        switch state {
        case .training: return 0.85
        case .recovering, .tired, .fasting: return 4
        default: return 2.8
        }
    }

    private var idleLift: Double {
        switch state {
        case .training: return 0.025
        case .recovering, .tired: return 0
        default: return 0.012
        }
    }

    private var idleTilt: Double {
        switch state {
        case .training: return 1.5
        case .comeback: return 2
        case .celebrating, .achievement, .proud: return 0.8
        default: return 0
        }
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
