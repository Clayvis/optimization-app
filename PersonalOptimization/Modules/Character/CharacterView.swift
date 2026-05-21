import SwiftUI
import SwiftData

/// Renders the current character state with breathing animation, alert pulses on
/// `.urgent` and `.achievement`, and a cross-fade transition between states.
/// Honors the system reduce-motion setting and the user's `mascotVariant` choice.
struct CharacterView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // CharacterStateService is @Observable so SwiftUI tracks its property
    // reads without needing @Bindable. The view only reads from the
    // service — no two-way binding required. Default to the shared
    // instance for production callers; tests inject a fixture.
    let service: CharacterStateService
    @Query private var profiles: [UserProfile]

    var size: CGFloat = 200
    var showsReason: Bool = true

    @State private var breathing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var lastAlertState: CharacterState?

    init(service: CharacterStateService = .shared, size: CGFloat = 200, showsReason: Bool = true) {
        self.service = service
        self.size = size
        self.showsReason = showsReason
    }

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
        .sensoryFeedback(trigger: service.currentState) { _, newValue in
            switch newValue {
            case .achievement: return .success
            case .urgent:      return .warning
            case .proud:       return .increase
            default:           return nil
            }
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
        // Use a Task with Task.sleep instead of DispatchQueue.main.asyncAfter
        // per CLAUDE.md's "async/await everywhere" rule. Task automatically
        // captures @MainActor isolation and cancels cleanly if the view
        // leaves the hierarchy.
        Task { @MainActor in
            // MARK: - try? justified because Task.sleep only throws on
            // cancellation; if the view cancels, we want the animation
            // settle to skip silently.
            try? await Task.sleep(for: .milliseconds(250))
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
