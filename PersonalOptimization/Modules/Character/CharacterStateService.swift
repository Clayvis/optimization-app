import Foundation
import SwiftData
import Observation
import os

/// Inputs gathered by `CharacterStateService` from the SwiftData store. Public so
/// tests can construct deterministic snapshots without touching live persistence.
@MainActor
struct CharacterStateInputs {
    var now: Date
    /// User's resolved timezone. Carried so the static resolvers do day/hour
    /// math in the user's zone, not the device's (W6).
    var timezone: TimeZone
    var profile: UserProfile?
    var todayLog: DailyLog?
    var hydrationTargetMin: Double         // floor that counts as "on track"
    var hydrationProgressByHour: Double    // expected oz at this hour of day
    var currentBlock: ScheduleBlock?
    var nextBlock: ScheduleBlock?
    var minutesUntilNextBlock: Int?
    var workoutStreakHitMilestoneToday: Bool
    var anyStreakBrokenInLast24h: Bool
    var liftPRSetToday: Bool
    var swimPRSetToday: Bool
    var basketballAchillesPainHigh: Bool
    var sevenDayHrvDownTwentyPercent: Bool
    var inFastWindow: Bool
    var sickDayActive: Bool
    var travelModeActive: Bool
    var workoutActive: Bool = false
    var workoutCompletedToday: Bool = false
    var lastWorkoutDate: Date?
    var restDayActive: Bool = false

    static let empty = CharacterStateInputs(
        now: Date(),
        timezone: .current,
        profile: nil,
        todayLog: nil,
        hydrationTargetMin: 64,
        hydrationProgressByHour: 0,
        currentBlock: nil,
        nextBlock: nil,
        minutesUntilNextBlock: nil,
        workoutStreakHitMilestoneToday: false,
        anyStreakBrokenInLast24h: false,
        liftPRSetToday: false,
        swimPRSetToday: false,
        basketballAchillesPainHigh: false,
        sevenDayHrvDownTwentyPercent: false,
        inFastWindow: false,
        sickDayActive: false,
        travelModeActive: false
    )
}

@Observable
@MainActor
final class CharacterStateService {
    static let shared = CharacterStateService()

    private(set) var currentState: CharacterState = .neutral
    private(set) var triggerReason: String = "default"

    private var modelContext: ModelContext?
    private var timezone: TimeZone = TimeZone.current
    private let logger = Logger.character
    private var lastTransitionAt: Date?
    /// Cache window. Repeated `recompute()` calls within this window return
    /// the prior result unless `force` is passed.
    private let cacheWindow: TimeInterval = 60
    private var lastRecomputeAt: Date?
    private var observers: [NSObjectProtocol] = []
    /// Test-only counter incremented on every recompute call. Lets tests
    /// assert that observer-driven recomputes don't stack from accidental
    /// double-start. Not exposed in Release builds.
    #if DEBUG
    private(set) var debugRecomputeCount: Int = 0
    #endif

    private init() {}

