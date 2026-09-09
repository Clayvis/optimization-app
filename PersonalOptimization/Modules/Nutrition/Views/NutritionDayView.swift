import SwiftUI
import SwiftData
import HealthKit

/// The nutrition day: what's left first, then each meal with its entries and
/// an inline add. Pushed from the Today card and the Dojo tile, so it does not
/// own a NavigationStack. Day boundaries come from UserCalendar.
@MainActor
struct NutritionDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var date: Date
    @State private var showingTargets = false
    @State private var addingSlot: MealSlot?
    @State private var editingEntry: FoodEntry?
    @State private var errorMessage: String?

    init(initialDate: Date = Date()) {
        _date = State(initialValue: initialDate)
    }

    private var calendar: Calendar { UserCalendar.current(modelContext: modelContext) }
    private var day: Date { calendar.startOfDay(for: date) }
    private var nextDay: Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var service: NutritionService { NutritionService.forUser(modelContext: modelContext) }

    var body: some View {
        NutritionDayContent(day: day,
                            nextDay: nextDay,
                            onAdd: { addingSlot = $0 },
                            onEdit: { editingEntry = $0 },
                            onEditTargets: { showingTargets = true },
                            onDelete: delete)
            .id(day)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shift(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                    Button("Today") { date = Date() }
                        .disabled(isToday)
                    Button {
                        shift(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(isToday)
                    .accessibilityLabel("Next day")
                }
            }
            .safeAreaInset(edge: .top) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                        .padding(.horizontal)
                }
            }
            .sheet(item: $addingSlot) { slot in
                AddFoodSheet(slot: slot, loggedAt: logTime(for: slot), service: service)
            }
            .sheet(item: $editingEntry) { entry in
                FoodEntryEditSheet(entry: entry, service: service)
            }
            .sheet(isPresented: $showingTargets) {
                NutritionTargetsSheet(service: service, date: day, weightLbs: profiles.first?.weightLbs)
            }
            .task { await requestAuthorization() }
    }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func shift(by days: Int) {
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return }
        // Meals are logged as they happen; there is nothing to plan on a
        // future day yet.
        date = min(shifted, Date())
    }

    /// Entries on today get the real clock. On a past day they land at the
    /// meal's usual hour so Apple Health shows them at a sensible time.
    private func logTime(for slot: MealSlot) -> Date {
        if isToday { return Date() }
        return calendar.date(bySettingHour: slot.defaultHour, minute: 0, second: 0, of: day) ?? day
    }

    private func delete(_ entry: FoodEntry) {
        do {
            try service.deleteEntry(entry)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't delete that entry. \(error.localizedDescription)"
        }
    }

    /// The spec asks for nutrition authorization on first open of this
    /// surface, not at launch. UI tests never see the system sheet.
    private func requestAuthorization() async {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        await service.requestNutritionAuthorizationIfNeeded()
    }
}

extension MealSlot {
    /// Hour used when an entry is added to a past day.
    var defaultHour: Int {
        switch self {
        case .breakfast: return 8
        case .lunch: return 12
        case .snack: return 15
        case .dinner: return 19
        }
    }
}

/// Query-driven body for one day. Recreated (via `.id(day)`) when the day
/// changes so the predicates are always for the visible day.
@MainActor
private struct NutritionDayContent: View {
    @Query private var entries: [FoodEntry]
    @Query(sort: [SortDescriptor(\NutritionTargets.effectiveFrom, order: .reverse),
                  SortDescriptor(\NutritionTargets.createdAt, order: .reverse)])
    private var targetRows: [NutritionTargets]
    @Query private var logs: [DailyLog]

    let day: Date
    let onAdd: (MealSlot) -> Void
    let onEdit: (FoodEntry) -> Void
    let onEditTargets: () -> Void
    let onDelete: (FoodEntry) -> Void

