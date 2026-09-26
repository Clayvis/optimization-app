import Foundation
import ActivityKit
import os

/// Live Activity facade for the daily protocol goal. Mirrors
/// `FastingLiveActivityController`: a closure-injectable class so tests can
/// assert start/update/end without touching ActivityKit (unavailable in xctest).
///
/// Lifecycle: the activity starts when requested by the foreground status
/// surface, is updated on confirmed logs and Health deliveries, and
/// marks its contents stale at the next freshness deadline (one hour, the next
/// schedule transition, or midnight, whichever comes first).
///
/// iOS ends every Live Activity after eight hours and a person can dismiss it
/// at any time. An ended or dismissed activity never updates again, so it no
/// longer counts as today's activity; the next foreground refresh starts a
/// replacement. Refreshes are serialized: launch, foreground, confirmed logs
/// and Health deliveries can all request one at once, and overlapping calls
/// must not each conclude "no activity" and request two.
///
/// Crucially, in-memory tracking (`activeID` / `activeDayStart`) is reconciled
/// against the OS activity registry on every refresh: iOS keeps a Live Activity
/// alive across an app termination, so a fresh process must ADOPT today's
/// existing activity rather than starting a duplicate, and must END any
/// prior-day stray it finds. The stale date is re-threaded through every update
/// so updates never represent old data as fresh.
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
    /// Tail of the serial refresh queue (see type comment).
    private var queueTail: Task<Void, Never>?

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
    /// gates whether a missing activity can be created (foreground only).
    /// Background callbacks only refresh an existing activity. `freshUntil` is
    /// the moment the status text stops being true (the next schedule
    /// transition); the content goes stale then at the latest.
    func refreshInstance(
        completedDomains: Int,
        totalDomains: Int,
        streak: Int,
        startIfNeeded: Bool,
        statusMessage: String? = nil,
        freshUntil: Date? = nil,
        asOf: Date = Date(),
        calendar: Calendar = DailyGoalLiveActivityController.deviceCalendar()
    ) async {
        let previous = queueTail
        let job = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performRefresh(completedDomains: completedDomains, totalDomains: totalDomains,
                                       streak: streak, startIfNeeded: startIfNeeded,
                                       statusMessage: statusMessage, freshUntil: freshUntil,
                                       asOf: asOf, calendar: calendar)
        }
        queueTail = job
        await job.value
    }

    func endAllInstance() async {
        let previous = queueTail
        let job = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performEndAll()
        }
        queueTail = job
        await job.value
    }

    var isRunning: Bool { activeID != nil }

    /// Latest moment the status is known to be true: one hour after the
    /// update, the next schedule transition, or midnight, whichever is first.
    nonisolated static func freshnessDeadline(asOf: Date, freshUntil: Date?, calendar: Calendar) -> Date {
        let hourLater = calendar.date(byAdding: .hour, value: 1, to: asOf) ?? asOf
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: asOf)) ?? hourLater
        var deadline = min(hourLater, midnight)
        if let freshUntil, freshUntil > asOf { deadline = min(deadline, freshUntil) }
        return deadline
    }

    /// Ended and dismissed activities never update again. Anything else
    /// (active, stale, pending, or a future state) still holds today's slot,
    /// which errs toward updating over starting a duplicate.
    nonisolated static func holdsSlot(_ state: ActivityState) -> Bool {
        switch state {
        case .ended, .dismissed: return false
        default: return true
        }
    }

    // MARK: - Serialized work

    private func performRefresh(
        completedDomains: Int,
        totalDomains: Int,
        streak: Int,
        startIfNeeded: Bool,
        statusMessage: String?,
        freshUntil: Date?,
        asOf: Date,
        calendar: Calendar
    ) async {
        guard totalDomains > 0 else { await performEndAll(); return }
        let day = calendar.startOfDay(for: asOf)
        let endOfDay = Self.freshnessDeadline(asOf: asOf, freshUntil: freshUntil, calendar: calendar)
        let state = DailyGoalActivityAttributes.State(
            completedDomains: completedDomains,
            totalDomains: totalDomains,
            streak: streak, statusMessage: statusMessage, updatedAt: asOf
        )

        // In-memory rollover (process survived past midnight).
        if let activeDayStart, activeDayStart != day {
            await _endAll()
            activeID = nil
            self.activeDayStart = nil
        }

        // iOS can end/dismiss an activity while this process stays alive.
        // Clear a missing handle before adopting or starting today's activity.
        let existing = await _existing()
        if let activeID, !existing.contains(where: { $0.id == activeID }) {
            self.activeID = nil
            activeDayStart = nil
        }
        if activeID == nil {
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
        // MARK: try? justified - a refused request (Live Activities disabled,
        // system limit) leaves no activity; the next foreground retries.
        activeID = try? await _start(attributes, state, endOfDay)
        activeDayStart = activeID == nil ? nil : day
    }

    private func performEndAll() async {
        await _endAll()
        activeID = nil
        activeDayStart = nil
    }

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
        // An activity iOS ended at its eight-hour limit stays on the Lock Screen,
        // frozen, for up to four more hours. Remove it so the replacement is the
        // only status shown. Best effort: ActivityKit documents `end` for active
        // activities, and a no-op here only leaves the old card to expire.
        for activity in Activity<DailyGoalActivityAttributes>.activities where activity.activityState == .ended {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let content = ActivityContent(state: state, staleDate: stale)
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        Logger.app.info("Started daily goal live activity \(activity.id, privacy: .public)")
        return activity.id
    }

    private static let liveUpdate: UpdateActivity = { id, state, stale in
        // for-in + await (not first(where:) + await) so the non-Sendable
        // Activity is never sent across the actor hop under Swift 6. The stale
        // date is re-supplied so the freshness deadline survives updates.
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
        Activity<DailyGoalActivityAttributes>.activities
            .filter { DailyGoalLiveActivityController.holdsSlot($0.activityState) }
            .map { (id: $0.id, dayStart: $0.attributes.dayStart) }
    }
}