    func start(modelContext: ModelContext, timezone: TimeZone? = nil) {
        // Defensive teardown so repeated start() calls do not stack
        // observers or leak prior model-context references. Without this
        // a model-context swap or app re-entry would silently double the
        // recompute fan-out on every event.
        if !observers.isEmpty {
            logger.info("CharacterStateService.start called twice; resetting observers")
            stop()
        }
        self.modelContext = modelContext
        self.timezone = timezone ?? UserCalendar.timezone(modelContext: modelContext)
        recompute(force: true)
        // Subscribe to state-change events instead of polling.
        //
        // `userStateChanged` is a user action (water logged, fast ended) and is
        // rare, so force an immediate recompute for instant mascot feedback.
        //
        // `dailyLogsRecomputed` fires from background HealthKit fan-out, which a
        // single Garmin/Withings sync delivers as a burst of up to a dozen posts
        // within seconds (C2). Force-recomputing on every one hammered the main
        // actor with SwiftData fetches under a concurrent CloudKit merge. Route
        // it through the normal cache window instead (force: false): the first
        // post recomputes, the rest of the burst are cache hits, so the storm
        // collapses to one recompute. Mascot state is daily-granularity, so the
        // up-to-cacheWindow staleness on late samples is irrelevant.
        observers.append(NotificationCenter.default.addObserver(
            forName: .userStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute(force: true) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .workoutPresenceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute(force: true) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .dailyLogsRecomputed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute(force: false) }
        })
    }

    func stop() {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        modelContext = nil
    }

    /// Recompute now using live SwiftData. No-op if `start` hasn't been called.
    /// Returns the cached value if called within `cacheWindow` of the prior
    /// call unless `force` is set.
    func recompute(force: Bool = false) {
        guard let ctx = modelContext else { return }
        if !force, let last = lastRecomputeAt,
           Date().timeIntervalSince(last) < cacheWindow {
            return
        }
        #if DEBUG
        debugRecomputeCount += 1
        #endif
        let inputs = Self.gatherInputs(modelContext: ctx, timezone: timezone)
        let resolved = Self.resolve(inputs: inputs)
        lastRecomputeAt = inputs.now
        if resolved.state != currentState || resolved.reason != triggerReason {
            logger.info("Character state \(self.currentState.rawValue, privacy: .public) -> \(resolved.state.rawValue, privacy: .public) reason=\(resolved.reason, privacy: .public)")
            let log = CharacterStateLog(timestamp: inputs.now, state: resolved.state, triggerReason: resolved.reason)
            ctx.insert(log)
            // MARK: - try? justified because CharacterStateLog is non-critical
            // analytic data. A save failure surfaces in os_log elsewhere; the
            // in-memory `currentState` still updates so the UI reflects the
            // change even if persistence transiently fails.
            try? ctx.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
            currentState = resolved.state
            triggerReason = resolved.reason
            lastTransitionAt = inputs.now
        }
    }

    /// Pure resolver. Reactions follow recorded activity and explicit recovery
    /// choices. A missed day never turns the companion into a punishment.
    static func resolve(inputs: CharacterStateInputs) -> (state: CharacterState, reason: String) {
        var candidates: [CharacterState: String] = [:]

        if inputs.sickDayActive || inputs.restDayActive || inputs.basketballAchillesPainHigh {
            return (.recovering, "Recovery belongs in your week. Your progress stays yours.")
        }
        if inputs.workoutActive {
            return (.training, "One session, your pace. I'm here with you.")
        }
        if inputs.workoutCompletedToday {
            candidates[.celebrating] = "You showed up today. Enjoy your daily win."
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = inputs.timezone
        let daysSinceWorkout = inputs.lastWorkoutDate.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0),
                                    to: calendar.startOfDay(for: inputs.now)).day
        }
        if !inputs.workoutCompletedToday,
           inputs.anyStreakBrokenInLast24h || (daysSinceWorkout ?? 0) >= 3 {
            candidates[.comeback] = "Welcome back. A small session is enough to begin again."
        }

        // urgent: a scheduled module block is starting in <5 min, or current scheduled
        //         module block has ended without a log. Travel/sick suppresses urgency.
        if !inputs.travelModeActive && !inputs.sickDayActive {
            if let nextMin = inputs.minutesUntilNextBlock,
               let next = inputs.nextBlock,
               next.module != nil,
               nextMin <= 5 && nextMin >= 0 {
                candidates[.urgent] = "Your next session starts in \(nextMin) minutes."
            }
        }

        // achievement: a PR was set today.
        if inputs.liftPRSetToday {
            candidates[.achievement] = "A new lifting personal best. You earned this."
        } else if inputs.swimPRSetToday {
            candidates[.achievement] = "A new swimming personal best. You earned this."
        }

        // proud: workout streak hit a milestone today (7/30/100).
        if inputs.workoutStreakHitMilestoneToday {
            candidates[.proud] = "A consistency milestone. Look how far you've come."
        }

        if Self.hydrationFarBehindEvening(inputs: inputs) {
            candidates[.thirsty] = "A water break could fit nicely right now."
        }

        // tired: low sleep or HRV down vs 7-day baseline.
        if let sleep = inputs.todayLog?.sleepHours, sleep.isFinite, sleep > 0, sleep < 6 {
            candidates[.tired] = "A shorter night. Make room for an easier day."
        } else if inputs.sevenDayHrvDownTwentyPercent {
            candidates[.tired] = "Your recovery signals are lower. An easier day is welcome."
        }

        // thirsty: hydration short of expected pace.
        if let log = inputs.todayLog, inputs.hydrationProgressByHour > 0 {
            let ratio = log.waterOz / inputs.hydrationProgressByHour
            if ratio < 0.6 {
                candidates[.thirsty] = "A water break could fit nicely right now."
            }
        }

        // fasting: in fast window.
        if inputs.inFastWindow {
            candidates[.fasting] = "Your fasting window is active. Settle into your rhythm."
        }

        // neutral fallback.
        candidates[.neutral] = "default"

        // Travel suppresses reminders while preserving recorded wins.
        if inputs.travelModeActive {
            candidates.removeValue(forKey: .urgent)
            candidates.removeValue(forKey: .disappointed)
            candidates.removeValue(forKey: .thirsty)
            candidates.removeValue(forKey: .comeback)
            if candidates[.proud] == nil && candidates[.achievement] == nil
                && candidates[.fasting] == nil && candidates[.celebrating] == nil {
                return (.neutral, "travel mode")
            }
        }

        for state in CharacterState.precedenceOrder {
            if let reason = candidates[state] {
                return (state, reason)
            }
        }
        return (.neutral, "default")
    }

    // MARK: - Live data gathering

    static func gatherInputs(modelContext: ModelContext, timezone: TimeZone, now: Date = Date()) -> CharacterStateInputs {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: now)

        let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        // Scoped fetch: predicate on date == day so we only pull the one row
        // instead of streaming the entire DailyLog table every recompute.
        let todayLogDescriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day && $0.supersededAt == nil }
        )
        let todayLog = modelContext.fetchFirstOrNil(todayLogDescriptor)
        let scheduleService = ScheduleService(modelContext: modelContext, timezone: timezone)
        let currentBlock = scheduleService.currentBlock(at: now)
        let nextBlock = scheduleService.nextBlock(after: now)
        let minutesUntilNextBlock: Int? = {
            guard let next = nextBlock,
                  let s = ScheduleService.parseTimeToMinutes(next.startTime) else { return nil }
            let nowMin = scheduleService.minutesFromMidnight(at: now)
            return s - nowMin
        }()

        // Hydration pacing: linear ramp from 0 oz at 06:00 to (rest target min) at 22:00.
        let hourFraction = Self.hourFractionOfWakingDay(now: now, calendar: cal)
        let hydrationFloor: Double = 64
        let hydrationProgressByHour = max(0, min(hydrationFloor, hydrationFloor * hourFraction))

        // Streak signals: read today's StreakCounter rows.
        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let workoutCounter = counters.first { $0.domain == StreakDomain.workout.rawValue }
        let workoutStreakHitMilestone = isMilestone(workoutCounter?.currentStreak)
            && (workoutCounter?.lastCompletedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        let anyBroken = counters.contains { c in
            guard let last = c.lastCompletedDate else { return false }
            let yesterday = cal.date(byAdding: .day, value: -1, to: day) ?? day
            return c.currentStreak == 0 && cal.isDate(last, inSameDayAs: yesterday)
        }

        // Lift PR check: bounded fetches. Today's sessions plus a separate
        // descending fetch of the all-time max volume row (1 fetch each).
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let todaysLiftsDescriptor = FetchDescriptor<LiftSession>(
            predicate: #Predicate<LiftSession> {
                $0.date >= day && $0.date < tomorrow && $0.date <= now && $0.durationMinutes > 0
            }
        )
        let todaysLifts = modelContext.fetchOrEmpty(todaysLiftsDescriptor)
        var priorLiftsDescriptor = FetchDescriptor<LiftSession>(
            predicate: #Predicate<LiftSession> { $0.date < day && $0.durationMinutes > 0 },
            sortBy: [SortDescriptor(\.totalVolumeLbs, order: .reverse)]
        )
        priorLiftsDescriptor.fetchLimit = 1
        let priorMaxLiftVolume = modelContext.fetchFirstOrNil(priorLiftsDescriptor)?.totalVolumeLbs ?? 0
        let liftPR = !todaysLifts.isEmpty && (todaysLifts.map { $0.totalVolumeLbs }.max() ?? 0) > priorMaxLiftVolume && priorMaxLiftVolume > 0

        let todaysSwimsDescriptor = FetchDescriptor<SwimSession>(
            predicate: #Predicate<SwimSession> {
                $0.date >= day && $0.date < tomorrow && $0.date <= now && $0.durationMinutes > 0
            }
        )
        let todaysSwims = modelContext.fetchOrEmpty(todaysSwimsDescriptor)
        var priorSwimsDescriptor = FetchDescriptor<SwimSession>(
            predicate: #Predicate<SwimSession> { $0.date < day && $0.durationMinutes > 0 },
            sortBy: [SortDescriptor(\.totalMeters, order: .reverse)]
        )
        priorSwimsDescriptor.fetchLimit = 1
        let priorMaxSwimDist = modelContext.fetchFirstOrNil(priorSwimsDescriptor)?.totalMeters ?? 0
        let swimPR = !todaysSwims.isEmpty && (todaysSwims.map { $0.totalMeters }.max() ?? 0) > priorMaxSwimDist && priorMaxSwimDist > 0

        let achillesHigh = (todayLog?.achillesPain ?? 0) >= 6

        // Fast window detection: profile + simple in-window check.
        var inFastWindow = false
        if let profile = profile {
            let nowMin = scheduleService.minutesFromMidnight(at: now)
            let startMin = profile.fastWindowStartHour * 60
            let endMin = profile.fastWindowEndHour * 60
            if startMin > endMin {
                inFastWindow = nowMin >= startMin || nowMin < endMin
            } else {
                inFastWindow = nowMin >= startMin && nowMin < endMin
            }
        }

        let sickDayActive = (profile?.sickDayActiveUntil ?? .distantPast) >= now
        let travelModeActive = (profile?.travelModeActiveUntil ?? .distantPast) >= now

        // Fetch only the latest actual workout. Skips, freezes, and future
        // rows cannot trigger celebration or erase the return-after-a-break cue.
        var workoutDescriptor = FetchDescriptor<WorkoutEvent>(
            predicate: #Predicate<WorkoutEvent> {
                $0.completed && $0.date <= now
                    && ($0.source == "lift" || $0.source == "swim"
                        || $0.source == "basketball" || $0.source == "custom")
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 1
        let lastWorkoutDate = modelContext.fetchFirstOrNil(workoutDescriptor)?.date
        #if os(iOS)
        let workoutActive = WorkoutPresenceService.shared.isActive(at: now)
        #else
        // Watch surfaces own their live workout session. A complication does
        // not import the phone's connectivity/presence service.
        let workoutActive = false
        #endif

        return CharacterStateInputs(
            now: now,
            timezone: timezone,
            profile: profile,
            todayLog: todayLog,
            hydrationTargetMin: hydrationFloor,
            hydrationProgressByHour: hydrationProgressByHour,
            currentBlock: currentBlock,
            nextBlock: nextBlock,
            minutesUntilNextBlock: minutesUntilNextBlock,
            workoutStreakHitMilestoneToday: workoutStreakHitMilestone,
            anyStreakBrokenInLast24h: anyBroken,
            liftPRSetToday: liftPR,
            swimPRSetToday: swimPR,
            basketballAchillesPainHigh: achillesHigh,
            sevenDayHrvDownTwentyPercent: false,
            inFastWindow: inFastWindow,
            sickDayActive: sickDayActive,
            travelModeActive: travelModeActive,
            workoutActive: workoutActive,
            workoutCompletedToday: lastWorkoutDate.map { cal.isDate($0, inSameDayAs: day) } ?? false,
            lastWorkoutDate: lastWorkoutDate,
            restDayActive: todayLog?.metadata("dailyWorkout.restDay", as: Bool.self) ?? false
        )
    }

    private static func hydrationFarBehindEvening(inputs: CharacterStateInputs) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = inputs.timezone
        let hour = cal.component(.hour, from: inputs.now)
        guard hour >= 18 else { return false }
        guard let log = inputs.todayLog else { return false }
        return log.waterOz < (inputs.hydrationTargetMin * 0.5)
    }

    private static func isMilestone(_ streak: Int?) -> Bool {
        guard let s = streak else { return false }
        return s == 7 || s == 30 || s == 100
    }

    private static func hourFractionOfWakingDay(now: Date, calendar: Calendar) -> Double {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutesIntoDay = max(0, hour * 60 + minute - 6 * 60) // 06:00 anchor
        return min(1.0, Double(minutesIntoDay) / Double(16 * 60))
    }
}
