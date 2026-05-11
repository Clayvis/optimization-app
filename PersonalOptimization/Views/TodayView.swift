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
    @State private var pendingCelebration: MilestoneUnlock?
    @State private var showingMemorySheet = false

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
                    WelcomeBackCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

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

                // M4.2 followup: weekly persona question card. Shows at most
                // once per 7 days when there's still an unanswered question
                // in PersonaQuestion.library. Each answer flows into
                // UserPersona which gets injected into every Coach prompt.
                Section {
                    PersonaWeeklyQuestionCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                // M4.2 followup v2: passive behavioral inference. Watches
                // training timing, recovery-vs-workout patterns, post-skip
                // behavior, suggestion accept/dismiss rates — proposes
                // persona updates the user can accept or reject. Hidden when
                // no signal clears its sample-size threshold.
                Section {
                    PersonaSignalCard()
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
                    Section {
                        WeeklyReflectionCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    IntentionsStrip()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }

                Section {
                    Button {
                        showingMemorySheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble.fill")
                            Text("Tell the Coach what's going on")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
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
                            tappableBlock(block: block)
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
                refreshLapseAndMilestones()
            }
            .onDisappear {
                stopTicking()
                characterService.stop()
            }
            .sheet(item: $pendingCelebration) { unlock in
                MilestoneCelebrationSheet(unlock: unlock)
            }
            .sheet(isPresented: $showingMemorySheet) {
                CoachMemoryEntrySheet()
            }
        }
    }

    /// Walk lapse + milestone services on Today appearance. Cheap (mostly
    /// SwiftData reads) and gives the user immediate feedback when they
    /// cross a threshold or come back from a slump.
    private func refreshLapseAndMilestones() {
        _ = try? LapseDetectionService(modelContext: modelContext).recompute()
        let milestones = MilestoneService(modelContext: modelContext)
        _ = try? milestones.evaluate()
        if let next = milestones.nextPendingCelebration() {
            pendingCelebration = next
        }
        _ = try? AchievementService(modelContext: modelContext).evaluate()
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

    /// M4.2 followup: wraps blockRow in a NavigationLink when the block's
    /// module maps to a session view, otherwise renders the plain row. Today
    /// the user can tap a Lift A / Lift B / Basketball / Swim / cardio /
    /// learning block and land directly on the matching logging surface.
    @ViewBuilder
    private func tappableBlock(block: ScheduleBlock) -> some View {
        let module = block.module ?? ""
        if cardioModules.contains(module) {
            NavigationLink {
                cardioDestination(for: module)
            } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "lift_a" {
            NavigationLink { LiftSessionView(templateName: "Lift A") } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "lift_b" {
            NavigationLink { LiftSessionView(templateName: "Lift B") } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "basketball" {
            NavigationLink { BasketballSessionView() } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "swim" {
            NavigationLink { SwimSessionView() } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "japanese" {
            NavigationLink {
                LearningTimerView(module: .japanese, service: LearningService(modelContext: modelContext))
            } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else if module == "guitar" {
            NavigationLink {
                LearningTimerView(module: .guitar, service: LearningService(modelContext: modelContext))
            } label: {
                blockRow(block: block, isCurrent: isCurrent(block))
            }
        } else {
            blockRow(block: block, isCurrent: isCurrent(block))
        }
    }

    private let cardioModules: Set<String> = [
        "cardio", "running", "cycling", "walking", "hiit", "yoga", "hiking"
    ]

    /// Resolve a cardio module string to a CustomActivityTemplate session.
    /// Falls back to the templates list if no match (user archived the
    /// matching template). Case-insensitive lookup against template names.
    @ViewBuilder
    private func cardioDestination(for module: String) -> some View {
        let normalized = module.lowercased()
        let lookupName: String? = {
            switch normalized {
            case "running": return "Running"
            case "cycling": return "Cycling"
            case "walking": return "Walking"
            case "hiit":    return "HIIT"
            case "yoga":    return "Yoga"
            case "hiking":  return "Hiking"
            default:        return nil
            }
        }()
        let templates = (try? modelContext.fetch(FetchDescriptor<CustomActivityTemplate>())) ?? []
        if let lookupName,
           let match = templates.first(where: {
               $0.name.caseInsensitiveCompare(lookupName) == .orderedSame && !$0.archived
           }) {
            CustomActivitySessionView(template: match)
        } else {
            CustomActivitiesSettingsView()
        }
    }

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
    let schema = Schema(versionedSchema: SchemaV8.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return TodayView().modelContainer(container)
}
