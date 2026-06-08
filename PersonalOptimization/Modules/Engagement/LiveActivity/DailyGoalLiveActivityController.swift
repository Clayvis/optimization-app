import Foundation
import ActivityKit
import os

/// Live Activity facade for the daily protocol goal. Mirrors
/// `FastingLiveActivityController`: a closure-injectable class so tests can
/// assert start/update/end without touching ActivityKit (unavailable in xctest).
///
/// Lifecycle: the activity is STARTED on the first log of the day (a real
/// action, not merely opening the app), UPDATED on every subsequent log, and
/// auto-dismisses at the day rollover via its stale date.
///
/// Crucially, in-memory tracking (`activeID` / `activeDayStart`) is reconciled
/// against the OS activity registry on every refresh: iOS keeps a Live Activity
/// alive across an app termination, so a fresh process must ADOPT today's
/// existing activity rather than starting a duplicate, and must END any
/// prior-day stray it finds. The stale date is re-threaded through every update
/// so a multi-log day still auto-dismisses at midnight.
@MainActor
final class DailyGoalLiveActivityController {

    typealias StartActivity = @MainActor (DailyGoalActivityAttributes, DailyGoalActivityAttributes.State, Date?) async throws -> String?
    typealias UpdateActivity = @MainActor (String, DailyGoalActivityAttributes.State, Date?) async -> Void
    typealias EndActivity = @MainActor (String) async -> Void
    typealias EndAllActivities = @MainActor () async -> Void
    /// Returns the OS registry's live daily-goal activities as (id, dayStart).
    typealias ExistingActivities = @MainActor () async -> [(id: String, dayStart: Date)]

    static let shared = DailyGoalLiveActivityController()

    private let _start: StartActivity
    private let _update: UpdateActivity
    private let _end: EndActivity
    private let _endAll: EndAllActivities
    private let _existing: ExistingActivities

    private var activeID: String?
    private var activeDayStart: Date?

    init(
        start: @escaping StartActivity = DailyGoalLiveActivityController.liveStart,
        update: @escaping UpdateActivity = DailyGoalLiveActivityController.liveUpdate,
        end: @escaping EndActivity = DailyGoalLiveActivityController.liveEnd,
        endAll: @escaping EndAllActivities = DailyGoalLiveActivityController.liveEndAll,
        existing: @escaping ExistingActivities = DailyGoalLiveActivityController.liveExisting
    ) {
        self._start = start
        self._update = update
        self._end = end
        self._endAll = endAll
        self._existing = existing
    }

    // MARK: - Instance API (testable)

    /// Reflects the current protocol tally on the lock screen. `startIfNeeded`
    /// gates whether a missing activity is created (true on a log, false on a
    /// passive app-open so we never spawn an activity the user didn't earn with
    /// an action). No-op when there is nothing scheduled today.
    func refreshInstance(
        completedDomains: Int,
        totalDomains: Int,
        streak: Int,
        startIfNeeded: Bool,
        asOf: Date = Date(),
        calendar: Calendar = DailyGoalLiveActivityController.deviceCalendar()
    ) async {
        guard totalDomains > 0 else { return }
        let day = calendar.startOfDay(for: asOf)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? asOf
        let state = DailyGoalActivityAttributes.State(
            completedDomains: completedDomains,
            totalDomains: totalDomains,
            streak: streak
        )

        // In-memory rollover (process survived past midnight).
        if let activeDayStart, activeDayStart != day {
            await _endAll()
            activeID = nil
            self.activeDayStart = nil
        }

        // Reconcile against the OS registry when we hold no in-memory handle (a
        // fresh process may have an activity iOS kept alive across a restart).
        // End prior-day strays; adopt today's existing activity instead of
        // starting a duplicate. Runs even on the passive path so a stranded
        // prior-day activity is cleaned up on first reopen.
        if activeID == nil {
            let existing = await _existing()
            for stray in existing where !calendar.isDate(stray.dayStart, inSameDayAs: asOf) {
                await _end(stray.id)
            }
            if let match = existing.first(where: { calendar.isDate($0.dayStart, inSameDayAs: asOf) }) {
                activeID = match.id
                activeDayStart = day
            }
        }

        if let id = activeID {
            await _update(id, state, endOfDay)
            return
        }

        guard startIfNeeded else { return }
        let attributes = DailyGoalActivityAttributes(dayStart: day)
        activeID = try? await _start(attributes, state, endOfDay)
        activeDayStart = activeID == nil ? nil : day
    }

    func endAllInstance() async {
        await _endAll()
        activeID = nil
        activeDayStart = nil
    }

    var isRunning: Bool { activeID != nil }

    // MARK: - Static facade

    static func refresh(completedDomains: Int, totalDomains: Int, streak: Int, startIfNeeded: Bool) async {
        await shared.refreshInstance(
            completedDomains: completedDomains,
            totalDomains: totalDomains,
            streak: streak,
            startIfNeeded: startIfNeeded
        )
    }

    static func endAll() async {
        await shared.endAllInstance()
    }

    nonisolated static func deviceCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    // MARK: - Live implementations

    private static let liveStart: StartActivity = { attributes, state, stale in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.app.info("Live activities disabled by system; skipping daily goal activity")
            return nil
        }
        let content = ActivityContent(state: state, staleDate: stale)
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        Logger.app.info("Started daily goal live activity \(activity.id, privacy: .public)")
        return activity.id
    }

    private static let liveUpdate: UpdateActivity = { id, state, stale in
        // for-in + await (not first(where:) + await) so the non-Sendable
        // Activity is never sent across the actor hop under Swift 6. The stale
        // date is re-supplied so the midnight auto-dismiss survives updates.
        let content = ActivityContent(state: state, staleDate: stale)
        for activity in Activity<DailyGoalActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    private static let liveEnd: EndActivity = { id in
        for activity in Activity<DailyGoalActivityAttributes>.activities where activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static let liveEndAll: EndAllActivities = {
        for activity in Activity<DailyGoalActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static let liveExisting: ExistingActivities = {
        Activity<DailyGoalActivityAttributes>.activities.map { (id: $0.id, dayStart: $0.attributes.dayStart) }
    }
}
