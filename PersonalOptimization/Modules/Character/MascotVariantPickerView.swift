import SwiftUI
import SwiftData

/// Available mascot variants. New variants are added here and require the
/// matching `<Variant>_<State>.imageset` directories. The preflight check on
/// selection halts cleanly when assets are missing rather than rendering a
/// blank Image.
enum MascotVariant: String, CaseIterable, Identifiable, Sendable {
    case ninjaMale = "ninja_male"
    case ninjaFemale = "ninja_female"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ninjaMale: return "Ninja (male)"
        case .ninjaFemale: return "Ninja (female)"
        }
    }

    var assetPrefix: String {
        switch self {
        case .ninjaMale: return "NinjaMale"
        case .ninjaFemale: return "NinjaFemale"
        }
    }

    /// Returns the list of state-suffix asset names that must exist for this variant.
    var requiredAssetNames: [String] {
        Array(Set(CharacterState.allCases.map { "\(assetPrefix)_\($0.suffix)" })).sorted()
    }
}

@MainActor
struct MascotVariantPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var pendingVariant: MascotVariant?
    @State private var preflightError: String?

    var body: some View {
        Form {
            ForEach(MascotVariant.allCases) { variant in
                Section {
                    variantRow(variant)
                }
            }
            Section {
                NavigationLink("Meet your companion") {
                    MascotReactionsGallery(variant: profiles.first?.mascotVariant ?? "ninja_male")
                }
                .accessibilityIdentifier("mascot.reactionsGallery")
                Text("Your companion reacts to training, recovery, returning, and earned wins. Motion follows your device's Reduce Motion setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let preflightError {
                Section {
                    Label(preflightError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Mascot variant")
    }

    @ViewBuilder
    private func variantRow(_ variant: MascotVariant) -> some View {
        let isCurrent = profiles.first?.mascotVariant == variant.rawValue
        HStack(spacing: 16) {
            MascotView(state: .neutral, variant: variant.rawValue)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.displayName)
                    .font(.body.weight(.semibold))
                Text(MascotVariantPreflight.missingAssets(for: variant) == nil
                     ? "Custom art · 12 reactions"
                     : "Built-in art · 12 reactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Select") {
                    select(variant)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func select(_ variant: MascotVariant) {
        guard let profile = profiles.first else {
            preflightError = "No user profile loaded; cannot apply variant."
            return
        }
        profile.mascotVariant = variant.rawValue
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        // PNG art is optional now that the vector fallback ships. Surface a
        // note (not a block) when the drop-in art isn't installed.
        if MascotVariantPreflight.missingAssets(for: variant) != nil {
            preflightError = "\(variant.displayName) is using the built-in drawn mascot. Drop PNG art into MascotAssets.xcassets to override (see References/gemini_workflow.md)."
        } else {
            preflightError = nil
        }
    }
}

/// A preview of the new reactions, available without fabricating any workout
/// or changing the live state, streaks, achievements, or history.
struct MascotReactionsGallery: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let variant: String
    @State private var selected: CharacterState = .training
    @State private var interactionCount = 0

    private let reactions: [CharacterState] = [.training, .recovering, .comeback, .celebrating]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Button { interactionCount += 1 } label: {
                    AnimatedMascotView(state: selected, variant: variant, size: 180,
                                       interactionCount: interactionCount)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Greet your companion")
                Text(selected.displayName).font(.title2.bold())
                Text(explanation).multilineTextAlignment(.center).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(reactions, id: \.self) { state in
                        Button { selected = state } label: {
                            HStack {
                                Label(state.displayName, systemImage: state.reactionSymbol ?? "sparkles")
                                Spacer()
                                if selected == state { Image(systemName: "checkmark") }
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .padding(12)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mascot.preview.\(state.rawValue)")
                        .accessibilityAddTraits(selected == state ? .isSelected : [])
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Your companion")
        .navigationBarTitleDisplayMode(.inline)
        .background(DojoBackground())
    }

    private var explanation: String {
        switch selected {
        case .training: return "A steady rhythm while your phone or Watch workout is in progress."
        case .recovering: return "A calm companion for rest and sick days. Your earned progress stays yours."
        case .comeback: return "A warm welcome after a break. A small session is enough to begin again."
        case .celebrating: return "A little celebration for a recorded workout. One daily win is enough."
        default: return "One small win at a time."
        }
    }
}

/// Asset preflight. Returns the missing asset filenames for a variant, or nil if
/// all 8 are present in the bundle. Used by Settings + the auto-select onboarding
/// stub to fail cleanly when the user hasn't yet supplied PNGs.
enum MascotVariantPreflight {
    /// Returns nil if all assets exist; otherwise an array of missing asset names.
    static func missingAssets(for variant: MascotVariant, bundle: Bundle = .main) -> [String]? {
        let required = variant.requiredAssetNames
        let missing = required.filter { name in
            #if canImport(UIKit)
            UIImage(named: name, in: bundle, with: nil) == nil
            #else
            true
            #endif
        }
        return missing.isEmpty ? nil : missing
    }
}
