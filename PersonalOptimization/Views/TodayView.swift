import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var now: Date = Date()
    @State private var tickTimer: Timer?
    @State private var characterService = CharacterStateService.shared
    @State private var showingProtocolDetail = false
    @State private var quoteService = DailyQuoteService()
    @State private var dailyQuote: DailyQuote?

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

                if let quote = dailyQuote {
                    Section {
                        Text(quote.displayText)
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                            .accessibilityLabel(quote.displayText)
                    }
                }

                Section {
                    masterMetricCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    streakStrip
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    DailyProgressBars()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    PrescribedWorkoutCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                if isSunday {
                    Section {
                        WeeklyProgramCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    ScheduleSuggestionInbox()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    CoachInsightCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
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
                        Text("Open day. You write the plan.")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No blocks scheduled today")
                    } else {
                        ForEach(blocks) { block in
                            blockRow(block: block, isCurrent: isCurrent(block))
                        }
                    }
                }
            }
            .navigationTitle(weekdayTitle)
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ScheduleEditorView()
                    } label: {
                        Label("Edit schedule", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityLabel("Edit schedule")
                }
            }
            .onAppear {
                now = Date()
                startTicking()
                characterService.start(modelContext: modelContext)
                Task { await loadDailyQuote() }
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
                    graceBanner(text: IdentityCopy.travelBanner,
                                systemImage: "airplane",
                                accent: .blue)
                }
            } else if let until = profile.sickDayActiveUntil, until >= now {
                Section {
                    graceBanner(text: IdentityCopy.sickBanner,
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

    /// Labeled streak card. Identity-framed. Day-count framing makes the chips
    /// read clearly as streaks rather than ambiguous counters. Flame glyph on
    /// chips with active streaks; muted otherwise so non-streaks don't shout.
    @ViewBuilder
    private var streakStrip: some View {
        let counters = (try? modelContext.fetch(FetchDescriptor<StreakCounter>())) ?? []
        let workout = counters.first { $0.domain == StreakDomain.workout.rawValue }?.currentStreak ?? 0
        let hydration = counters.first { $0.domain == StreakDomain.hydration.rawValue }?.currentStreak ?? 0
        let learning = counters.first { $0.domain == StreakDomain.learning.rawValue }?.currentStreak ?? 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("STREAKS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                streakChip(label: "Workout", days: workout, systemImage: "figure.strengthtraining.traditional")
                streakChip(label: "Hydration", days: hydration, systemImage: "drop.fill")
                streakChip(label: "Learning", days: learning, systemImage: "book.fill")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func streakChip(label: String, days: Int, systemImage: String) -> some View {
        let dayLabel = days == 1 ? "day streak" : "day streak"
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                if days > 0 {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("d")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(label) \(days) \(dayLabel)")
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

    private var isSunday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let raw = cal.component(.weekday, from: now)
        let iso = raw == 1 ? 7 : raw - 1
        return iso == 7
    }

    private func loadDailyQuote() async {
        guard let profile else {
            dailyQuote = quoteService.curatedQuote(style: "balanced")
            return
        }
        dailyQuote = await quoteService.dailyQuote(
            style: profile.motivationStyle,
            customStylePrompt: profile.customStylePrompt,
            aiEnabled: profile.aiQuotesEnabled
        )
    }
}

#Preview {
    let schema = Schema(versionedSchema: SchemaV5.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return TodayView().modelContainer(container)
}
