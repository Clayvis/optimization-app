import SwiftUI
import SwiftData

struct LearningHubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: LearningService?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Learning")
        }
        .task { loadService() }
    }

    @ViewBuilder
    private var content: some View {
        if let service {
            List {
                ForEach(LearningModule.allCases, id: \.rawValue) { module in
                    NavigationLink {
                        LearningTimerView(module: module, service: service)
                    } label: {
                        ModuleCard(module: module, service: service)
                    }
                }
            }
        } else {
            ProgressView()
        }
    }

    private func loadService() {
        service = LearningService(modelContext: modelContext)
    }
}

private struct ModuleCard: View {
    let module: LearningModule
    let service: LearningService

    @Query private var logs: [DailyLog]
    @Query private var streaks: [LearningStreak]

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todayLog = logs.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let minutes = module == .japanese ? (todayLog?.japaneseMinutes ?? 0) : (todayLog?.guitarMinutes ?? 0)
        let streak = streaks.first { $0.module == module.rawValue }?.currentStreak ?? 0
        let target = module.defaultDailyTargetMinutes

        HStack(spacing: 12) {
            Image(systemName: module == .japanese ? "character.book.closed" : "guitars")
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(module.displayName).font(.body.weight(.semibold))
                Text("\(minutes) / \(target) min today")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Streak \(streak) day\(streak == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tint)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
