import SwiftUI
import SwiftData

/// The live companion in the Dojo. Motion is owned by the rendering view so
/// every surface uses the same reactions and accessibility policy.
struct CharacterView: View {
    let service: CharacterStateService
    @Query private var profiles: [UserProfile]
    var size: CGFloat = 200
    var showsReason: Bool = true
    @State private var interactionCount = 0

    init(service: CharacterStateService = .shared, size: CGFloat = 200, showsReason: Bool = true) {
        self.service = service
        self.size = size
        self.showsReason = showsReason
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                interactionCount += 1
            } label: {
                AnimatedMascotView(state: service.currentState,
                                   variant: profiles.first?.mascotVariant ?? "ninja_male",
                                   size: size, interactionCount: interactionCount)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.currentState.displayName)
            .accessibilityValue(displayReason)
            .accessibilityHint("Tap to greet your companion")
            .accessibilityIdentifier("mascot.companion")

            if showsReason {
                Text(service.currentState.displayName)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mascot.state")
                Text(displayReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: interactionCount)
    }

    private var displayReason: String {
        let reason = service.triggerReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty || reason == "default" { return "One small win at a time. I'm here with you." }
        if reason == "travel mode" { return "Away from your routine. Your progress stays with you." }
        return reason
    }
}

#Preview {
    CharacterView(size: 200)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
}