    init(day: Date,
         nextDay: Date,
         onAdd: @escaping (MealSlot) -> Void,
         onEdit: @escaping (FoodEntry) -> Void,
         onEditTargets: @escaping () -> Void,
         onDelete: @escaping (FoodEntry) -> Void) {
        self.day = day
        self.onAdd = onAdd
        self.onEdit = onEdit
        self.onEditTargets = onEditTargets
        self.onDelete = onDelete
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= day && $0.date < nextDay },
                         sort: [SortDescriptor(\FoodEntry.loggedAt, order: .forward)])
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= day && $0.date < nextDay && $0.supersededAt == nil })
    }

    private var summary: NutritionDaySummary {
        NutritionService.summary(date: day,
                                 entries: entries,
                                 targets: targetRows.first { $0.effectiveFrom <= day },
                                 activeEnergyKcal: logs.first?.activeEnergyBurnedKcal)
    }

    var body: some View {
        List {
            Section {
                NutritionSummaryCard(summary: summary, onEditTargets: onEditTargets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(MealSlot.allCases) { slot in
                let rows = entries.filter { $0.mealSlot == slot }
                Section {
                    if rows.isEmpty {
                        Text("Nothing logged")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(rows) { entry in
                        Button {
                            onEdit(entry)
                        } label: {
                            FoodEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label(slot.displayName, systemImage: slot.systemImage)
                        Spacer()
                        if !rows.isEmpty {
                            Text(NutritionFormat.kcal(MacroTotals.sum(rows.map(\.totals)).calories))
                                .monospacedDigit()
                                .accessibilityIdentifier("nutrition.total.\(slot.rawValue)")
                        }
                        Button {
                            onAdd(slot)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.matcha)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add to \(slot.displayName)")
                        .accessibilityIdentifier("nutrition.add.\(slot.rawValue)")
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DojoBackground())
    }
}

/// What's left today. Protein leads (a fitness user, not a weight-loss-only
/// user), then calories, then carbs and fat. The exercise adjustment shows
/// as its own line so the math is transparent.
@MainActor
struct NutritionSummaryCard: View {
    let summary: NutritionDaySummary
    let onEditTargets: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionEyebrow(title: summary.hasTargets ? "What's left" : "Logged", tint: Theme.matcha)
                Spacer()
                Button(summary.hasTargets ? "Targets" : "Set targets") { onEditTargets() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("nutrition.targets")
            }

            if summary.hasTargets {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    macroColumn("Protein",
                                remaining: summary.proteinRemaining,
                                consumed: summary.consumed.protein,
                                target: summary.targets?.proteinGrams,
                                progress: summary.proteinProgress,
                                unit: "g",
                                tint: Theme.matcha,
                                headline: true)
                    macroColumn("Calories",
                                remaining: summary.caloriesRemaining,
                                consumed: summary.consumed.calories,
                                target: summary.calorieBudget,
                                progress: summary.caloriesProgress,
                                unit: "kcal",
                                tint: Theme.kurenai,
                                headline: true)
                }
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    macroColumn("Carbs",
                                remaining: summary.carbsRemaining,
                                consumed: summary.consumed.carbs,
                                target: summary.targets?.carbsGrams,
                                progress: summary.carbsProgress,
                                unit: "g",
                                tint: Theme.ai,
                                headline: false)
                    macroColumn("Fat",
                                remaining: summary.fatRemaining,
                                consumed: summary.consumed.fat,
                                target: summary.targets?.fatGrams,
                                progress: summary.fatProgress,
                                unit: "g",
                                tint: Theme.kin,
                                headline: false)
                }
                if summary.exerciseAdjustmentKcal > 0, let burned = summary.activeEnergyKcal,
                   let percent = summary.targets?.exerciseEatBackPercent {
                    Label("+\(NutritionFormat.wholeNumber(summary.exerciseAdjustmentKcal)) kcal from exercise (\(NutritionFormat.wholeNumber(percent * 100))% of \(NutritionFormat.wholeNumber(burned)) burned)",
                          systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("\(NutritionFormat.kcal(summary.consumed.calories)) · P \(NutritionFormat.wholeNumber(summary.consumed.protein)) · C \(NutritionFormat.wholeNumber(summary.consumed.carbs)) · F \(NutritionFormat.wholeNumber(summary.consumed.fat))")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("Set daily targets to see what's left. Protein first.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.l)
        .dojoCardSurface()
        // No container identifier here: it would propagate to every child
        // and mask the Targets button's own identifier.
    }

    private func macroColumn(_ name: String,
                             remaining: Double?,
                             consumed: Double,
                             target: Double?,
                             progress: Double,
                             unit: String,
                             tint: Color,
                             headline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(NutritionFormat.remaining(remaining ?? 0, unit: unit))
                .font(headline ? Theme.numeral(22) : .subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ProgressView(value: progress)
                .tint(tint)
            Text("\(NutritionFormat.wholeNumber(consumed)) of \(NutritionFormat.wholeNumber(target ?? 0)) \(unit)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text([entry.brand, entry.portionLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(NutritionFormat.kcal(entry.totals.calories))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("P \(NutritionFormat.wholeNumber(entry.totals.protein)) · C \(NutritionFormat.wholeNumber(entry.totals.carbs)) · F \(NutritionFormat.wholeNumber(entry.totals.fat))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        NutritionDayView(initialDate: Date())
    }
    .modelContainer(nutritionPreviewContainer)
}

@MainActor
private let nutritionPreviewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let profile = UserProfile(name: "Amber")
    profile.onboardingCompleted = true
    container.mainContext.insert(profile)
    let service = NutritionService(modelContext: container.mainContext, calendar: .current)
    // MARK: try? justified - preview fixture; a failed seed only leaves the preview empty.
    _ = try? service.setTargets(NutritionTargetValues(calories: 1900, proteinGrams: 150, carbsGrams: 180, fatGrams: 60))
    // MARK: try? justified - preview fixture; see above.
    if let eggs = try? service.createFood(name: "Eggs", servingSize: 2, servingUnit: "large",
                                          macros: MacroTotals(calories: 140, protein: 12, carbs: 1, fat: 10)) {
        // MARK: try? justified - preview fixture; see above.
        _ = try? service.logEntry(food: eggs, servings: 1.5, meal: .breakfast)
    }
    return container
}()
