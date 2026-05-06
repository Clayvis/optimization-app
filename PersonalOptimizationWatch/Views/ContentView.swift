import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            ScheduleWatchView()
                .tag(0)
            HydrationWatchView()
                .tag(1)
            TrainingWatchView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

struct ScheduleWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var now: Date = Date()

    private var service: ScheduleService {
        ScheduleService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                if let current = service.currentBlock(at: now) {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(current.activity)
                                .font(.headline)
                            Text("\(current.startTime) – \(current.endTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let interval = service.timeUntilNextTransition(from: now) {
                                Text(formattedInterval(interval) + " left")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                } else if let next = service.nextBlock(after: now) {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEXT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(next.activity).font(.headline)
                            Text("\(next.startTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Today") {
                    let upcoming = remainingBlocks
                    if upcoming.isEmpty {
                        Text("Day complete.").foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { block in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.activity).font(.body)
                                Text("\(block.startTime) – \(block.endTime)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(weekdayShort)
        }
        .onAppear { now = Date() }
    }

    private var remainingBlocks: [ScheduleBlock] {
        let blocks = service.todayBlocks(for: now)
        let nowMinutes = service.minutesFromMidnight(at: now)
        return blocks.filter { block in
            guard let end = ScheduleService.parseTimeToMinutes(block.endTime) else { return false }
            return end > nowMinutes
        }
    }

    private var weekdayShort: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "EEE d"
        return formatter.string(from: now)
    }

    private func formattedInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "—"
    }
}
