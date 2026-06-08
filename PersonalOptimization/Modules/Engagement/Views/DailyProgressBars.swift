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
    @Query private var workoutEvents: [WorkoutEvent]
    @Query private var liftSessions: [LiftSession]
    @Query private var basketballSessions: [BasketballSession]
    @Query private var swimSessions: [SwimSession]
    @Query private var customSessions: [CustomActivitySession]

    @State private var hydrationTargetMin: Double = 64
    /// Readiness-adjusted Move goal multiplier (Gap 3: a low-readiness day gets a
    /// reduced "restore" goal, a normal day keeps the full "stretch" goal). 1.0
    /// until RecoveryGate resolves in `.task`.
    @State private var moveGoalMultiplier: Double = 1.0
    @State private var moveGoalNote: String?

    private var todayLog: DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: Date())
        return logs.first(where: { cal.isDate($0.date, inSameDayAs: day) })
    }

    private var hydrationOz: Double {
        todayLog?.waterOz ?? 0
    }

    private var learningMinutes: Int {
        guard let log = todayLog else { return 0 }
        return log.japaneseMinutes + log.guitarMinutes + log.courseworkMinutes + log.musicMinutes
    }

    /// Active calories burned today. We don't yet ingest the live HK quantity
    /// (M3.7 scope). Use a deterministic estimate: lift volume → kcal at
    /// ~0.04 kcal/lb-rep, basketball/swim/custom → minutes × intensity factor.
    /// Surfacing this as motivating progress is more important than precision.
    private var caloriesBurned: Double {
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
                tint: .red,
                systemImage: "flame.fill"
            )

            progressRow(
                label: "Hydration",
                detail: "\(Int(hydrationOz)) / \(Int(hydrationTargetMin)) oz",
                progress: hydrationProgress,
                tint: .blue,
                systemImage: "drop.fill"
            )

            progressRow(
                label: "Learning",
                detail: "\(learningMinutes) / 30 min",
                progress: learningProgress,
                tint: .green,
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await loadHydrationTarget()
            loadReadiness()
        }
    }

    /// Scales the Move goal by today's readiness (Gap 3: the score adjusts the
    /// goal target, not just suggests). High readiness keeps the stretch goal;
    /// low readiness drops it to a winnable restore goal.
    private func loadReadiness() {
        guard let profile = profiles.first else { return }
        let detail = RecoveryGate(modelContext: modelContext).evaluateDetailed(profile: profile)
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
                // Goal-gradient cue: emphasize the final stretch so motivation
                // rises near the finish, without distorting the accurate fill.
                if progress >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                } else if progress >= 0.8 {
                    Text("almost")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Apple-Activity-style fully rounded thick progress bar. GeometryReader
            // keeps the fill width pixel-correct and the 100% case lights up.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 10)
            .accessibilityLabel("\(label) \(detail), \(Int(progress * 100)) percent")
        }
    }

    private func loadHydrationTarget() async {
        // Best-effort: pull the day's minimum from ScheduleConfigLoader. On
        // failure leave the 64oz default in place rather than show a broken bar.
        do {
            let config = try ScheduleConfigLoader.loadCached()
            let weekday = isoWeekday(for: Date())
            let targets = config.hydrationTargetsOz
            if targets.basketball.appliesTo.contains(weekday) {
                hydrationTargetMin = targets.basketball.min
            } else if targets.swim.appliesTo.contains(weekday) {
                hydrationTargetMin = targets.swim.min
            } else if targets.lift.appliesTo.contains(weekday) {
                hydrationTargetMin = targets.lift.min
            } else {
                hydrationTargetMin = targets.rest.min
            }
        } catch {
            hydrationTargetMin = 64
        }
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }
}
