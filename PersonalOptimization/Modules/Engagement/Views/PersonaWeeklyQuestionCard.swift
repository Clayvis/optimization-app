import SwiftUI
import SwiftData

/// Weekly question card on TodayView. Surfaces ONE question from the curated
/// library, dismissible, with inline answer for the multi-choice ones. Free-
/// text questions route to the full PersonaQuestionnaireView. Throttled to
/// at most once per week (handled by PersonaService.shouldShowWeeklyQuestion).
@MainActor
struct PersonaWeeklyQuestionCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dismissed = false
    @State private var navigateToFull = false

    var body: some View {
        let service = PersonaService(modelContext: modelContext)
        if !dismissed, service.shouldShowWeeklyQuestion(), let question = service.nextQuestion() {
            content(question: question, service: service)
                .navigationDestination(isPresented: $navigateToFull) {
                    PersonaQuestionnaireView()
                }
                .onAppear { service.markQuestionAsked() }
        }
    }

    @ViewBuilder
    private func content(question: PersonaQuestion, service: PersonaService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.text.rectangle.fill")
                    .foregroundStyle(.tint)
                Text("COACH IS LEARNING YOU")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss for this week")
            }
            Text(question.prompt)
                .font(.body.weight(.medium))

            answerSurface(for: question, service: service)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func answerSurface(for question: PersonaQuestion, service: PersonaService) -> some View {
        switch question.kind {
        case .motivationDriver:
            chipPicker(options: PersonaMotivationDriver.allCases.map { ($0.rawValue, shortName(driver: $0)) },
                       question: question, service: service) { raw in
                service.currentOrCreate().motivationDriverRaw = raw
            }
        case .communicationStyle:
            chipPicker(options: PersonaCommunicationStyle.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                       question: question, service: service) { raw in
                service.currentOrCreate().communicationStyleRaw = raw
            }
        case .accountabilityPreference:
            chipPicker(options: PersonaAccountabilityPreference.allCases.map { ($0.rawValue, shortName(accountability: $0)) },
                       question: question, service: service) { raw in
                service.currentOrCreate().accountabilityPreferenceRaw = raw
            }
        case .failureResponse:
            chipPicker(options: PersonaFailureResponse.allCases.map { ($0.rawValue, shortName(failure: $0)) },
                       question: question, service: service) { raw in
                service.currentOrCreate().failureResponseRaw = raw
            }
        case .recoverySensitivity:
            chipPicker(options: PersonaRecoverySensitivity.allCases.map { ($0.rawValue, shortName(sensitivity: $0)) },
                       question: question, service: service) { raw in
                service.currentOrCreate().recoverySensitivityRaw = raw
            }
        case .peakAlertness:
            chipPicker(options: PersonaPeakAlertness.allCases.map { ($0.rawValue, shortName(peak: $0)) },
                       question: question, service: service) { raw in
                service.currentOrCreate().peakAlertnessRaw = raw
            }
        case .decisionStyle:
            chipPicker(options: PersonaDecisionStyle.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                       question: question, service: service) { raw in
                service.currentOrCreate().decisionStyleRaw = raw
            }
        case .identityAnchors, .historicalAttempts, .goodWeek, .idealCoachLine:
            // Free-text answers route to the full questionnaire where there's room.
            Button {
                navigateToFull = true
            } label: {
                Label("Answer in Settings", systemImage: "arrow.right.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func chipPicker(options: [(String, String)],
                            question: PersonaQuestion,
                            service: PersonaService,
                            apply: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.0) { option in
                Button {
                    apply(option.0)
                    service.recordAnswer(key: question.key)
                    try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
                    dismissed = true
                } label: {
                    Text(option.1)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Short display names for the chip surface — the full Settings view uses
    // the longer parenthetical versions.
    private func shortName(driver: PersonaMotivationDriver) -> String {
        switch driver {
        case .mastery:        return "Mastery"
        case .accomplishment: return "Accomplishment"
        case .autonomy:       return "Autonomy"
        case .social:         return "Social"
        case .identity:       return "Identity"
        case .vitality:       return "Vitality"
        }
    }
    private func shortName(accountability: PersonaAccountabilityPreference) -> String {
        switch accountability {
        case .gentleCheckIn: return "Gentle"
        case .hardTruth:     return "Hard truth"
        case .dataOnly:      return "Data only"
        case .encouragement: return "Encouragement"
        }
    }
    private func shortName(failure: PersonaFailureResponse) -> String {
        switch failure {
        case .pushThrough: return "Push"
        case .recalibrate: return "Shorten"
        case .rest:        return "Rest"
        case .talkItOut:   return "Talk"
        }
    }
    private func shortName(sensitivity: PersonaRecoverySensitivity) -> String {
        switch sensitivity {
        case .lowListener:  return "Override fatigue"
        case .balanced:     return "Balanced"
        case .highListener: return "First signal"
        }
    }
    private func shortName(peak: PersonaPeakAlertness) -> String {
        switch peak {
        case .earlyMorning: return "Early AM"
        case .morning:      return "Morning"
        case .afternoon:    return "Afternoon"
        case .evening:      return "Evening"
        case .lateNight:    return "Late night"
        }
    }
}

/// Minimal flow-layout container so chips wrap. SwiftUI ships
/// `Layout` protocol — keep it tight, no external dependency.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
