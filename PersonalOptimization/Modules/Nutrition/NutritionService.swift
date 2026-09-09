import Foundation
import SwiftData
import HealthKit
import os

enum NutritionError: LocalizedError {
    case emptyName
    case invalidServings
    case invalidTargets

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the food a name."
        case .invalidServings: return "Servings must be more than zero."
        case .invalidTargets: return "Set at least one target above zero."
        }
    }
}

/// Nutrition module service: targets with history, the user's foods, the
/// day's entries, and the HealthKit mirror of every entry. Same shape as
/// HydrationService. Day boundaries come from the injected calendar
/// (UserCalendar in production, an explicit JST calendar in tests), never
/// from a hardcoded timezone.
///
/// HealthKit writes leave the logging path immediately (detached task, three
/// attempts, exhausted failures persisted as HealthKitWriteFailure) so a slow
/// or denied Health store never delays the visible log. See decision 020.
@MainActor
final class NutritionService {
    nonisolated static let maxHealthKitAttempts = 3

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let healthKit: HealthKitServiceProtocol?
    private let logger = Logger.app

    /// The most recent HealthKit dispatch. Tests await it; production ignores it.
    private(set) var lastHealthKitTask: Task<Void, Never>?

    init(modelContext: ModelContext, calendar: Calendar, healthKit: HealthKitServiceProtocol? = nil) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.healthKit = healthKit
    }

    /// Production factory: the user's calendar and the live Health store.
    static func forUser(modelContext: ModelContext,
                        healthKit: HealthKitServiceProtocol? = LiveHealthKitService.shared) -> NutritionService {
        NutritionService(modelContext: modelContext,
                         calendar: UserCalendar.current(modelContext: modelContext),
                         healthKit: healthKit)
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    // MARK: - Targets

    /// The targets in force on `date`: the latest row effective at or before
    /// that day. nil until the user sets targets for the first time.
    func targets(for date: Date) -> NutritionTargets? {
        let day = calendar.startOfDay(for: date)
        var descriptor = FetchDescriptor<NutritionTargets>(
            predicate: #Predicate<NutritionTargets> { $0.effectiveFrom <= day },
            sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse),
                     SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return modelContext.fetchFirstOrNil(descriptor)
    }

    /// Saves targets effective from `date`'s day. A row that already starts
    /// that day is updated in place; otherwise a new row begins that day so
    /// earlier days keep the targets that applied to them.
    @discardableResult
    func setTargets(_ values: NutritionTargetValues, from date: Date = Date()) throws -> NutritionTargets {
        let clean = values.sanitized()
        guard clean.isUsable else { throw NutritionError.invalidTargets }
        let day = calendar.startOfDay(for: date)
        if let current = targets(for: day), current.effectiveFrom == day {
            current.apply(clean)
            try modelContext.save()
            return current
        }
        let row = NutritionTargets(effectiveFrom: day, values: clean)
        modelContext.insert(row)
        try modelContext.save()
        logger.info("Nutrition targets set from \(day, privacy: .public): \(clean.calories, privacy: .public) kcal, \(clean.proteinGrams, privacy: .public) g protein")
        return row
    }

    // MARK: - Foods

    @discardableResult
    func createFood(name: String,
                    brand: String? = nil,
                    servingSize: Double,
                    servingUnit: String,
                    macros: MacroTotals,
                    source: FoodSource = .userCreated,
                    barcode: String? = nil,
                    externalID: String? = nil,
                    servingsPerContainer: Double? = nil) throws -> FoodItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw NutritionError.emptyName }
        let food = FoodItem(
            name: trimmedName,
            brand: Self.blankToNil(brand),
            barcode: Self.blankToNil(barcode),
            source: source,
            externalID: Self.blankToNil(externalID),
            servingSize: servingSize > 0 ? servingSize : 1,
            servingUnit: Self.blankToNil(servingUnit) ?? "serving",
            servingsPerContainer: servingsPerContainer,
            calories: max(0, macros.calories),
            protein: max(0, macros.protein),
            carbs: max(0, macros.carbs),
            fat: max(0, macros.fat),
            fiber: macros.fiber.map { max(0, $0) },
            sugar: macros.sugar.map { max(0, $0) }
        )
        modelContext.insert(food)
        try modelContext.save()
        return food
    }

    /// Edits the food's facts. Existing entries keep their snapshot, so past
    /// days do not change; the next log uses the new numbers.
    func updateFood(_ food: FoodItem,
                    name: String,
                    brand: String?,
                    servingSize: Double,
                    servingUnit: String,
                    macros: MacroTotals) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw NutritionError.emptyName }
        food.name = trimmedName
        food.brand = Self.blankToNil(brand)
        food.servingSize = servingSize > 0 ? servingSize : food.servingSize
        food.servingUnit = Self.blankToNil(servingUnit) ?? food.servingUnit
        food.calories = max(0, macros.calories)
        food.protein = max(0, macros.protein)
        food.carbs = max(0, macros.carbs)
        food.fat = max(0, macros.fat)
        food.fiber = macros.fiber.map { max(0, $0) }
        food.sugar = macros.sugar.map { max(0, $0) }
        try modelContext.save()
    }

    func food(id: UUID) -> FoodItem? {
        modelContext.fetchFirstOrNil(FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { $0.id == id }))
    }

    /// The user's foods, most recently used first, then newest. Phase 1's
    /// "My foods" list; Phase 2 layers Recent / Frequent / Saved on top of
    /// the same `useCount` / `lastUsed` counters.
    func foods(matching query: String = "", limit: Int = 50) -> [FoodItem] {
        let all = modelContext.fetchOrEmpty(
            FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = needle.isEmpty ? all : all.filter { food in
            food.name.lowercased().contains(needle) || (food.brand?.lowercased().contains(needle) ?? false)
        }
        let ordered = matches.sorted { ($0.lastUsed ?? $0.createdAt) > ($1.lastUsed ?? $1.createdAt) }
        return Array(ordered.prefix(limit))
    }

    // MARK: - Entries

    /// Logs `servings` of `food` to the day containing `loggedAt` (user
    /// calendar) and mirrors it to HealthKit off the main path.
    @discardableResult
    func logEntry(food: FoodItem, servings: Double, meal: MealSlot, at loggedAt: Date = Date()) throws -> FoodEntry {
        guard servings > 0 else { throw NutritionError.invalidServings }
        let entry = FoodEntry(date: calendar.startOfDay(for: loggedAt),
                              loggedAt: loggedAt,
                              meal: meal,
                              food: food,
                              servings: servings)
        modelContext.insert(entry)
        food.useCount += 1
        food.lastUsed = loggedAt
        try modelContext.save()
        logger.info("Logged \(food.name, privacy: .private) x\(servings, privacy: .public) as \(meal.rawValue, privacy: .public)")
        dispatchHealthKitWrite(for: entry, replacing: [])
        return entry
    }

    /// Changes servings or meal. HealthKit gets the old samples removed and
    /// the entry rewritten, so Apple Health never shows both versions.
    func updateEntry(_ entry: FoodEntry, servings: Double, meal: MealSlot) throws {
        guard servings > 0 else { throw NutritionError.invalidServings }
        entry.servings = servings
        entry.mealSlot = meal
        let previous = entry.healthKitSampleIDs
        entry.healthKitSampleIDs = []
        entry.healthKitSyncedAt = nil
        try modelContext.save()
        dispatchHealthKitWrite(for: entry, replacing: previous)
    }

    /// Explicit user action (CLAUDE.md allowed-deletion list). Removes the
    /// HealthKit samples too so Apple Health matches the app.
    func deleteEntry(_ entry: FoodEntry) throws {
        let entryID = entry.id
        let previous = entry.healthKitSampleIDs
        let name = entry.name
        modelContext.delete(entry)
        try modelContext.save()
        dispatchHealthKitDelete(entryID: entryID, sampleIDs: previous, name: name)
    }

    func entries(for date: Date) -> [FoodEntry] {
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return modelContext.fetchOrEmpty(
            FetchDescriptor<FoodEntry>(
                predicate: #Predicate<FoodEntry> { $0.date >= day && $0.date < next },
                sortBy: [SortDescriptor(\.loggedAt, order: .forward)]
            )
        )
    }

    func summary(for date: Date) -> NutritionDaySummary {
        let day = calendar.startOfDay(for: date)
        return Self.summary(date: day,
                            entries: entries(for: day),
                            targets: targets(for: day),
                            activeEnergyKcal: dailyLog(for: day)?.activeEnergyBurnedKcal)
    }

    /// Pure assembly shared with views that already hold @Query rows.
    static func summary(date: Date,
                        entries: [FoodEntry],
                        targets: NutritionTargets?,
                        activeEnergyKcal: Double?) -> NutritionDaySummary {
        NutritionDaySummary(date: date,
                            consumed: MacroTotals.sum(entries.map(\.totals)),
                            targets: targets?.values,
                            activeEnergyKcal: activeEnergyKcal,
                            entryCount: entries.count)
    }

    private func dailyLog(for day: Date) -> DailyLog? {
        modelContext.fetchFirstOrNil(
            FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.date == day && $0.supersededAt == nil })
        )
    }

    // MARK: - HealthKit

    var nutritionAuthorizationStatus: HKAuthorizationStatus {
        healthKit?.nutritionAuthorizationStatus() ?? .notDetermined
    }

    /// First open of the nutrition surface asks once. Denied is a legitimate
    /// answer; logging keeps working locally either way.
    @discardableResult
    func requestNutritionAuthorizationIfNeeded() async -> HKAuthorizationStatus {
        guard let healthKit else { return .notDetermined }
        guard healthKit.nutritionAuthorizationStatus() == .notDetermined else {
            return healthKit.nutritionAuthorizationStatus()
        }
        do {
            _ = try await healthKit.requestNutritionAuthorization()
        } catch {
            logger.warning("Nutrition authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        return healthKit.nutritionAuthorizationStatus()
    }

    /// Health is mirrored only while sharing is authorized. Before the user
    /// has answered the prompt, or after a refusal, entries simply stay
    /// local (healthKitSyncedAt nil) instead of producing a failure row and a
    /// "sync needs attention" nag on every meal.
    private var canWriteToHealth: Bool {
        healthKit?.nutritionAuthorizationStatus() == .sharingAuthorized
    }

    private func dispatchHealthKitWrite(for entry: FoodEntry, replacing previous: [UUID]) {
        guard let healthKit, canWriteToHealth else {
            logger.info("Nutrition Health mirror skipped: sharing not authorized")
            return
        }
        let totals = entry.totals
        let sample = NutritionSample(entryID: entry.id,
                                     name: entry.name,
                                     date: entry.loggedAt,
                                     calories: totals.calories,
                                     protein: totals.protein,
                                     carbs: totals.carbs,
                                     fat: totals.fat,
                                     fiber: totals.fiber,
                                     sugar: totals.sugar)
        let container = modelContext.container
        lastHealthKitTask = Task.detached(priority: .utility) {
            let outcome = await Self.withRetry {
                // Delete first so an edit never leaves both versions in Health.
                try await healthKit.deleteNutrition(entryID: sample.entryID, sampleIDs: previous)
                return try await healthKit.saveNutrition(sample)
            }
            switch outcome {
            case .success(let ids):
                await Self.markSynced(entryID: sample.entryID, sampleIDs: ids, container: container)
            case .failure(let error, let attempts):
                await Self.persistFailure(description: "Nutrition write (\(sample.name)): \(error.localizedDescription)",
                                          date: sample.date,
                                          kcal: sample.calories,
                                          attempts: attempts,
                                          container: container)
            }
        }
    }

    private func dispatchHealthKitDelete(entryID: UUID, sampleIDs: [UUID], name: String) {
        guard let healthKit, canWriteToHealth else { return }
        let container = modelContext.container
        lastHealthKitTask = Task.detached(priority: .utility) {
            let outcome = await Self.withRetry {
                try await healthKit.deleteNutrition(entryID: entryID, sampleIDs: sampleIDs)
                return []
            }
            if case .failure(let error, let attempts) = outcome {
                await Self.persistFailure(description: "Nutrition delete (\(name)): \(error.localizedDescription)",
                                          date: Date(),
                                          kcal: nil,
                                          attempts: attempts,
                                          container: container)
            }
        }
    }

    private enum RetryOutcome {
        case success([UUID])
        case failure(any Error, Int)
    }

    /// Three attempts with 250 ms then 500 ms backoff, like
    /// SessionLifecycleService. Cancellation ends the loop early.
    nonisolated private static func withRetry(_ operation: @Sendable () async throws -> [UUID]) async -> RetryOutcome {
        var attempt = 0
        var lastError: (any Error)?
        while attempt < maxHealthKitAttempts {
            do {
                return .success(try await operation())
            } catch {
                attempt += 1
                lastError = error
                Logger.healthkit.warning(
                    "Nutrition HK attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if attempt < maxHealthKitAttempts {
                    do {
                        try await Task.sleep(for: .milliseconds(250 * (1 << (attempt - 1))))
                    } catch {
                        break
                    }
                }
            }
        }
        return .failure(lastError ?? HealthKitError.dataNotAvailable, attempt)
    }

    private static func markSynced(entryID: UUID, sampleIDs: [UUID], container: ModelContainer) {
        let context = container.mainContext
        // The entry may have been deleted while the write was in flight.
        guard let entry = context.fetchFirstOrNil(
            FetchDescriptor<FoodEntry>(predicate: #Predicate<FoodEntry> { $0.id == entryID })
        ) else { return }
        entry.healthKitSampleIDs = sampleIDs
        entry.healthKitSyncedAt = Date()
        do {
            try context.save()
        } catch {
            Logger.healthkit.error("Could not record nutrition sample ids: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func persistFailure(description: String,
                                       date: Date,
                                       kcal: Double?,
                                       attempts: Int,
                                       container: ModelContainer) {
        let context = container.mainContext
        let failure = HealthKitWriteFailure(timestamp: Date(),
                                            activityTypeRaw: 0,
                                            startTime: date,
                                            endTime: date,
                                            totalEnergyKcal: kcal,
                                            totalDistanceMeters: nil,
                                            errorDescription: description,
                                            retryCount: attempts)
        context.insert(failure)
        do {
            try context.save()
        } catch {
            Logger.healthkit.error("Could not persist nutrition HK failure: \(error.localizedDescription, privacy: .public)")
        }
        Logger.healthkit.error("Nutrition HK write exhausted retries: \(description, privacy: .public)")
    }

    private static func blankToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
