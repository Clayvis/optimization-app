import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var now: Date = Date()
    @State private var tickTimer: Timer?

    private var service: ScheduleService {
        ScheduleService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Today's blocks") {
                    let blocks = service.todayBlocks(for: now)
                    if blocks.isEmpty {
                        Text("No blocks scheduled today.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(blocks) { block in
                            blockRow(block: block, isCurrent: isCurrent(block))
                        }
                    }
                }
            }
            .navigationTitle(weekdayTitle)
            .listStyle(.insetGrouped)
            .onAppear {
                now = Date()
                startTicking()
            }
            .onDisappear { stopTicking() }
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = service.currentBlock(at: now) {
                Text("NOW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(current.activity)
                    .font(.title2.weight(.semibold))
                Text("\(current.startTime) – \(current.endTime)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if let next = service.nextBlock(after: now) {
                Text("NEXT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(next.activity)
                    .font(.title2.weight(.semibold))
                Text("starts \(next.startTime)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Text("Day complete.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let interval = service.timeUntilNextTransition(from: now) {
                Text("Next transition in \(formattedInterval(interval))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Next transition in \(formattedInterval(interval))")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func blockRow(block: ScheduleBlock, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.activity)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                Text("\(block.startTime) – \(block.endTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
                    .accessibilityLabel("Current block")
            }
        }
        .padding(.vertical, 4)
    }

    private func isCurrent(_ block: ScheduleBlock) -> Bool {
        guard let current = service.currentBlock(at: now) else { return false }
        return current.id == block.id
    }

    private var weekdayTitle: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: now)
    }

    private func formattedInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "—"
    }

    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.now = Date() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}

#Preview {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return TodayView().modelContainer(container)
}
