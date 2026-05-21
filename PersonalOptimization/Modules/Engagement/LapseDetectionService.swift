import Foundation
import SwiftData
import os

/// Detects lapse windows in the user's adherence and persists `LapseEvent`
/// rows so the welcome-back UI and Coach prompts can react.
///
/// Definitions (per V1_OPPORTUNITIES.md / Opportunity 4):
/// - softLapse: 2 consecutive days with master metric < 30%.
/// - hardLapse: 5+ consecutive days with master metric < 30%.
/// - crisisLapse: 14+ days persistent.
///
/// Resolved: when a day has master metric ≥ 30% after a lapse window, the
/// active LapseEvent gets `resolvedAt` stamped.
@MainActor
final class LapseDetectionService {
    static let lowAdherenceThreshold: Double = 0.30
    static let softDays = 2
    static let hardDays = 5
    static let crisisDays = 14

    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "lapse")

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Recompute lapse state from `ActivityArchive`. Idempotent — won't
    /// duplicate active LapseEvent rows; will resolve them when the user
    /// re-engages.
    ///
    /// Counts trailing archive rows below the threshold. Days without an
    /// archive don't implicitly count as lapse (would trip crisis on a
    /// fresh install); a non-contiguous gap stops the trailing window so an
    /// older bad block doesn't bleed into today's count.
    @discardableResult
    func recompute(asOf date: Date = Date()) throws -> LapseEvent? {
        let cal = jstCalendar()
        let today = cal.startOfDay(for: date)

        let descriptor = FetchDescriptor<ActivityArchive>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allArchives = (try? modelContext.fetch(descriptor)) ?? []
        let lookback = cal.date(byAdding: .day, value: -30, to: today) ?? today
        let recent = allArchives.filter { $0.date >= lookback && $0.date <= today }

        var consecutiveLow = 0
        var lapseStart: Date? = nil
        var lastSeenDay: Date? = nil
        for archive in recent {
            let day = cal.startOfDay(for: archive.date)
            if let last = lastSeenDay,
               let prevDay = cal.date(byAdding: .day, value: -1, to: last),
               !cal.isDate(prevDay, inSameDayAs: day) {
                break
            }
            if archive.masterMetric < Self.lowAdherenceThreshold {
                consecutiveLow += 1
                lapseStart = day
                lastSeenDay = day
            } else {
                break
            }
        }

        let activeLapse = currentActiveLapse()

        // No lapse currently — resolve any active one and bail.
        if consecutiveLow < Self.softDays {
            if let active = activeLapse, active.resolvedAt == nil {
                active.resolvedAt = today
                try modelContext.save()
                logger.info("Lapse resolved at \(today, privacy: .public)")
            }
            return nil
        }

        // Determine severity from the trailing-low-day count.
        let severity: LapseSeverity = {
            if consecutiveLow >= Self.crisisDays { return .crisis }
            if consecutiveLow >= Self.hardDays { return .hard }
            return .soft
        }()

        // Already-tracked lapse: bump severity if it climbed; reuse the row
        // so welcomeBackShown dedups across launches.
        if let active = activeLapse, active.resolvedAt == nil {
            if active.severity != severity {
                active.severityRaw = severity.rawValue
                active.detectedAt = today
                try modelContext.save()
                logger.info("Lapse severity bumped to \(severity.rawValue, privacy: .public)")
            }
            return active
        }

        let lapse = LapseEvent(
            startedAt: lapseStart ?? today,
            detectedAt: today,
            severity: severity
        )
        modelContext.insert(lapse)
        try modelContext.save()
        logger.info("Lapse opened severity=\(severity.rawValue, privacy: .public)")
        return lapse
    }

    /// Most recent unresolved lapse, if any.
    func currentActiveLapse() -> LapseEvent? {
        let descriptor = FetchDescriptor<LapseEvent>(
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.resolvedAt == nil }
    }

    /// Mark the welcome-back card seen so it doesn't re-render on every
    /// open of the Today tab during the same lapse.
    func markWelcomeBackShown(_ lapse: LapseEvent) {
        lapse.welcomeBackShown = true
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    private func enumerateDays(from start: Date, to end: Date) -> [Date] {
        let cal = jstCalendar()
        var out: [Date] = []
        var cursor = cal.startOfDay(for: start)
        let stop = cal.startOfDay(for: end)
        while cursor <= stop {
            out.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}
