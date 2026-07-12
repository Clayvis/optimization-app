import SwiftUI
import SwiftData

/// Learning hub, dojo-styled. A daily-practice ring as the master metric, then
/// one card per module with live progress toward its target and the streak in
/// gold. Tap a card to open the timer.
struct LearningHubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: LearningService?
    var embedded: Bool = false

    @ViewBuilder
    var body: some View {
        if embedded {
            screen
        } else {
            NavigationStack { screen }
        }
    }

    private var screen: some View {
        content
            .navigationTitle("Learning")
            .scrollContentBackground(.hidden)
            .background(DojoBackground())
            .task { loadService() }
    }

    @ViewBuilder
    private var content: some View {
        if let service {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    DailyPracticeHero()
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionEyebrow(title: "Modules", tint: Theme.murasaki)
                        ForEach(LearningModule.allCases, id: \.rawValue) { module in
                            NavigationLink {
                                LearningTimerView(module: module, service: service)
                            } label: {
                                ModuleCard(module: module)
                            }
                            .buttonStyle(DojoPressStyle())
                        }
                    }
                }
                .padding()
            }
        } else {
            ProgressView()
        }
    }

    private func loadService() {
        if service == nil {
            service = LearningService(modelContext: modelContext)
        }
    }
}

// MARK: - Hero

/// Master metric for the tab: today's practice adherence across all modules.
/// Progress is capped per module so overshooting Japanese cannot mask a
/// skipped Guitar session.
private struct DailyPracticeHero: View {
    @Query private var logs: [DailyLog]

    var body: some View {
        let todayLog = todaysLog
        let perModule: [(module: LearningModule, minutes: Int)] = LearningModule.allCases.map {
            ($0, minutes(for: $0, in: todayLog))
        }
        let targetTotal = LearningModule.allCases.reduce(0) { $0 + $1.defaultDailyTargetMinutes }
        let cappedTotal = perModule.reduce(0) { $0 + min($1.minutes, $1.module.defaultDailyTargetMinutes) }
        let loggedTotal = perModule.reduce(0) { $0 + $1.minutes }
        let metCount = perModule.filter { $0.minutes >= $0.module.defaultDailyTargetMinutes }.count
        let progress = targetTotal > 0 ? Double(cappedTotal) / Double(targetTotal) : 0

        HStack(spacing: Theme.Space.l) {
            CrestRing(progress: progress,
                      gradient: AngularGradient(colors: [Theme.murasaki, Theme.ai, Theme.matcha],
                                                center: .center)) {
                VStack(spacing: 0) {
                    Text("\(Int((progress * 100).rounded()))")
                        .font(Theme.numeral(26))
                        .foregroundStyle(Theme.textPrimary)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(title: "Daily practice", tint: Theme.murasaki)
                Text("\(loggedTotal) min logged")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                StatChip(systemImage: "checkmark.seal.fill",
                         text: "\(metCount)/\(LearningModule.allCases.count) targets met",
                         tint: metCount == LearningModule.allCases.count ? Theme.matcha : Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily practice \(Int((progress * 100).rounded())) percent. \(loggedTotal) minutes logged, \(metCount) of \(LearningModule.allCases.count) targets met.")
    }

    private var todaysLog: DailyLog? {
        let today = Calendar.current.startOfDay(for: Date())
        return logs.first { $0.supersededAt == nil && Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
}

private func minutes(for module: LearningModule, in log: DailyLog?) -> Int {
    switch module {
    case .japanese: return log?.japaneseMinutes ?? 0
    case .guitar:   return log?.guitarMinutes ?? 0
    case .music:    return log?.musicMinutes ?? 0
    }
}

// MARK: - Module card

private struct ModuleCard: View {
    let module: LearningModule

    @Query private var logs: [DailyLog]
    @Query private var streaks: [LearningStreak]

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todayLog = logs.first { $0.supersededAt == nil && Calendar.current.isDate($0.date, inSameDayAs: today) }
        let logged = minutes(for: module, in: todayLog)
        let target = module.defaultDailyTargetMinutes
        let met = logged >= target
        let streak = streaks.first { $0.module == module.rawValue }?.currentStreak ?? 0

        HStack(spacing: Theme.Space.m) {
            Image(systemName: module.iconName)
                .font(.title2)
                .foregroundStyle(met ? Theme.matcha : Theme.murasaki)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill((met ? Theme.matcha : Theme.murasaki).opacity(0.14))
                )

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(module.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if met {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.matcha)
                    }
                    Spacer()
                    if streak > 0 {
                        StatChip(systemImage: "flame.fill", text: "\(streak)d", tint: Theme.kin)
                    }
                }
                ProgressView(value: min(Double(logged) / Double(target), 1.0))
                    .tint(met ? Theme.matcha : Theme.murasaki)
                Text("\(logged) / \(target) min today")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.displayName). \(logged) of \(target) minutes today. Streak \(streak) day\(streak == 1 ? "" : "s").")
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])

    let context = container.mainContext
    let log = DailyLog(date: Date())
    log.japaneseMinutes = 30
    log.guitarMinutes = 10
    context.insert(log)
    let streak = LearningStreak(module: LearningModule.japanese.rawValue)
    streak.currentStreak = 12
    streak.longestStreak = 21
    streak.totalMinutesAllTime = 2640
    context.insert(streak)

    return LearningHubView().modelContainer(container)
}
