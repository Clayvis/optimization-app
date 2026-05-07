import SwiftUI
import SwiftData

/// One-time celebration when the user crosses a registered milestone. Pulled
/// up from TodayView via `.sheet(item:)` when `MilestoneService.nextPendingCelebration()`
/// returns a row. Marks the unlock as shown so it doesn't re-fire on the
/// next app launch.
@MainActor
struct MilestoneCelebrationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    let unlock: MilestoneUnlock

    private var milestone: Milestone? {
        MilestoneRegistry.milestone(forID: unlock.identifier)
    }

    private var variant: String {
        profiles.first?.mascotVariant ?? "ninja_male"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if let m = milestone {
                Image(m.mascotState.assetName(for: variant))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .accessibilityLabel(m.mascotState.rawValue.capitalized)
                Text(m.unlockTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(m.unlockBody)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("Milestone reached.")
                    .font(.title2.weight(.bold))
            }
            Spacer()
            Button("Continue") {
                MilestoneService(modelContext: modelContext).markCelebrationShown(unlock)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: unlock.persistentModelID)
    }
}
