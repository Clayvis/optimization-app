import Foundation
import SwiftData
import Observation
import os

/// Inputs gathered by `CharacterStateService` from the SwiftData store. Public so
/// tests can construct deterministic snapshots without touching live persistence.
@MainActor
struct CharacterStateInputs {
    var now: Date
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

    static let empty = CharacterStateInputs(
        now: Date(),
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
    private var timer: Timer?
    private var timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    private let logger = Logger.character
    private var lastTransitionAt: Date?

    private init() {}

    func start(modelContext: ModelContext, timezone: TimeZone? = nil) {
        self.modelContext = modelContext
        if let tz = timezone { self.timezone = tz }
        recompute()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        modelContext = nil
    }

    /// Recompute now using live SwiftData. No-op if `start` hasn't been called.
    func recompute() {
        guard let ctx = modelContext else { return }
        let inputs = Self.gatherInputs(modelContext: ctx, timezone: timezone)
        let resolved = Self.resolve(inputs: inputs)
        if resolved.state != currentState || resolved.reason != triggerReason {
            logger.info("Character state \(self.currentState.rawValue, privacy: .public) -> \(resolved.state.rawValue, privacy: .public) reason=\(resolved.reason, privacy: .public)")
            let log = CharacterStateLog(timestamp: inputs.now, state: resolved.state, triggerReason: resolved.reason)
            ctx.insert(log)
            try? ctx.save()
            currentState = resolved.state
            triggerReason = resolved.reason
            lastTransitionAt = inputs.now
        }
    }

    /// Pure resolver. All eight states evaluated; precedence picks the winner.
    static func resolve(inputs: CharacterStateInputs) -> (state: CharacterState, reason: String) {
        var candidates: [CharacterState: String] = [:]

        // urgent: a scheduled module block is starting in <5 min, or current scheduled
        //         module block has ended without a log. Travel/sick suppresses urgency.
        if !inputs.travelModeActive && !inputs.sickDayActive {
            if let nextMin = inputs.minutesUntilNextBlock,
               let next = inputs.nextBlock,
               next.module != nil,
               nextMin <= 5 && nextMin >= 0 {
                candidates[.urgent] = "next block in \(nextMin) min"
            }
        }

        // achievement: a PR was set today.
        if inputs.liftPRSetToday {
            candidates[.achievement] = "lift PR set today"
        } else if inputs.swimPRSetToday {
            candidates[.achievement] = "swim PR set today"
        }

        // proud: workout streak hit a milestone today (7/30/100).
        if inputs.workoutStreakHitMilestoneToday {
            candidates[.proud] = "streak milestone today"
        }

        // disappointed: a streak broke recently, Achilles pain high, or hydration is
        // visibly behind in the evening.
        if inputs.anyStreakBrokenInLast24h {
            candidates[.disappointed] = "streak broke in last 24h"
        } else if inputs.basketballAchillesPainHigh {
            candidates[.disappointed] = "achilles pain reported high"
        } else if Self.hydrationFarBehindEvening(inputs: inputs) {
            candidates[.disappointed] = "hydration far behind in evening"
        }

        // tired: low sleep or HRV down vs 7-day baseline.
        if let sleep = inputs.todayLog?.sleepHours, sleep < 6 {
            candidates[.tired] = "sleep < 6h"
        } else if inputs.sevenDayHrvDownTwentyPercent {
            candidates[.tired] = "hrv down 20% vs 7d avg"
        }

        // thirsty: hydration short of expected pace.
        if let log = inputs.todayLog, inputs.hydrationProgressByHour > 0 {
            let ratio = log.waterOz / inputs.hydrationProgressByHour
            if ratio < 0.6 {
                candidates[.thirsty] = "hydration ratio \(Int(ratio * 100))%"
            }
        }

        // fasting: in fast window.
        if inputs.inFastWindow {
            candidates[.fasting] = "in fast window"
        }

        // neutral fallback.
        candidates[.neutral] = "default"

        // Travel/sick day prefer neutral over disappointed/urgent so the user is
        // not nagged while offline. But fasting/proud/achievement still surface.
        if inputs.travelModeActive {
            candidates.removeValue(forKey: .urgent)
            candidates.removeValue(forKey: .disappointed)
            candidates.removeValue(forKey: .thirsty)
            if candidates[.proud] == nil && candidates[.achievement] == nil && candidates[.fasting] == nil {
                return (.neutral, "travel mode")
            }
        }
        if inputs.sickDayActive {
            candidates.removeValue(forKey: .urgent)
            candidates.removeValue(forKey: .disappointed)
            if candidates[.proud] == nil && candidates[.achievement] == nil {
                return (.tired, "user marked sick day")
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

    static func gatherInputs(modelContext: ModelContext, timezone: TimeZone) -> CharacterStateInputs {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: now)

        let profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
        let todayLog = (try? modelContext.fetch(FetchDescriptor<DailyLog>()))?.first { cal.isDate($0.date, inSameDayAs: day) }
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
        let counters = (try? modelContext.fetch(FetchDescriptor<StreakCounter>())) ?? []
        let workoutCounter = counters.first { $0.domain == StreakDomain.workout.rawValue }
        let workoutStreakHitMilestone = isMilestone(workoutCounter?.currentStreak)
            && (workoutCounter?.lastCompletedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        let anyBroken = counters.contains { c in
            guard let last = c.lastCompletedDate else { return false }
            let yesterday = cal.date(byAdding: .day, value: -1, to: day) ?? day
            return c.currentStreak == 0 && cal.isDate(last, inSameDayAs: yesterday)
        }

        // Lift PR check: simple heuristic — today's session totalVolumeLbs > all prior.
        let liftSessions = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let todaysLifts = liftSessions.filter { cal.isDate($0.date, inSameDayAs: day) }
        let priorMaxLiftVolume = liftSessions.filter { !cal.isDate($0.date, inSameDayAs: day) }.map { $0.totalVolumeLbs }.max() ?? 0
        let liftPR = !todaysLifts.isEmpty && (todaysLifts.map { $0.totalVolumeLbs }.max() ?? 0) > priorMaxLiftVolume && priorMaxLiftVolume > 0

        let swimSessions = (try? modelContext.fetch(FetchDescriptor<SwimSession>())) ?? []
        let todaysSwims = swimSessions.filter { cal.isDate($0.date, inSameDayAs: day) }
        let priorMaxSwimDist = swimSessions.filter { !cal.isDate($0.date, inSameDayAs: day) }.map { $0.totalMeters }.max() ?? 0
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

        return CharacterStateInputs(
            now: now,
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
            travelModeActive: travelModeActive
        )
    }

    private static func hydrationFarBehindEvening(inputs: CharacterStateInputs) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
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
