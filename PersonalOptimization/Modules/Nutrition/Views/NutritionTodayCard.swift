import SwiftUI
import SwiftData

/// Compact Today card: protein remaining first, then calories remaining,
/// then the macro bars. One glance, no scrolling. Tapping opens the day.
@MainActor
struct NutritionTodayCard: View {
    @Query private var entries: [FoodEntry]
    @Query(sort: [SortDescriptor(\NutritionTargets.effectiveFrom, order: .reverse),
                  SortDescriptor(\NutritionTargets.createdAt, order: .reverse)])
    private var targetRows: [NutritionTargets]
    @Query private var logs: [DailyLog]
    let now: Date
    private let day: Date

    init(now: Date) {
        self.now = now
        // Device calendar, which is what UserCalendar resolves to; the same
        // choice DailyWorkoutCard makes for its query bounds.
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? now
        self.day = day
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < tomorrow })
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= day && $0.date < tomorrow && $0.supersededAt == nil })
    }

    private var summary: NutritionDaySummary {
        NutritionService.summary(date: day,
                                 entries: entries,
                                 targets: targetRows.first { $0.effectiveFrom <= day },
                                 activeEnergyKcal: logs.first?.activeEnergyBurnedKcal)
    }

    var body: some View {
        NavigationLink {
            NutritionDayView(initialDate: now)
        } label: {
            HStack(spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionEyebrow(title: "Nutrition", tint: Theme.matcha)
                    if let protein = summary.proteinRemaining, let kcal = summary.caloriesRemaining {
                        Text(NutritionFormat.remaining(protein, unit: "g protein"))
                            .font(Theme.numeral(24))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(NutritionFormat.remaining(kcal, unit: "kcal"))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    } else if summary.entryCount > 0 {
                        Text("\(NutritionFormat.kcal(summary.consumed.calories)) · \(NutritionFormat.wholeNumber(summary.consumed.protein)) g protein")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("Set targets to see what's left")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Log your first meal")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Calories and macros, written to Apple Health")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if summary.hasTargets {
                    VStack(alignment: .leading, spacing: 6) {
                        miniBar("P", progress: summary.proteinProgress, tint: Theme.matcha)
                        miniBar("C", progress: summary.carbsProgress, tint: Theme.ai)
                        miniBar("F", progress: summary.fatProgress, tint: Theme.kin)
                    }
                    .frame(width: 84)
                    .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .dojoCardSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.nutritionCard")
    }

    private func miniBar(_ label: String, progress: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 10)
            ProgressView(value: progress)
                .tint(tint)
        }
    }
}
