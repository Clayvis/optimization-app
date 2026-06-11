import SwiftUI
import SwiftData

/// Apple-Activity-style daily progress in a compact stacked-bars layout.
/// Reads three signals from today's `DailyLog` plus the hydration target out
/// of `ScheduleConfigLoader`. Falls back gracefully when data is missing —
/// each bar's denominator is conservative so an empty store renders 0/N
/// rather than crashing.
@MainActor
struct DailyProgressBars: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var logs: [DailyLog]
    @Query private var liftSessions: [LiftSession]
    @Query private var basketballSessions: [BasketballSession]
    @Query private var swimSessions: [SwimSession]
    @Query private var customSessions: [CustomActivitySession]

    @State private var hydrationTargetMin: Double = 64
    /// Last seen milestone bucket per bar (0 none, 1 quarter, 2 half,
    /// 3 almost, 4 done). A bucket increase fires one haptic, so crossing
    /// halfway feels like something without any fake celebration.
    @State private var milestoneBuckets: [String: Int] = [:]
    @State private var milestoneCelebration = 0
    /// Readiness-adjusted Move goal multiplier (Gap 3: a low-readiness day gets a
    /// reduced "restore" goal, a normal day keeps the full "stretch" goal). 1.0
    /// until RecoveryGate resolves in `.task`.
    @State private var moveGoalMultiplier: Double = 1.0
    @State private var moveGoalNote: String?

    private var todayLog: DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: Date())
        return logs.first(where: { $0.supersededAt == nil && cal.isDate($0.date, inSameDayAs: day) })
    }

    private var hydrationOz: Double {
        todayLog?.waterOz ?? 0
    }

    private var learningMinutes: Int {
        ProtocolRules.learningMinutes(log: todayLog)
    }

    /// Active calories shown on the Move track. Prefers HealthKit's measured
    /// active energy (the Apple Watch / Fitness "Move" number, which already
    /// counts workouts the watch tracked even when nothing was logged in-app),
    /// and never undercounts an in-app session HealthKit hasn't picked up yet.
    private var caloriesBurned: Double {
        max(todayLog?.activeEnergyBurnedKcal ?? 0, sessionCaloriesEstimate)
    }

    /// Fallback estimate from in-app logged sessions, used when HealthKit has no
    /// active-energy data (no watch / not authorized): lift volume → kcal at
    /// ~0.04 kcal/lb-rep, basketball/swim/custom → minutes × intensity factor.
    private var sessionCaloriesEstimate: Double {
        var total: Double = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: Date())

        // Lift: rough estimate from volume × 0.04 kcal/lb (compound lifts).
        for s in liftSessions where cal.isDate(s.date, inSameDayAs: day) {
            total += s.totalVolumeLbs * 0.04
        }
        // Basketball: ~9 kcal/min for moderate-vigorous play.
        for s in basketballSessions where cal.isDate(s.date, inSameDayAs: day) {
            let mins = max(0, s.endTime.timeIntervalSince(s.startTime) / 60)
            total += mins * 9
        }
        // Swim: ~10 kcal/min freestyle moderate.
        for s in swimSessions where cal.isDate(s.date, inSameDayAs: day) {
            total += Double(s.durationMinutes) * 10
        }
        // Custom: kcal field if user entered it, else 6 kcal/min default.
        for s in customSessions where cal.isDate(s.date, inSameDayAs: day) {
            if let kcal = s.caloriesKcal {
                total += kcal
            } else {
                total += Double(s.durationMinutes) * 6
            }
        }
        return total
    }

    private var calorieGoal: Double {
        // Base 500 kcal (Apple Watch "Move" default), scaled by today's readiness
        // so a low-recovery day becomes a winnable restore goal instead of an
        // unreachable stretch goal. Rounded to the nearest 10.
        (500 * moveGoalMultiplier / 10).rounded() * 10
    }

    private var hydrationProgress: Double {
        guard hydrationTargetMin > 0 else { return 0 }
        return min(1, hydrationOz / hydrationTargetMin)
    }

    private var learningProgress: Double {
        // 30 min default learning target for the day; matches StreakService's
        // hydration/learning thresholds for a "day complete" verdict.
        let target: Double = 30
        return min(1, Double(learningMinutes) / target)
    }

    private var caloriesProgress: Double {
        min(1, caloriesBurned / calorieGoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.tint)
                Text("TODAY'S PROGRESS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            progressRow(
                label: "Move",
                detail: "\(Int(caloriesBurned)) / \(Int(calorieGoal)) kcal",
                progress: caloriesProgress,
                tint: Theme.kurenai,
                systemImage: "flame.fill"
            )

            progressRow(
                label: "Hydration",
                detail: "\(Int(hydrationOz)) / \(Int(hydrationTargetMin)) oz",
                progress: hydrationProgress,
                tint: Theme.ai,
                systemImage: "drop.fill"
            )

            progressRow(
                label: "Learning",
                detail: "\(learningMinutes) / 30 min",
                progress: learningProgress,
                tint: Theme.matcha,
                systemImage: "book.fill"
            )

            if let moveGoalNote {
                Text(moveGoalNote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .task {
            await loadHydrationTarget()
            loadReadiness()
            // Baseline the buckets silently so opening the screen never
            // haptics for progress already made.
            for (label, progress) in currentProgress() {
                milestoneBuckets[label] = Self.milestoneBucket(progress)
            }
        }
        .onChange(of: caloriesProgress) { trackMilestone(label: "Move", progress: caloriesProgress) }
        .onChange(of: hydrationProgress) { trackMilestone(label: "Hydration", progress: hydrationProgress) }
        .onChange(of: learningProgress) { trackMilestone(label: "Learning", progress: learningProgress) }
        .sensoryFeedback(.increase, trigger: milestoneCelebration)
    }

    private func currentProgress() -> [(String, Double)] {
        [("Move", caloriesProgress), ("Hydration", hydrationProgress), ("Learning", learningProgress)]
    }

    /// 0 none, 1 quarter, 2 half, 3 almost (75 percent), 4 done.
    private static func milestoneBucket(_ progress: Double) -> Int {
        if progress >= 1.0 { return 4 }
        if progress >= 0.75 { return 3 }
        if progress >= 0.5 { return 2 }
        if progress >= 0.25 { return 1 }
        return 0
    }

    private func trackMilestone(label: String, progress: Double) {
        let bucket = Self.milestoneBucket(progress)
        let previous = milestoneBuckets[label] ?? 0
        milestoneBuckets[label] = bucket
        if bucket > previous {
            milestoneCelebration += 1
        }
    }

    /// Scales the Move goal by today's readiness (Gap 3: the score adjusts the
    /// goal target, not just suggests). High readiness keeps the stretch goal;
    /// low readiness drops it to a winnable restore goal.
    private func loadReadiness() {
        guard let profile = profiles.first else { return }
        let detail = RecoveryGate(modelContext: modelContext).evaluateDetailed(profile: profile)
        // No same-day readiness signal (HRV / RHR / sleep / achilles): keep the
        // full stretch goal. Never assert a verdict from a purely historical
        // baseline, which would ease the goal on a day with nothing logged.
        guard detail.hasData else {
            moveGoalMultiplier = 1.0
            moveGoalNote = nil
            return
        }
        switch detail.recommendation {
        case .normal:
            moveGoalMultiplier = 1.0
            moveGoalNote = nil
        case .downgrade:
            moveGoalMultiplier = 0.7
            moveGoalNote = "Readiness low: Move goal eased to \(Int(calorieGoal)) kcal."
        case .rest:
            moveGoalMultiplier = 0.5
            moveGoalNote = "Rest day: Move goal set to a light \(Int(calorieGoal)) kcal."
        }
    }

    @ViewBuilder
    private func progressRow(label: String,
                             detail: String,
                             progress: Double,
                             tint: Color,
                             systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline.weight(.medium))
                // Goal-gradient cue: name the milestone the user just passed
                // so motivation rises through the middle and final stretch,
                // without distorting the accurate fill.
                if progress >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                } else if progress >= 0.75 {
                    Text("almost")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                } else if progress >= 0.5 {
                    Text("halfway")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint.opacity(0.8))
                        .accessibilityHidden(true)
                }
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Apple-Activity-style fully rounded thick progress bar with faint
            // quarter ticks, so the milestones read on the bar itself.
            // GeometryReader keeps the fill width pixel-correct and the 100%
            // case lights up.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(0, geo.size.width * progress))
                    ForEach([0.25, 0.5, 0.75], id: \.self) { tick in
                        Rectangle()
                            .fill(Theme.inkVoid.opacity(0.3))
                            .frame(width: 1.5)
                            .offset(x: geo.size.width * tick)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .accessibilityLabel("\(label) \(detail), \(Int(progress * 100)) percent")
        }
    }

    private func loadHydrationTarget() async {
        // Best-effort: pull the day's minimum from ScheduleConfigLoader. On
        // failure leave the 64oz default in place rather than show a broken bar.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        // try? justified - bundled resource; nil falls back to the shared 64oz floor.
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
        hydrationTargetMin = ProtocolRules.hydrationTargetMin(for: Date(), targets: targets, calendar: cal)
    }
}
