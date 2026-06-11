import SwiftUI
import SwiftData
import UIKit

/// One module's practice screen. The ring is live: while the stopwatch runs,
/// elapsed time counts toward today's target in real time. Quick-log chips
/// replace the stepper so a finished session is one tap to record.
struct LearningTimerView: View {
    let module: LearningModule
    let service: LearningService

    @Query private var logs: [DailyLog]
    @Query private var streaks: [LearningStreak]

    @State private var startedAt: Date?
    @State private var celebrationTrigger = 0

    private let quickPicks = [5, 10, 15, 20, 30, 45]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                progressCard
                quickLogCard
                streakCard
                if module == .japanese {
                    pimsleurCard
                }
            }
            .padding()
        }
        .navigationTitle(module.displayName)
        .scrollContentBackground(.hidden)
        .background(DojoBackground())
        .sensoryFeedback(.increase, trigger: celebrationTrigger)
    }

    private var loggedToday: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let todayLog = logs.first { $0.supersededAt == nil && Calendar.current.isDate($0.date, inSameDayAs: today) }
        switch module {
        case .japanese: return todayLog?.japaneseMinutes ?? 0
        case .guitar:   return todayLog?.guitarMinutes ?? 0
        case .music:    return todayLog?.musicMinutes ?? 0
        }
    }

    // MARK: - Progress + stopwatch

    @ViewBuilder
    private var progressCard: some View {
        let target = module.defaultDailyTargetMinutes

        VStack(spacing: Theme.Space.l) {
            if let startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                    ring(progress: (Double(loggedToday) + elapsed / 60) / Double(target)) {
                        VStack(spacing: 0) {
                            Text(formatDuration(elapsed))
                                .font(Theme.numeral(34))
                                .foregroundStyle(Theme.textPrimary)
                            Text("LIVE")
                                .font(Theme.eyebrow)
                                .tracking(1.6)
                                .foregroundStyle(Theme.kurenai)
                        }
                    }
                }
                Button {
                    let minutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
                    log(minutes: minutes)
                    self.startedAt = nil
                } label: {
                    Label("Stop and log", systemImage: "stop.fill")
                }
                .buttonStyle(BladeButtonStyle())
                .accessibilityLabel("Stop session and log elapsed minutes")
            } else {
                ring(progress: Double(loggedToday) / Double(target)) {
                    VStack(spacing: 0) {
                        Text("\(loggedToday)")
                            .font(Theme.numeral(34))
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(target) min")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Button {
                    startedAt = Date()
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .buttonStyle(BladeButtonStyle())
                .accessibilityLabel("Start a timed \(module.displayName) session")
            }

            if loggedToday >= target {
                StatChip(systemImage: "checkmark.seal.fill", text: "Target met", tint: Theme.matcha)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .dojoCardSurface()
    }

    @ViewBuilder
    private func ring(progress: Double, @ViewBuilder center: @escaping () -> some View) -> some View {
        CrestRing(progress: min(progress, 1.0),
                  gradient: AngularGradient(colors: [Theme.murasaki, Theme.ai, Theme.matcha],
                                            center: .center),
                  lineWidth: 12,
                  center: center)
            .frame(width: 168, height: 168)
    }

    // MARK: - Quick log

    @ViewBuilder
    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(title: "Quick log", tint: Theme.murasaki)
            let columns = [GridItem(.adaptive(minimum: 72), spacing: Theme.Space.s)]
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(quickPicks, id: \.self) { minutes in
                    Button {
                        log(minutes: minutes)
                    } label: {
                        VStack(spacing: 2) {
                            Text("+\(minutes)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("min")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .dojoCardSurface(cornerRadius: Theme.Radius.chip)
                    }
                    .buttonStyle(DojoPressStyle())
                    .accessibilityLabel("Log \(minutes) minutes of \(module.displayName)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
    }

    // MARK: - Streak

    @ViewBuilder
    private var streakCard: some View {
        let streak = streaks.first { $0.module == module.rawValue }
        let current = streak?.currentStreak ?? 0
        let allTime = streak?.totalMinutesAllTime ?? 0

        HStack(spacing: Theme.Space.l) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(current > 0 ? Theme.goldGradient : LinearGradient(
                    colors: [Theme.textTertiary, Theme.textTertiary],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.kin.opacity(current > 0 ? 0.14 : 0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(current) day\(current == 1 ? "" : "s")")
                    .font(Theme.numeral(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("current streak")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                StatChip(systemImage: "trophy.fill",
                         text: "best \(streak?.longestStreak ?? 0)d",
                         tint: Theme.kin)
                StatChip(systemImage: "hourglass",
                         text: formatAllTime(allTime))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(current) days, longest \(streak?.longestStreak ?? 0) days, \(allTime) minutes all time")
    }

    // MARK: - Pimsleur

    @ViewBuilder
    private var pimsleurCard: some View {
        Button {
            openPimsleur()
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.title2)
                    .foregroundStyle(Theme.ai)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Theme.ai.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Pimsleur")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Start the timer here first, then jump over.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .dojoCardSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(DojoPressStyle())
        .accessibilityLabel("Open Pimsleur app")
    }

    // MARK: - Actions

    private func log(minutes: Int) {
        _ = try? service.logMinutes(module: module, minutes: minutes)  // MARK: try? justified - best-effort; failure logged inside the called function.
        celebrationTrigger += 1
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

    private func formatAllTime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])

    let context = container.mainContext
    let log = DailyLog(date: Date())
    log.japaneseMinutes = 18
    context.insert(log)
    let streak = LearningStreak(module: LearningModule.japanese.rawValue)
    streak.currentStreak = 12
    streak.longestStreak = 21
    streak.totalMinutesAllTime = 2640
    context.insert(streak)

    return NavigationStack {
        LearningTimerView(module: .japanese, service: LearningService(modelContext: context))
    }
    .modelContainer(container)
}
