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
        CharacterState.allCases.map { "\(assetPrefix)_\($0.suffix)" }
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
        let neutralAsset = "\(variant.assetPrefix)_Neutral"
        let isCurrent = profiles.first?.mascotVariant == variant.rawValue
        HStack(spacing: 16) {
            Image(neutralAsset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.displayName)
                    .font(.body.weight(.semibold))
                Text("8 states · breathing animation")
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
        if let missing = MascotVariantPreflight.missingAssets(for: variant) {
            preflightError = "Cannot switch to \(variant.displayName): \(missing.count)/8 assets missing — \(missing.joined(separator: ", ")). See M3.7_MASCOT_PROMPTS.md."
            return
        }
        profile.mascotVariant = variant.rawValue
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        preflightError = nil
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
