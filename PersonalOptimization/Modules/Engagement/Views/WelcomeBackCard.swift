import SwiftUI
import SwiftData

/// Surfaces a soft, identity-framed welcome-back card when the user is
/// returning from a hard lapse (5+ low-adherence days). Suppresses itself
/// after the user dismisses it once. Soft lapses (2 days) don't surface a
/// card at all; the Coach prompt warms its tone instead.
@MainActor
struct WelcomeBackCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LapseEvent.detectedAt, order: .reverse)])
    private var lapses: [LapseEvent]

    @State private var dismissed: Bool = false

    private var activeLapse: LapseEvent? {
        lapses.first { $0.resolvedAt == nil && !$0.welcomeBackShown }
    }

    var body: some View {
        if !dismissed, let lapse = activeLapse, lapse.severity != .soft {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.wave.fill")
                        .foregroundStyle(.tint)
                    Text(headerText(for: lapse))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(messageText(for: lapse))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reframeText(for: lapse))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("I'm back") {
                        markSeen(lapse)
                        dismissed = true
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not yet") {
                        dismissed = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func headerText(for lapse: LapseEvent) -> String {
        switch lapse.severity {
        case .soft:    return "WELCOME BACK"
        case .hard:    return "WELCOME BACK"
        case .crisis:  return "WE'VE MISSED YOU"
        }
    }

    private func messageText(for lapse: LapseEvent) -> String {
        switch lapse.severity {
        case .soft:
            return "Open day. You write the plan."
        case .hard:
            return "You're here. That's the rep that counts."
        case .crisis:
            return "Tough stretch. The standard hasn't moved; the entry point has."
        }
    }

    private func reframeText(for lapse: LapseEvent) -> String {
        switch lapse.severity {
        case .soft:
            return "Pick one small win for today and keep moving."
        case .hard:
            return "Today's bar is small: one log, one drink, one block. That's the whole ask."
        case .crisis:
            return "Want me to simplify the schedule for the next two weeks while you reset? Open Settings → Schedule any time."
        }
    }

    private func markSeen(_ lapse: LapseEvent) {
        let service = LapseDetectionService(modelContext: modelContext)
        service.markWelcomeBackShown(lapse)
    }
}
