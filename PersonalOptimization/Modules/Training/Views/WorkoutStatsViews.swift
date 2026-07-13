import SwiftUI
import HealthKit

/// Shared session-screen building blocks: the live Apple Health metrics
/// section shown during an active workout, and the last-session recap row
/// shown on the pre-start screens.

/// Form section surfacing what HealthKit has accumulated since the session
/// started: active energy, activity-appropriate distance, latest heart rate.
/// Hidden entirely until at least one metric has data, so phone-only
/// sessions without a watch never show a wall of dashes.
struct LiveWorkoutStatsSection: View {
    let metrics: LiveWorkoutMetrics

    var body: some View {
        if metrics.hasAnyData {
            Section {
                if let kcal = metrics.activeKcal {
                    statRow(icon: "flame.fill", tint: .orange,
                            label: "Active energy",
                            value: "\(Int(kcal.rounded())) kcal")
                }
                if let meters = metrics.distanceMeters, meters > 0 {
                    statRow(icon: "point.topleft.down.curvedto.point.bottomright.up.fill", tint: .green,
                            label: "Distance",
                            value: WorkoutMetrics.milesText(meters: meters))
                }
                if let bpm = metrics.heartRateBPM {
                    statRow(icon: "heart.fill", tint: .red,
                            label: "Heart rate",
                            value: "\(Int(bpm.rounded())) bpm")
                }
            } header: {
                Text("Apple Health")
            } footer: {
                if let updated = metrics.lastUpdatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened)). Watch workouts feed richer data.")
                }
            }
        }
    }

    private func statRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.multicolor)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// "Last session" line for the pre-start screens, fed by the most recent
/// HealthKit workout of the given activity types. Quietly absent when
/// HealthKit has nothing. Takes a value set, not a match closure: closures
/// over HKWorkout sequences tripped Swift 6 region analysis in Release WMO.
struct LastWorkoutRecapRow: View {
    let activityTypes: Set<HKWorkoutActivityType>

    @State private var recap: WorkoutRecap?

    var body: some View {
        Group {
            if let recap, let line = recap.line {
                HStack {
                    Label("Last session", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(line)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(recap.endDate.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Last session \(line), \(recap.endDate.formatted(.relative(presentation: .named)))")
            }
        }
        .task { await load() }
    }

    private func load() async {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        // MARK: try? justified - recap is decorative; unauthorized/no-data hides the row.
        guard let workouts = try? await LiveHealthKitService.shared.fetchWorkouts(
            in: DateInterval(start: start, end: now)
        ) else { return }
        for workout in workouts where activityTypes.contains(workout.workoutActivityType) {
            recap = WorkoutRecap.from(workout: workout)
            break
        }
    }
}
