import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var now: Date = Date()
    @State private var characterService = CharacterStateService.shared
    @State private var logFeedback = LogFeedbackCenter.shared
    @State private var hkSyncService: HealthKitSyncService?
    @State private var showingProtocolDetail = false
    @State private var quoteService = DailyQuoteService()
    @State private var dailyQuote: DailyQuote?
    @State private var pendingCelebration: MilestoneUnlock?
    @State private var showingMemorySheet = false

    // V11 launch-polish (Item 6): services held in @State so they survive
    // body evaluations. Pre-refactor these were computed every render
    // (ScheduleService init does a SwiftData FetchDescriptor walk;
    // DailySummaryService reads bundled hydration targets). The cost
    // multiplied across every TabView re-emission produced the "wonky" feel
    // on daily launch. Lazy-bootstrap via .task; refresh on demand via
    // bootstrapServices(reset: true).
    @State private var scheduleService: ScheduleService?
    @State private var summaryService: DailySummaryService?

    private var profile: UserProfile? { profiles.first }

    /// Pre-bootstrap callers fall back to a transient instance so the view
    /// can render before the .task has run. Once bootstrap completes the
    /// @State copies take over and subsequent renders are free.
    private var service: ScheduleService {
        scheduleService ?? ScheduleService(modelContext: modelContext)
    }

    private var dailySummary: DailySummaryService {
        if let summaryService { return summaryService }
        // MARK: - try? justified because: ScheduleConfig is a bundled
        // resource; falling back to nil targets keeps DailySummaryService
        // working with its default hydration floor.
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz  // MARK: try? justified - best-effort decode/fetch; nil result is acceptable.
        return DailySummaryService(modelContext: modelContext, hydrationTargets: targets)
    }

    var body: some View {
        NavigationStack {
            List {
                if let svc = hkSyncService, svc.isSyncing {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Catching up with Apple Health…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    }
                }

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
                    NextBlockCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
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
                    RecoveryCard()
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
                bootstrapServices()
                characterService.start(modelContext: modelContext)
                Task { await loadDailyQuote() }
                refreshLapseAndMilestones()
            }
            .onDisappear {
                characterService.stop()
            }
            // Pull to refresh runs a full HK sync and re-derives downstream
            // state. The spinner above shows for the duration of the sync
            // via the @Observable isSyncing flag.
            .refreshable {
                guard let svc = hkSyncService else { return }
                await svc.syncToday()
                NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
            }
            // V11 launch-polish: build services once per view appearance.
            // Subsequent body evaluations read the @State copies instead of
            // re-allocating per-render.
            .task(id: "todayview.bootstrap") {
                bootstrapServices()
            }
            // SwiftUI-native ticker. The OS pauses the task when the view
            // leaves the screen and resumes it when it returns; no manual
            // Timer lifecycle to manage and no battery cost while idle.
            .task(id: "todayview.tick") {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))  // MARK: try? justified - best-effort; failure logged inside the called function.
                    now = Date()
                }
            }
            .sheet(item: $pendingCelebration) { unlock in
                MilestoneCelebrationSheet(unlock: unlock)
            }
            .sheet(isPresented: $showingMemorySheet) {
                CoachMemoryEntrySheet()
            }
        }
    }

    /// V11 launch-polish (Item 6). Lazily allocates the ScheduleService /
    /// DailySummaryService / HealthKitSyncService instances on first view
    /// appearance. Idempotent: subsequent calls without `reset: true` are
    /// no-ops. Callers that mutate the schedule (template re-apply, AI
    /// generation accept) should call `bootstrapServices(reset: true)`
    /// after the mutation so the cached service picks up the new rows.
    private func bootstrapServices(reset: Bool = false) {
        if reset {
            scheduleService = nil
            summaryService = nil
            hkSyncService = nil
        }
        if scheduleService == nil {
            scheduleService = ScheduleService(modelContext: modelContext)
        }
        if summaryService == nil {
            // MARK: - try? justified because: ScheduleConfig is a bundled
            // resource; falling back to nil targets keeps DailySummaryService
            // working with its default hydration floor.
            let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz  // MARK: try? justified - best-effort decode/fetch; nil result is acceptable.
            summaryService = DailySummaryService(modelContext: modelContext, hydrationTargets: targets)
        }
        if hkSyncService == nil {
            hkSyncService = HealthKitSyncService(modelContext: modelContext)
        }
    }

    /// Walk lapse + milestone services on Today appearance. Cheap (mostly
    /// SwiftData reads) and gives the user immediate feedback when they
    /// cross a threshold or come back from a slump.
    private func refreshLapseAndMilestones() {
        _ = try? LapseDetectionService(modelContext: modelContext).recompute()  // MARK: try? justified - best-effort; failure logged inside the called function.
        let milestones = MilestoneService(modelContext: modelContext)
        _ = try? milestones.evaluate()  // MARK: try? justified - best-effort; failure logged inside the called function.
        if let next = milestones.nextPendingCelebration() {
            pendingCelebration = next
        }
        _ = try? AchievementService(modelContext: modelContext).evaluate()  // MARK: try? justified - best-effort; failure logged inside the called function.
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
        // Rederive the instant a log is confirmed (LogFeedbackCenter bumps its
        // token on every confirm), not only on the 60-second tick.
        _ = logFeedback.token
        let tally = dailySummary.todayProtocol(asOf: now)
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
        // Rederive when a log is confirmed so the chips reflect the freshly
        // recomputed StreakCounter rows (ReactiveRecomputeService runs on the
        // same .userStateChanged signal).
        let _ = logFeedback.token
        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let workout = counters.first { $0.domain == StreakDomain.workout.rawValue }?.currentStreak ?? 0
        let hydration = counters.first { $0.domain == StreakDomain.hydration.rawValue }?.currentStreak ?? 0
        let learning = counters.first { $0.domain == StreakDomain.learning.rawValue }?.currentStreak ?? 0
        let master = counters.first { $0.domain == StreakDomain.protocolAdherence.rawValue }
        let masterStreak = master?.currentStreak ?? 0
        let masterFreezes = master?.freezesAvailable ?? 0
        let todayProtected = master?.lastCompletedDate.map { Calendar.current.isDateInToday($0) } ?? false
        // Design Principle 2 (streaks need mercy, made visible): smallest freeze
        // balance across the shown domains so the count never over-promises.
        let freezesLeft = [
            counters.first { $0.domain == StreakDomain.workout.rawValue }?.freezesAvailable,
            counters.first { $0.domain == StreakDomain.hydration.rawValue }?.freezesAvailable,
            counters.first { $0.domain == StreakDomain.learning.rawValue }?.freezesAvailable
        ].compactMap { $0 }.min()

        // Gap 1 durability handoff: past the bootstrap window the headline shifts
        // from the raw streak count to an identity + trend narrative, and the
        // streak is demoted so the user is not solely streak-dependent.
        let durability = DurabilityHeadlineService(modelContext: modelContext).headline(asOf: now)

        VStack(alignment: .leading, spacing: 10) {
            // Design Principle 6 (one master metric): one headline, per-domain
            // chips beneath. Bootstrap weeks lead with the streak number; once
            // established, identity leads and the streak demotes to a chip.
            if durability.phase == .established {
                VStack(alignment: .leading, spacing: 4) {
                    Text(durability.identityLine)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let trend = durability.trendLine {
                        Text(trend)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(masterStreak > 0 ? .orange : .secondary)
                            .accessibilityHidden(true)
                        Text("\(masterStreak)-day protocol streak")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(masterStreak) day protocol streak")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(masterStreak > 0 ? .orange : .secondary)
                        .accessibilityHidden(true)
                    Text("\(masterStreak)")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("day protocol streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(masterStreak) day protocol streak")
            }
            HStack(spacing: 8) {
                streakChip(label: "Workout", days: workout, systemImage: "figure.strengthtraining.traditional")
                streakChip(label: "Hydration", days: hydration, systemImage: "drop.fill")
                streakChip(label: "Learning", days: learning, systemImage: "book.fill")
            }
            if masterStreak > 0 && masterFreezes > 0 && !todayProtected {
                Button {
                    protectProtocolStreak()
                } label: {
                    Label("Protect today · \(masterFreezes) freeze\(masterFreezes == 1 ? "" : "s") left",
                          systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Spends one streak freeze to keep today's protocol streak alive without faking a log.")
            } else if let freezesLeft, freezesLeft > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(IdentityCopy.streakFreezeAvailable(count: freezesLeft))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Spends one freeze on the master protocol streak to keep today alive
    /// (design principle 2: mercy, never fake completion). applyFreeze records
    /// an honest FreezeApplication; confirm() then refreshes the mascot,
    /// counters, and this strip via .userStateChanged.
    private func protectProtocolStreak() {
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz  // MARK: try? justified - best-effort decode; nil falls back to the default hydration floor.
        let streaks = StreakService(modelContext: modelContext, hydrationTargets: targets)
        if (try? streaks.applyFreeze(domain: .protocolAdherence)) != nil {  // MARK: try? justified - gated by the button; only throws noFreezesAvailable, logged inside the service.
            LogFeedbackCenter.shared.confirm(IdentityCopy.streakProtected)
        }
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
        let templates = modelContext.fetchOrEmpty(FetchDescriptor<CustomActivityTemplate>())
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
        formatter.timeZone = TimeZone.current
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

    private var isSunday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
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
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)  // MARK: try? justified - best-effort; failure logged inside the called function.
    return TodayView().modelContainer(container)
}
