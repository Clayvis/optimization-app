import Foundation
import HealthKit
import SwiftData
import os

/// Pulls HealthKit data into today's `DailyLog`. Idempotent — running twice
/// with the same source data produces the same DailyLog. Designed to be
/// called from:
///   - App launch (after onboarding-gate check)
///   - TodayView `.refreshable {}` (pull-to-refresh)
///   - Settings → Data → "Refresh from HealthKit"
///   - HealthKitObserverService when a background sample lands
///
/// Failure mode: a single fetch failure logs a warning but does NOT abort the
/// rest of the sync. The user gets whatever HealthKit was willing to share.
///
/// Observable state (`isSyncing`, `lastSyncedAt`, `lastSyncDurationMs`,
/// `lastSyncError`) lets the UI show a "catching up..." spinner and surfaces
/// failures in Diagnostics.
@MainActor
@Observable
final class HealthKitSyncService {
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncDurationMs: Int?
    private(set) var lastSyncError: String?

    private let modelContext: ModelContext
    private let healthKit: HealthKitServiceProtocol
    private let logger = Logger.healthkit
    private let now: () -> Date

    init(modelContext: ModelContext,
         healthKit: HealthKitServiceProtocol = LiveHealthKitService.shared,
         now: @escaping () -> Date = Date.init) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.now = now
    }

    /// Pulls today's HealthKit data into today's DailyLog row. Returns the
    /// row written to so callers can introspect what landed.
    @discardableResult
    func syncToday() async -> DailyLog {
        await sync(for: now())
    }

    /// Pulls HealthKit data for a specific day into its DailyLog row.
    /// Powers retroactive recompute when late-arriving samples (Garmin,
    /// Strava, Withings) land for a day in the past.
    @discardableResult
    func sync(for date: Date) async -> DailyLog {
        let started = Date()
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncedAt = Date()
            lastSyncDurationMs = Int(Date().timeIntervalSince(started) * 1000)
        }
        let log = ensureLog(for: date)

        // Latest single-sample readings.
        log.respiratoryRate = await tryFetchLatest(.respiratoryRate,
                                                   unit: HKUnit.count().unitDivided(by: .minute()),
                                                   on: date) ?? log.respiratoryRate
        log.oxygenSaturationPercent = await tryFetchLatest(.oxygenSaturation,
                                                           unit: .percent(),
                                                           on: date).map { $0 * 100 } ?? log.oxygenSaturationPercent
        log.bodyFatPercentage = await tryFetchLatest(.bodyFatPercentage,
                                                     unit: .percent(),
                                                     on: date).map { $0 * 100 } ?? log.bodyFatPercentage
        if let lean = await tryFetchLatest(.leanBodyMass,
                                            unit: .pound(),
                                            on: date) {
            log.leanBodyMassLbs = lean
        }
        if let weight = await tryFetchLatest(.bodyMass,
                                              unit: .pound(),
                                              on: date) {
            log.weightLbs = weight
        }
        if let hrr = await tryFetchLatest(.heartRateRecoveryOneMinute,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          on: date) {
            log.heartRateRecovery1minBpm = Int(hrr.rounded())
        }
        if let rhr = await tryFetchLatest(.restingHeartRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          on: date) {
            log.restingHR = Int(rhr.rounded())
        }
        if let hrv = await tryFetchLatest(.heartRateVariabilitySDNN,
                                          unit: HKUnit.secondUnit(with: .milli),
                                          on: date) {
            log.hrvRmssd = hrv
        }
        if #available(iOS 16.0, *) {
            log.wristTemperatureCelsius = await tryFetchLatest(.appleSleepingWristTemperature,
                                                               unit: .degreeCelsius(),
                                                               on: date)
                ?? log.wristTemperatureCelsius
        }

        // Daily aggregates (sum).
        if let steps = await tryFetchSum(.stepCount, unit: .count(), for: date) {
            log.stepCount = Int(steps.rounded())
        }
        if let exercise = await tryFetchSum(.appleExerciseTime, unit: .minute(), for: date) {
            log.appleExerciseMinutes = Int(exercise.rounded())
        }
        if let distance = await tryFetchSum(.distanceWalkingRunning, unit: .meter(), for: date) {
            log.distanceMeters = distance
        }
        if let kcal = await tryFetchSum(.dietaryEnergyConsumed, unit: .kilocalorie(), for: date) {
            log.dietaryKcal = kcal
        }
        if let protein = await tryFetchSum(.dietaryProtein, unit: .gram(), for: date) {
            log.dietaryProteinG = protein
        }
        if let carbs = await tryFetchSum(.dietaryCarbohydrates, unit: .gram(), for: date) {
            log.dietaryCarbsG = carbs
        }
        if let fat = await tryFetchSum(.dietaryFatTotal, unit: .gram(), for: date) {
            log.dietaryFatG = fat
        }
        if let caffeine = await tryFetchSum(.dietaryCaffeine, unit: .gramUnit(with: .milli), for: date) {
            log.caffeineMg = caffeine
        }
        if #available(iOS 17.0, *) {
            if let daylight = await tryFetchSum(.timeInDaylight, unit: .minute(), for: date) {
                log.timeInDaylightMinutes = Int(daylight.rounded())
            }
        }
        if let envDb = await tryFetchLatest(.environmentalAudioExposure,
                                            unit: HKUnit.decibelAWeightedSoundPressureLevel(),
                                            on: date) {
            log.environmentalAudioDb = envDb
        }

        // Special-shape pulls.
        if let sleep = await tryFetchSleep(for: date) {
            log.sleepHours = sleep
        }
        if let mindful = await tryFetchMindful(for: date) {
            log.mindfulMinutes = Int(mindful.rounded())
        }

        log.healthKitSyncedAt = now()
        do {
            try modelContext.save()
            lastSyncError = nil
        } catch {
            logger.error("HealthKit sync save failed: \(error.localizedDescription, privacy: .public)")
            lastSyncError = error.localizedDescription
        }
        logger.info("HealthKit sync ran for \(date.description(with: nil), privacy: .public)")
        return log
    }

    /// Pulls HealthKit data for the last `days` days. Used by the observer
    /// pipeline so a late-arriving sample reconstructs the affected past days,
    /// not just today. Posts `dailyLogsRecomputed` once after the batch so
    /// downstream listeners (StreakService, CharacterStateService,
    /// TrendAnalyticsService) can rederive in one pass.
    func syncRange(days: Int = 7) async {
        let calendar = UserCalendar.current(modelContext: modelContext)
        let today = calendar.startOfDay(for: now())
        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            _ = await sync(for: day)
        }
        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
    }

    // MARK: - Internals

    /// Funnels through DailyLogStore so the user-calendar day boundary is
    /// the single source of truth — preventing JST/PST splits during travel.
    private func ensureLog(for date: Date) -> DailyLog {
        DailyLogStore.forUser(modelContext: modelContext).upsert(for: date)
    }

    private func tryFetchLatest(_ id: HKQuantityTypeIdentifier,
                                unit: HKUnit,
                                on date: Date) async -> Double? {
        do {
            return try await healthKit.fetchLatestQuantity(id, unit: unit, on: date)
        } catch {
            logger.warning("HK latest \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func tryFetchSum(_ id: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             for date: Date) async -> Double? {
        do {
            return try await healthKit.fetchSumQuantity(id, unit: unit, for: date)
        } catch {
            logger.warning("HK sum \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func tryFetchSleep(for date: Date) async -> Double? {
        do { return try await healthKit.fetchSleepHours(for: date) }
        catch {
            logger.warning("HK sleep failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func tryFetchMindful(for date: Date) async -> Double? {
        do { return try await healthKit.fetchMindfulMinutes(for: date) }
        catch {
            logger.warning("HK mindful failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
