import SwiftUI
import SwiftData
import UIKit

struct LearningTimerView: View {
    let module: LearningModule
    let service: LearningService

    @Query private var logs: [DailyLog]
    @Query private var streaks: [LearningStreak]

    @State private var startedAt: Date?
    @State private var manualMinutes: Int = 5

    var body: some View {
        Form {
            Section {
                liveTimerSection
            }

            Section("Manual log") {
                Stepper("\(manualMinutes) min", value: $manualMinutes, in: 1...120)
                Button {
                    log(minutes: manualMinutes)
                } label: {
                    Label("Add \(manualMinutes) min", systemImage: "plus.circle.fill")
                }
            }

            Section("Today") {
                let today = Calendar.current.startOfDay(for: Date())
                let todayLog = logs.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
                let minutes: Int = {
                    switch module {
                    case .japanese: return todayLog?.japaneseMinutes ?? 0
                    case .guitar:   return todayLog?.guitarMinutes ?? 0
                    case .music:    return todayLog?.musicMinutes ?? 0
                    }
                }()
                LabeledContent("Logged", value: "\(minutes) min")
                LabeledContent("Target", value: "\(module.defaultDailyTargetMinutes) min")
            }

            Section("Streak") {
                let streak = streaks.first { $0.module == module.rawValue }
                LabeledContent("Current", value: "\(streak?.currentStreak ?? 0) days")
                LabeledContent("Longest", value: "\(streak?.longestStreak ?? 0) days")
                LabeledContent("All-time minutes", value: "\(streak?.totalMinutesAllTime ?? 0)")
            }

            if module == .japanese {
                Section {
                    Button {
                        openPimsleur()
                    } label: {
                        Label("Open Pimsleur", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
        .navigationTitle(module.displayName)
    }

    @ViewBuilder
    private var liveTimerSection: some View {
        if let startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                HStack {
                    Image(systemName: "stopwatch.fill").foregroundStyle(.tint)
                    Text(formatDuration(elapsed))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Button("Stop") {
                        let minutes = max(1, Int(elapsed / 60))
                        log(minutes: minutes)
                        self.startedAt = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Button {
                startedAt = Date()
            } label: {
                Label("Start session", systemImage: "play.circle.fill")
            }
        }
    }

    private func log(minutes: Int) {
        // try? justified: SwiftData local write; failures already logged inside the
        // service and are not user-actionable in this UI.
        _ = try? service.logMinutes(module: module, minutes: minutes)  // MARK: try? justified - best-effort; failure logged inside the called function.
        LogFeedbackCenter.shared.confirm(IdentityCopy.learningLogged)
    }

    private func openPimsleur() {
        let preferred = PimsleurDeepLink.preferredURL()
        UIApplication.shared.open(preferred, options: [:]) { success in
            if !success {
                UIApplication.shared.open(PimsleurDeepLink.fallbackURL())
            }
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
