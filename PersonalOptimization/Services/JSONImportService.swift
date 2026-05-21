import Foundation
import SwiftData
import os

enum JSONImportError: LocalizedError {
    case unsupportedVersion(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "Export payload version \(v) is not supported"
        case .decodingFailed(let e): return "Failed to decode export payload: \(e.localizedDescription)"
        }
    }
}

@MainActor
enum JSONImportService {

    /// Restores a previously-exported store. Replace semantics: deletes all
    /// existing entities for each type before inserting the imported records.
    /// This is round-trip lossless when the export+import cycle is uninterrupted.
    static func restore(data: Data, modelContext: ModelContext) throws {
        let payload: ExportPayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(ExportPayload.self, from: data)
        } catch {
            throw JSONImportError.decodingFailed(error)
        }

        guard (1...2).contains(payload.version) else {
            throw JSONImportError.unsupportedVersion(payload.version)
        }

        try wipe(modelContext: modelContext)
        try insertAll(from: payload, into: modelContext)
        try modelContext.save()
        Logger.persistence.info("Restore complete: \(payload.scheduleBlocks.count, privacy: .public) blocks, \(payload.dailyLogs.count, privacy: .public) logs")
    }

    private static func wipe(modelContext: ModelContext) throws {
        try modelContext.delete(model: UserProfile.self)
        try modelContext.delete(model: ScheduleBlock.self)
        try modelContext.delete(model: DailyLog.self)
        try modelContext.delete(model: LiftSession.self)
        try modelContext.delete(model: LiftExercise.self)
        try modelContext.delete(model: LiftSet.self)
        try modelContext.delete(model: BasketballSession.self)
        try modelContext.delete(model: SwimSession.self)
        try modelContext.delete(model: LabDraw.self)
        try modelContext.delete(model: WearableEntry.self)
        try modelContext.delete(model: ProtocolEntry.self)
        try modelContext.delete(model: PomodoroSession.self)
        try modelContext.delete(model: AdminTask.self)
        try modelContext.delete(model: LearningStreak.self)
        try modelContext.delete(model: CharacterStateLog.self)
        // M3.7 entities. Safe-no-op when payload is version 1 (no rows to load).
        try modelContext.delete(model: ActivityArchive.self)
        try modelContext.delete(model: DetectedPattern.self)
        try modelContext.delete(model: PrescribedWorkout.self)
        try modelContext.delete(model: ScheduleSuggestion.self)
        try modelContext.delete(model: WeeklyProgram.self)
    }

    private static func insertAll(from payload: ExportPayload, into ctx: ModelContext) throws {
        if let p = payload.userProfile {
            ctx.insert(makeUserProfile(from: p))
        }
        for dto in payload.scheduleBlocks { ctx.insert(makeScheduleBlock(from: dto)) }
        for dto in payload.dailyLogs { ctx.insert(makeDailyLog(from: dto)) }
        for dto in payload.liftSessions { ctx.insert(makeLiftSession(from: dto)) }
        for dto in payload.basketballSessions { ctx.insert(makeBasketball(from: dto)) }
        for dto in payload.swimSessions { ctx.insert(makeSwim(from: dto)) }
        for dto in payload.labDraws { ctx.insert(makeLab(from: dto)) }
        for dto in payload.wearableEntries { ctx.insert(makeWearable(from: dto)) }
        for dto in payload.protocolEntries { ctx.insert(makeProtocol(from: dto)) }
        for dto in payload.pomodoroSessions { ctx.insert(makePomodoro(from: dto)) }
        for dto in payload.adminTasks { ctx.insert(makeAdmin(from: dto)) }
        for dto in payload.learningStreaks { ctx.insert(makeStreak(from: dto)) }
        for dto in payload.characterStateLogs { ctx.insert(makeCharacterLog(from: dto)) }
        for dto in payload.activityArchives ?? [] { ctx.insert(makeActivityArchive(from: dto)) }
        for dto in payload.detectedPatterns ?? [] { ctx.insert(makeDetectedPattern(from: dto)) }
        for dto in payload.prescribedWorkouts ?? [] { ctx.insert(makePrescribedWorkout(from: dto)) }
        for dto in payload.scheduleSuggestions ?? [] { ctx.insert(makeScheduleSuggestion(from: dto)) }
        for dto in payload.weeklyPrograms ?? [] { ctx.insert(makeWeeklyProgram(from: dto)) }
    }

    // MARK: - DTO -> Model factories

    private static func makeUserProfile(from d: UserProfileDTO) -> UserProfile {
        let p = UserProfile(name: d.name, dob: d.dob, sex: d.sex)
        p.heightInches = d.heightInches
        p.weightLbs = d.weightLbs
        p.timezone = d.timezone
        p.fastWindowStartHour = d.fastWindowStartHour
        p.fastWindowEndHour = d.fastWindowEndHour
        p.bottleSizeOz = d.bottleSizeOz
        p.anthropicModel = d.anthropicModel
        p.rolloutPhase = d.rolloutPhase
        p.notificationBundling = d.notificationBundling
        p.mascotEnabled = d.mascotEnabled
        p.reducedMotion = d.reducedMotion
        // M3.7 fields. Optional in v1 payloads; keep struct defaults if absent.
        if let v = d.mascotVariant { p.mascotVariant = v }
        p.primaryGoal = d.primaryGoal
        if let v = d.secondaryGoalsCSV { p.secondaryGoalsCSV = v }
        if let v = d.equipmentAccess { p.equipmentAccess = v }
        if let v = d.weeklyTrainingTargetSessions { p.weeklyTrainingTargetSessions = v }
        if let v = d.restrictionsCSV { p.restrictionsCSV = v }
        return p
    }

    // MARK: - M3.7 factories

    private static func makeActivityArchive(from d: ActivityArchiveDTO) -> ActivityArchive {
        let a = ActivityArchive(date: d.date)
        a.workoutVolumeTotal = d.workoutVolumeTotal
        a.workoutCount = d.workoutCount
        a.fastingHours = d.fastingHours
        a.hydrationOz = d.hydrationOz
        a.learningMinutes = d.learningMinutes
        a.dominantMascotState = d.dominantMascotState
        a.masterMetric = d.masterMetric
        a.stepsHK = d.stepsHK
        a.activeCaloriesHK = d.activeCaloriesHK
        a.exerciseMinutesHK = d.exerciseMinutesHK
        a.sleepMinutesHK = d.sleepMinutesHK
        a.hrvAvgHK = d.hrvAvgHK
        a.restingHRHK = d.restingHRHK
        return a
    }

    private static func makeDetectedPattern(from d: DetectedPatternDTO) -> DetectedPattern {
        let type = PatternType(rawValue: d.patternTypeRaw) ?? .scheduleDrift
        let p = DetectedPattern(
            detectedAt: d.detectedAt,
            patternType: type,
            confidence: d.confidence,
            summary: d.summary,
            detail: d.detail,
            actionableSuggestion: d.actionableSuggestion
        )
        p.dismissed = d.dismissed
        p.snoozedUntil = d.snoozedUntil
        return p
    }

    private static func makePrescribedWorkout(from d: PrescribedWorkoutDTO) -> PrescribedWorkout {
        let type = PrescribedWorkoutType(rawValue: d.workoutTypeRaw) ?? .rest
        let pw = PrescribedWorkout(
            generatedAt: d.generatedAt,
            forDate: d.forDate,
            workoutType: type,
            template: d.template,
            rationale: d.rationale,
            tokenUsage: d.tokenUsage,
            modelUsed: d.modelUsed
        )
        pw.statusRaw = d.statusRaw
        pw.sessionUUIDString = d.sessionUUIDString
        return pw
    }

    private static func makeScheduleSuggestion(from d: ScheduleSuggestionDTO) -> ScheduleSuggestion {
        let type = ScheduleSuggestionChangeType(rawValue: d.changeTypeRaw) ?? .shiftBlock
        let s = ScheduleSuggestion(
            generatedAt: d.generatedAt,
            summary: d.summary,
            detail: d.detail,
            changeType: type,
            changePayload: d.changePayload,
            rationaleData: d.rationaleData
        )
        s.statusRaw = d.statusRaw
        s.snoozedUntil = d.snoozedUntil
        return s
    }

    private static func makeWeeklyProgram(from d: WeeklyProgramDTO) -> WeeklyProgram {
        let wp = WeeklyProgram(
            weekStartDate: d.weekStartDate,
            generatedAt: d.generatedAt,
            programJSON: d.programJSON,
            coachNarrative: d.coachNarrative,
            tokenUsage: d.tokenUsage,
            modelUsed: d.modelUsed
        )
        wp.statusRaw = d.statusRaw
        return wp
    }

    private static func makeScheduleBlock(from d: ScheduleBlockDTO) -> ScheduleBlock {
        let blockType = BlockType(rawValue: d.typeRaw) ?? .other
        let b = ScheduleBlock(
            dayOfWeek: d.dayOfWeek, startTime: d.startTime, endTime: d.endTime,
            activity: d.activity, type: blockType, module: d.module
        )
        b.isOverride = d.isOverride
        b.overrideDate = d.overrideDate
        return b
    }

    private static func makeDailyLog(from d: DailyLogDTO, calendar: Calendar = .current) -> DailyLog {
        let l = DailyLog(date: d.date, calendar: calendar)
        l.fastStart = d.fastStart
        l.fastEnd = d.fastEnd
        l.fastBrokeEarly = d.fastBrokeEarly
        l.fastBreakReason = d.fastBreakReason
        l.waterOz = d.waterOz
        l.electrolyteSessions = d.electrolyteSessions
        l.japaneseMinutes = d.japaneseMinutes
        l.guitarMinutes = d.guitarMinutes
        l.courseworkMinutes = d.courseworkMinutes
        l.subjectiveEnergy = d.subjectiveEnergy
        l.achillesPain = d.achillesPain
        l.sleepHours = d.sleepHours
        l.restingHR = d.restingHR
        l.hrvRmssd = d.hrvRmssd
        l.weightLbs = d.weightLbs
        l.notes = d.notes
        return l
    }

    private static func makeLiftSession(from d: LiftSessionDTO) -> LiftSession {
        let session = LiftSession(date: d.date, template: d.template)
        session.totalVolumeLbs = d.totalVolumeLbs
        session.durationMinutes = d.durationMinutes
        session.avgHR = d.avgHR
        session.notes = d.notes
        var exercises: [LiftExercise] = []
        for ed in d.exercises {
            let e = LiftExercise(name: ed.name, orderIndex: ed.orderIndex)
            e.rpe = ed.rpe
            var sets: [LiftSet] = []
            for sd in ed.sets {
                let s = LiftSet(weightLbs: sd.weightLbs, reps: sd.reps, orderIndex: sd.orderIndex)
                s.restSeconds = sd.restSeconds
                sets.append(s)
            }
            e.sets = sets
            exercises.append(e)
        }
        session.exercises = exercises
        return session
    }

    private static func makeBasketball(from d: BasketballSessionDTO) -> BasketballSession {
        let s = BasketballSession(date: d.date, startTime: d.startTime, endTime: d.endTime)
        s.avgHR = d.avgHR
        s.maxHR = d.maxHR
        s.hrZoneMinutes = d.hrZoneMinutes
        s.hydrationOz = d.hydrationOz
        s.achillesPostScore = d.achillesPostScore
        s.notes = d.notes
        return s
    }

    private static func makeSwim(from d: SwimSessionDTO) -> SwimSession {
        let s = SwimSession(date: d.date, poolLengthMeters: d.poolLengthMeters)
        s.laps = d.laps
        s.totalMeters = d.totalMeters
        s.durationMinutes = d.durationMinutes
        s.avgHR = d.avgHR
        s.location = d.location
        return s
    }

    private static func makeLab(from d: LabDrawDTO) -> LabDraw {
        let l = LabDraw(date: d.date, values: d.values)
        l.notes = d.notes
        l.sourcePdfFilename = d.sourcePdfFilename
        return l
    }

    private static func makeWearable(from d: WearableEntryDTO) -> WearableEntry {
        let w = WearableEntry(date: d.date, source: d.source)
        w.metrics = d.metrics
        w.notes = d.notes
        return w
    }

    private static func makeProtocol(from d: ProtocolEntryDTO) -> ProtocolEntry {
        let p = ProtocolEntry(date: d.date, category: d.category, title: d.title)
        p.notes = d.notes
        p.dose = d.dose
        p.retestDate = d.retestDate
        p.completed = d.completed
        p.completedAt = d.completedAt
        return p
    }

    private static func makePomodoro(from d: PomodoroSessionDTO) -> PomodoroSession {
        let s = PomodoroSession(date: d.date, courseTag: d.courseTag,
                                workMinutes: d.workMinutes, breakMinutes: d.breakMinutes)
        s.completedCycles = d.completedCycles
        s.notes = d.notes
        return s
    }

    private static func makeAdmin(from d: AdminTaskDTO) -> AdminTask {
        let a = AdminTask(title: d.title, category: d.category)
        a.dueDate = d.dueDate
        a.completed = d.completed
        a.completedAt = d.completedAt
        a.notes = d.notes
        a.createdAt = d.createdAt
        return a
    }

    private static func makeStreak(from d: LearningStreakDTO) -> LearningStreak {
        let s = LearningStreak(module: d.module)
        s.currentStreak = d.currentStreak
        s.longestStreak = d.longestStreak
        s.lastCompletedDate = d.lastCompletedDate
        s.totalMinutesAllTime = d.totalMinutesAllTime
        return s
    }

    private static func makeCharacterLog(from d: CharacterStateLogDTO) -> CharacterStateLog {
        let state = CharacterState(rawValue: d.stateRaw) ?? .neutral
        let log = CharacterStateLog(timestamp: d.timestamp, state: state, triggerReason: d.triggerReason)
        log.durationSeconds = d.durationSeconds
        return log
    }
}
