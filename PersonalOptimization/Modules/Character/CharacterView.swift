import SwiftUI
import SwiftData

/// Renders the current character state with breathing animation, alert pulses on
/// `.urgent` and `.achievement`, and a cross-fade transition between states.
/// Honors the system reduce-motion setting and the user's `mascotVariant` choice.
struct CharacterView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var service = CharacterStateService.shared
    @Query private var profiles: [UserProfile]

    var size: CGFloat = 200
    var showsReason: Bool = true

    @State private var breathing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var lastAlertState: CharacterState?

    private var variant: String {
        profiles.first?.mascotVariant ?? "ninja_male"
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(service.currentState.assetName(for: variant))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .scaleEffect(reduceMotion ? 1.0 : (breathing ? 1.02 : 1.0) * pulseScale)
                    .id(service.currentState)
                    .transition(.opacity)
                    .accessibilityLabel(service.currentState.rawValue.capitalized)
                    .accessibilityHint(service.triggerReason)
            }
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.5), value: service.currentState)

            if showsReason, !isInternalReason(service.triggerReason) {
                Text(service.triggerReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            if !reduceMotion { startBreathing() }
            triggerAlertPulseIfNeeded(for: service.currentState)
        }
        .onChange(of: service.currentState) { _, newValue in
            triggerAlertPulseIfNeeded(for: newValue)
        }
    }

    /// Filters internal placeholder reasons that shouldn't be shown to the user.
    /// "default" and similar diagnostics ride in service.triggerReason for logging
    /// purposes; the UI should stay quiet when there's nothing meaningful to say.
    private func isInternalReason(_ reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "default"
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    private func triggerAlertPulseIfNeeded(for state: CharacterState) {
        guard !reduceMotion else { return }
        guard state == .urgent || state == .achievement else { return }
        guard lastAlertState != state else { return }
        lastAlertState = state

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            pulseScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                pulseScale = 1.0
            }
        }
    }
}

#Preview {
    CharacterView(size: 200)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
}
