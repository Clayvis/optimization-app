import SwiftUI
import SwiftData
import WatchKit

/// Watch idle "home" — mascot front and center, master metric below, plus a
/// one-tap row for the highest-frequency logs (water, end fast). Designed to
/// feel like a glance: open, see your day, log one thing, drop the wrist.
///
/// Battery posture: no Timer.scheduledTimer. The clock-driven elements
/// (fasting elapsed, "now" header) live inside a TimelineView with a 60s
/// cadence — Apple's WidgetKit/Watch policy honors this without burning the
/// chip. Heavy queries (hydration target lookup) run once on appear, not on
/// the ticker.
@MainActor
struct IdleHomeWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var logs: [DailyLog]
    @Query(sort: [SortDescriptor(\StreakCounter.domain, order: .forward)])
    private var streaks: [StreakCounter]

    @State private var mascotState: CharacterState = .neutral
    @State private var mascotReason: String = ""
    @State private var hydrationService: HydrationService?
    @State private var fastingService: FastingService?
    @State private var refreshTrigger = 0

    private var profile: UserProfile? { profiles.first }
    private var variant: String { profile?.mascotVariant ?? "ninja_male" }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                mascotBlock
                masterMetricBlock
                fastingBlock
                quickLogRow
                streakRow
            }
            .padding(.horizontal, 4)
            .id(refreshTrigger)
        }
        .task { await loadServices() }
        .onAppear { recomputeMascot() }
    }

    // MARK: - Blocks

    @ViewBuilder
    private var mascotBlock: some View {
        VStack(spacing: 2) {
            Image(mascotState.assetName(for: variant))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 72)
                .accessibilityLabel(mascotState.rawValue.capitalized)
            if !isInternalReason(mascotReason) {
                Text(mascotReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private var masterMetricBlock: some View {
        let tally = todayTally()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(tally.completed)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("of \(tally.scheduled)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            Text("TODAY'S PROTOCOL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if tally.scheduled > 0 {
                ProgressView(value: Double(tally.completed), total: Double(tally.scheduled))
                    .tint(.green)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var fastingBlock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            if let svc = fastingService, let p = profile {
                let state = svc.state(at: now, profile: p)
                let elapsed = svc.elapsedFasting(at: now, profile: p)
                let remaining = svc.remainingInFast(at: now, profile: p)
                HStack {
                    Image(systemName: state == .fasting ? "timer" : "fork.knife")
                        .foregroundStyle(state == .fasting ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state == .fasting ? "Fasting" : "Eating")
                            .font(.caption.weight(.semibold))
                        Text(state == .fasting
                             ? (remaining.map { "\(formatHM($0)) left" } ?? "open")
                             : "open")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state == .fasting {
                        Text(formatHM(elapsed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var quickLogRow: some View {
        HStack(spacing: 8) {
            Button {
                quickLogWater(oz: 16)
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue)
                    Text("+16 oz").font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .accessibilityLabel("Log 16 ounces of water")

            Button {
                endFastIfActive()
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
                    Text("End fast").font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("End current fast")
            .disabled(!fastIsActive)
        }
    }

    @ViewBuilder
    private var streakRow: some View {
        let workout = streakValue(.workout)
        let hydration = streakValue(.hydration)
        let learning = streakValue(.learning)
        HStack(spacing: 6) {
            streakChip(systemImage: "figure.strengthtraining.traditional", days: workout)
            streakChip(systemImage: "drop.fill", days: hydration)
            streakChip(systemImage: "book.fill", days: learning)
        }
        .padding(.top, 2)
    }

    private func streakChip(systemImage: String, days: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            if days > 0 {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
            }
            Text("\(days)d")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.18))
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func quickLogWater(oz: Double) {
        guard let svc = hydrationService else { return }
        _ = try? svc.logBottle(oz: oz)
        WKInterfaceDevice.current().play(.success)
        refreshTrigger += 1
    }

    private func endFastIfActive() {
        guard let svc = fastingService else { return }
        _ = try? svc.endManualFast()
        WKInterfaceDevice.current().play(.success)
        refreshTrigger += 1
    }

    private var fastIsActive: Bool {
        guard let svc = fastingService, let p = profile else { return false }
        return svc.state(at: Date(), profile: p) == .fasting
    }

    // MARK: - Computation

    /// Lightweight tally without DailySummaryService (which lives in iOS-only
    /// engagement module). Mirrors the logic at glance fidelity: count of
    /// (fasting done, hydration target met, learning ≥30min, workout logged).
    private func todayTally() -> (completed: Int, scheduled: Int) {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: Date())
        let log = logs.first { cal.isDate($0.date, inSameDayAs: day) }
        var completed = 0
        let scheduled = 4

        if log?.fastEnd != nil { completed += 1 }

        let hydrationTarget = profile?.bottleSizeOz ?? 64
        if (log?.waterOz ?? 0) >= hydrationTarget { completed += 1 }

        if (log?.japaneseMinutes ?? 0) + (log?.guitarMinutes ?? 0) >= 30 { completed += 1 }

        let workoutCounter = streaks.first { $0.domain == StreakDomain.workout.rawValue }
        if (workoutCounter?.lastCompletedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) {
            completed += 1
        }
        return (completed, scheduled)
    }

    private func streakValue(_ domain: StreakDomain) -> Int {
        streaks.first { $0.domain == domain.rawValue }?.currentStreak ?? 0
    }

    /// Mascot recompute on appear only; we don't run a 30s ticker on the watch
    /// like CharacterStateService does on iOS — that would burn battery for no
    /// real-time benefit. The state on the wrist refreshes when the user
    /// opens the app or the iOS app pushes via WCSession (M3.8 Block 3).
    private func recomputeMascot() {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: Date())
        let log = logs.first { cal.isDate($0.date, inSameDayAs: day) }

        let workoutCounter = streaks.first { $0.domain == StreakDomain.workout.rawValue }
        let workoutMilestone = isMilestone(workoutCounter?.currentStreak)
            && (workoutCounter?.lastCompletedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        let anyBroken = streaks.contains { c in
            guard let last = c.lastCompletedDate else { return false }
            let yesterday = cal.date(byAdding: .day, value: -1, to: day) ?? day
            return c.currentStreak == 0 && cal.isDate(last, inSameDayAs: yesterday)
        }

        // Fast window check (manual or scheduled).
        let inFast: Bool
        if let svc = fastingService, let p = profile {
            inFast = svc.state(at: Date(), profile: p) == .fasting
        } else {
            inFast = false
        }

        // Order matches CharacterState.precedenceOrder (urgent/achievement/
        // proud/disappointed/tired/thirsty/fasting/neutral) — but on the
        // wrist we skip urgent (no schedule lookup here) and stay on the
        // most likely visible states.
        if workoutMilestone {
            mascotState = .proud
            mascotReason = "milestone today"
        } else if anyBroken {
            mascotState = .disappointed
            mascotReason = "streak broke"
        } else if let log, let sleep = log.sleepHours, sleep < 6 {
            mascotState = .tired
            mascotReason = "low sleep"
        } else if inFast {
            mascotState = .fasting
            mascotReason = "in fast window"
        } else {
            mascotState = .neutral
            mascotReason = ""
        }
    }

    private func isMilestone(_ s: Int?) -> Bool {
        guard let s else { return false }
        return s == 7 || s == 30 || s == 100
    }

    private func isInternalReason(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "default"
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private func formatHM(_ s: TimeInterval) -> String {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private func loadServices() async {
        do {
            let config = try ScheduleConfigLoader.load()
            hydrationService = HydrationService(modelContext: modelContext, targets: config.hydrationTargetsOz)
            fastingService = FastingService(modelContext: modelContext, defaults: config.fastingDefaults)
        } catch {
            // Stay quiet on the watch — surface bad config in iOS Diagnostics, not on the wrist.
        }
        recomputeMascot()
    }
}
