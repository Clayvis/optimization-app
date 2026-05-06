import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var now: Date = Date()
    @State private var tickTimer: Timer?
    @State private var characterService = CharacterStateService.shared
    @State private var showingProtocolDetail = false

    private var service: ScheduleService {
        ScheduleService(modelContext: modelContext)
    }

    private var summaryService: DailySummaryService {
        let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz
        return DailySummaryService(modelContext: modelContext, hydrationTargets: targets)
    }

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                if let profile, profile.mascotEnabled {
                    Section {
                        CharacterView(service: characterService, size: 200)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                    }
                }

                graceBannerSection

                Section {
                    masterMetricCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

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
                characterService.start(modelContext: modelContext)
            }
            .onDisappear {
                stopTicking()
                characterService.stop()
            }
        }
    }

    @ViewBuilder
    private var graceBannerSection: some View {
        if let profile {
            if let until = profile.travelModeActiveUntil, until >= now {
                Section {
                    graceBanner(text: "Travel mode active. Streaks paused, not faked.",
                                systemImage: "airplane",
                                accent: .blue)
                }
            } else if let until = profile.sickDayActiveUntil, until >= now {
                Section {
                    graceBanner(text: "Sick day. Today is covered. Rest up.",
                                systemImage: "thermometer.medium",
                                accent: .orange)
                }
            }
        }
    }

    private func graceBanner(text: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
            Text(text)
                .font(.callout.weight(.medium))
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .accessibilityLabel(text)
    }

    private var masterMetricCard: some View {
        let tally = summaryService.todayProtocol(asOf: now)
        return Button {
            showingProtocolDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S PROTOCOL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(tally.displayText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                if tally.scheduledCount > 0 {
                    ProgressView(value: Double(tally.completedCount), total: Double(tally.scheduledCount))
                        .tint(.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tally.displayText)
        .sheet(isPresented: $showingProtocolDetail) {
            ProtocolDetailView(tally: tally)
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
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return TodayView().modelContainer(container)
}
