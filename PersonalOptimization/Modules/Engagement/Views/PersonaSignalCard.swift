import SwiftUI
import SwiftData

/// TodayView surface for passive persona inference. Shows the highest-confidence
/// behavior-derived proposal with Accept / Not me actions. Hidden when there are
/// no signals or the user has dismissed them all.
///
/// Companion to PersonaWeeklyQuestionCard (which surfaces active-inference
/// questions). The two never appear together — if a signal is available we
/// surface that first; otherwise we fall through to the weekly question.
@MainActor
struct PersonaSignalCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hiddenForSession = false
    @State private var lastSignalKey: String?

    var body: some View {
        let service = PersonaService(modelContext: modelContext)
        let signals = service.inferFromBehavior()
        if !hiddenForSession, let signal = signals.first {
            content(signal: signal, service: service)
                .onAppear { lastSignalKey = signal.key }
        }
    }

    @ViewBuilder
    private func content(
        signal: PersonaBehavioralInference.PersonaSignal,
        service: PersonaService
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("COACH NOTICED A PATTERN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(signal.confidence)%")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(Capsule())
            }
            Text(headlineCopy(signal: signal))
                .font(.body.weight(.medium))
            Text(signal.evidence)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    service.acceptSignal(signal)
                    hiddenForSession = true
                } label: {
                    Label("Sounds right", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    service.dismissSignal(signal)
                    hiddenForSession = true
                } label: {
                    Text("Not me")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func headlineCopy(signal: PersonaBehavioralInference.PersonaSignal) -> String {
        switch signal.field {
        case .peakAlertness:
            return "You seem to do your best work in the \(signal.proposedDisplay.lowercased())."
        case .recoverySensitivity:
            return "Your recovery pattern reads as: \(signal.proposedDisplay)."
        case .failureResponse:
            return "After a miss, your default looks like: \(signal.proposedDisplay)."
        case .decisionStyle:
            return "When the coach offers a call, you tend to: \(signal.proposedDisplay)."
        }
    }
}
