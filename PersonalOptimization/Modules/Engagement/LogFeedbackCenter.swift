import SwiftUI

/// Centralized in-the-moment logging feedback for the iOS app.
///
/// When the user logs a protocol behavior, the originating view calls
/// `confirm(_:)`. That does three things at once:
///   1. Surfaces a transient, identity-framed banner (design principle 4:
///      confirmations reinforce who the user is, not what task was ticked).
///   2. Posts `.userStateChanged` so the mascot recomputes immediately
///      (principle 7: mascot reflects real state) and the streak counters plus
///      the Today master metric rederive at once, instead of waiting for the
///      60-second tick or the next HealthKit sync.
///   3. Drives one success haptic via the overlay (principle 5: tap-to-log
///      should feel acknowledged without extra steps).
///
/// UI-only state. No persistence, so it touches nothing in the retention model.
@MainActor
@Observable
final class LogFeedbackCenter {
    static let shared = LogFeedbackCenter()

    /// The message currently shown, or nil when the banner is hidden.
    private(set) var message: String?

    /// Monotonic token, bumped on every confirm. Views read it to rederive on a
    /// log; the overlay keys its transition and haptic to it so a repeat of the
    /// same message (two water logs both reading "Streak alive.") still animates.
    private(set) var token: Int = 0

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Confirms a just-completed log. Safe to call from any view's log action.
    /// - Parameter message: identity-framed copy, typically from `IdentityCopy`.
    func confirm(_ message: String) {
        self.message = message
        token &+= 1
        // Instant, truthful downstream refresh: mascot + streak counters +
        // Today master metric. `.userStateChanged` is the sanctioned
        // user-action signal (see AppNotifications.swift), distinct from the
        // bursty HealthKit-sourced `.dailyLogsRecomputed`.
        NotificationCenter.default.post(name: .userStateChanged, object: nil)

        dismissTask?.cancel()
        let shown = token
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))  // MARK: try? justified - sleep only throws on cancellation, handled by the token guard below.
            guard let self, !Task.isCancelled, self.token == shown else { return }
            self.message = nil
        }
    }
}

// MARK: - Overlay

private struct LogFeedbackOverlay: ViewModifier {
    @State private var center = LogFeedbackCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = center.message {
                    LogConfirmationBanner(message: message)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .id(center.token)
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: center.token)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: center.message)
            .sensoryFeedback(.success, trigger: center.token)
    }
}

extension View {
    /// Mounts the global log-confirmation banner. Apply once near the app root.
    func logFeedbackOverlay() -> some View {
        modifier(LogFeedbackOverlay())
    }
}

private struct LogConfirmationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.green.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}

#Preview {
    Color(.systemBackground)
        .logFeedbackOverlay()
        .task {
            LogFeedbackCenter.shared.confirm(IdentityCopy.hydrationLogged)
        }
}
