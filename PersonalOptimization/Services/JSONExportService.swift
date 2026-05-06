import Foundation
import SwiftData
import os

// MARK: - Top-level payload

struct ExportPayload: Codable {
    let version: Int
    let exportedAt: Date
    let userProfile: UserProfileDTO?
    let scheduleBlocks: [ScheduleBlockDTO]
    let dailyLogs: [DailyLogDTO]
    let liftSessions: [LiftSessionDTO]
    let basketballSessions: [BasketballSessionDTO]
    let swimSessions: [SwimSessionDTO]
    let labDraws: [LabDrawDTO]
    let wearableEntries: [WearableEntryDTO]
    let protocolEntries: [ProtocolEntryDTO]
    let pomodoroSessions: [PomodoroSessionDTO]
    let adminTasks: [AdminTaskDTO]
    let learningStreaks: [LearningStreakDTO]
    let characterStateLogs: [CharacterStateLogDTO]

    // M3.7 additions (version >= 2). Optional so version 1 payloads decode unchanged.
    let activityArchives: [ActivityArchiveDTO]?
    let detectedPatterns: [DetectedPatternDTO]?
    let prescribedWorkouts: [PrescribedWorkoutDTO]?
    let scheduleSuggestions: [ScheduleSuggestionDTO]?
    let weeklyPrograms: [WeeklyProgramDTO]?
}

// MARK: - DTOs

struct UserProfileDTO: Codable {
    let name: String
    let dob: Date
    let sex: String
    let heightInches: Double
    let weightLbs: Double
    let timezone: String
    let fastWindowStartHour: Int
    let fastWindowEndHour: Int
    let bottleSizeOz: Double
    let anthropicModel: String
    let rolloutPhase: Int
    let notificationBundling: Bool
    let mascotEnabled: Bool
    let reducedMotion: Bool
    // M3.7 fields. Optional for backward compatibility with version-1 payloads.
    let mascotVariant: String?
    let primaryGoal: String?
    let secondaryGoalsCSV: String?
    let equipmentAccess: String?
    let weeklyTrainingTargetSessions: Int?
    let restrictionsCSV: String?
}

struct ScheduleBlockDTO: Codable {
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
    let activity: String
    let typeRaw: String
    let module: String?
    let isOverride: Bool
    let overrideDate: Date?
}

struct DailyLogDTO: Codable {
    let date: Date
    let fastStart: Date?
    let fastEnd: Date?
    let fastBrokeEarly: Bool
    let fastBreakReason: String?
    let waterOz: Double
    let electrolyteSessions: Int
    let japaneseMinutes: Int
    let guitarMinutes: Int
    let courseworkMinutes: Int
    let subjectiveEnergy: Int?
    let achillesPain: Int?
    let sleepHours: Double?
    let restingHR: Int?
    let hrvRmssd: Double?
    let weightLbs: Double?
    let notes: String?
}

struct LiftSessionDTO: Codable {
    let date: Date
    let template: String
    let exercises: [LiftExerciseDTO]
    let totalVolumeLbs: Double
    let durationMinutes: Int
    let avgHR: Int?
    let notes: String?
}

struct LiftExerciseDTO: Codable {
    let name: String
    let orderIndex: Int
    let sets: [LiftSetDTO]
    let rpe: Int?
}

struct LiftSetDTO: Codable {
    let weightLbs: Double
    let reps: Int
    let restSeconds: Int?
    let orderIndex: Int
}

struct BasketballSessionDTO: Codable {
    let date: Date
    let startTime: Date
    let endTime: Date
    let avgHR: Int?
    let maxHR: Int?
    let hrZoneMinutes: [String: Int]
    let hydrationOz: Double
    let achillesPostScore: Int?
    let notes: String?
}

struct SwimSessionDTO: Codable {
    let date: Date
    let poolLengthMeters: Double
    let laps: Int
    let totalMeters: Double
    let durationMinutes: Int
    let avgHR: Int?
    let location: String?
}

struct LabDrawDTO: Codable {
    let date: Date
    let notes: String?
    let values: [String: Double]
    let sourcePdfFilename: String?
}

struct WearableEntryDTO: Codable {
    let date: Date
    let source: String
    let metrics: [String: Double]
    let notes: String?
}

struct ProtocolEntryDTO: Codable {
    let date: Date
    let category: String
    let title: String
    let notes: String?
    let dose: String?
    let retestDate: Date?
    let completed: Bool
    let completedAt: Date?
}

struct PomodoroSessionDTO: Codable {
    let date: Date
    let courseTag: String
    let workMinutes: Int
    let breakMinutes: Int
    let completedCycles: Int
    let notes: String?
}

struct AdminTaskDTO: Codable {
    let title: String
    let category: String
    let dueDate: Date?
    let completed: Bool
    let completedAt: Date?
    let notes: String?
    let createdAt: Date
}

struct LearningStreakDTO: Codable {
    let module: String
    let currentStreak: Int
    let longestStreak: Int
    let lastCompletedDate: Date?
    let totalMinutesAllTime: Int
}

struct CharacterStateLogDTO: Codable {
    let timestamp: Date
    let stateRaw: String
    let triggerReason: String
    let durationSeconds: Int?
}

// MARK: - M3.7 DTOs (version >= 2)

struct ActivityArchiveDTO: Codable {
    let date: Date
    let workoutVolumeTotal: Double
    let workoutCount: Int
    let fastingHours: Double
    let hydrationOz: Double
    let learningMinutes: Int
    let dominantMascotState: String
    let masterMetric: Double
    let stepsHK: Int?
    let activeCaloriesHK: Double?
    let exerciseMinutesHK: Int?
    let sleepMinutesHK: Int?
    let hrvAvgHK: Double?
    let restingHRHK: Int?
}

struct DetectedPatternDTO: Codable {
    let detectedAt: Date
    let patternTypeRaw: String
    let confidence: Double
    let summary: String
    let detail: String
    let actionableSuggestion: String?
    let dismissed: Bool
    let snoozedUntil: Date?
}

struct PrescribedWorkoutDTO: Codable {
    let generatedAt: Date
    let forDate: Date
    let workoutTypeRaw: String
    let template: String
    let rationale: String
    let statusRaw: String
    let sessionUUIDString: String?
    let tokenUsage: Int
    let modelUsed: String
}

struct ScheduleSuggestionDTO: Codable {
    let generatedAt: Date
    let summary: String
    let detail: String
    let changeTypeRaw: String
    let changePayload: String
    let statusRaw: String
    let rationaleData: String
    let snoozedUntil: Date?
}

struct WeeklyProgramDTO: Codable {
    let weekStartDate: Date
    let generatedAt: Date
    let programJSON: String
    let coachNarrative: String
    let statusRaw: String
    let tokenUsage: Int
    let modelUsed: String
}

// MARK: - Mappers (model -> DTO)

extension UserProfileDTO {
    init(_ m: UserProfile) {
        self.init(
            name: m.name, dob: m.dob, sex: m.sex,
            heightInches: m.heightInches, weightLbs: m.weightLbs,
            timezone: m.timezone,
            fastWindowStartHour: m.fastWindowStartHour, fastWindowEndHour: m.fastWindowEndHour,
            bottleSizeOz: m.bottleSizeOz, anthropicModel: m.anthropicModel,
            rolloutPhase: m.rolloutPhase, notificationBundling: m.notificationBundling,
            mascotEnabled: m.mascotEnabled, reducedMotion: m.reducedMotion,
            mascotVariant: m.mascotVariant,
            primaryGoal: m.primaryGoal,
            secondaryGoalsCSV: m.secondaryGoalsCSV,
            equipmentAccess: m.equipmentAccess,
            weeklyTrainingTargetSessions: m.weeklyTrainingTargetSessions,
            restrictionsCSV: m.restrictionsCSV
        )
    }
}

extension ScheduleBlockDTO {
    init(_ m: ScheduleBlock) {
        self.init(
            dayOfWeek: m.dayOfWeek, startTime: m.startTime, endTime: m.endTime,
            activity: m.activity, typeRaw: m.typeRaw, module: m.module,
            isOverride: m.isOverride, overrideDate: m.overrideDate
        )
    }
}

extension DailyLogDTO {
    init(_ m: DailyLog) {
        self.init(
            date: m.date, fastStart: m.fastStart, fastEnd: m.fastEnd,
            fastBrokeEarly: m.fastBrokeEarly, fastBreakReason: m.fastBreakReason,
            waterOz: m.waterOz, electrolyteSessions: m.electrolyteSessions,
            japaneseMinutes: m.japaneseMinutes, guitarMinutes: m.guitarMinutes,
            courseworkMinutes: m.courseworkMinutes,
            subjectiveEnergy: m.subjectiveEnergy, achillesPain: m.achillesPain,
            sleepHours: m.sleepHours, restingHR: m.restingHR, hrvRmssd: m.hrvRmssd,
            weightLbs: m.weightLbs, notes: m.notes
        )
    }
}

extension LiftSetDTO {
    init(_ m: LiftSet) {
        self.init(weightLbs: m.weightLbs, reps: m.reps, restSeconds: m.restSeconds, orderIndex: m.orderIndex)
    }
}

extension LiftExerciseDTO {
    init(_ m: LiftExercise) {
        self.init(
            name: m.name, orderIndex: m.orderIndex,
            sets: (m.sets ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }).map(LiftSetDTO.init),
            rpe: m.rpe
        )
    }
}

extension LiftSessionDTO {
    init(_ m: LiftSession) {
        self.init(
            date: m.date, template: m.template,
            exercises: (m.exercises ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }).map(LiftExerciseDTO.init),
            totalVolumeLbs: m.totalVolumeLbs, durationMinutes: m.durationMinutes,
            avgHR: m.avgHR, notes: m.notes
        )
    }
}

extension BasketballSessionDTO {
    init(_ m: BasketballSession) {
        self.init(
            date: m.date, startTime: m.startTime, endTime: m.endTime,
            avgHR: m.avgHR, maxHR: m.maxHR, hrZoneMinutes: m.hrZoneMinutes,
            hydrationOz: m.hydrationOz, achillesPostScore: m.achillesPostScore, notes: m.notes
        )
    }
}

extension SwimSessionDTO {
    init(_ m: SwimSession) {
        self.init(
            date: m.date, poolLengthMeters: m.poolLengthMeters,
            laps: m.laps, totalMeters: m.totalMeters,
            durationMinutes: m.durationMinutes, avgHR: m.avgHR, location: m.location
        )
    }
}

extension LabDrawDTO {
    init(_ m: LabDraw) {
        self.init(date: m.date, notes: m.notes, values: m.values, sourcePdfFilename: m.sourcePdfFilename)
    }
}

extension WearableEntryDTO {
    init(_ m: WearableEntry) {
        self.init(date: m.date, source: m.source, metrics: m.metrics, notes: m.notes)
    }
}

extension ProtocolEntryDTO {
    init(_ m: ProtocolEntry) {
        self.init(
            date: m.date, category: m.category, title: m.title,
            notes: m.notes, dose: m.dose, retestDate: m.retestDate,
            completed: m.completed, completedAt: m.completedAt
        )
    }
}

extension PomodoroSessionDTO {
    init(_ m: PomodoroSession) {
        self.init(
            date: m.date, courseTag: m.courseTag,
            workMinutes: m.workMinutes, breakMinutes: m.breakMinutes,
            completedCycles: m.completedCycles, notes: m.notes
        )
    }
}

extension AdminTaskDTO {
    init(_ m: AdminTask) {
        self.init(
            title: m.title, category: m.category, dueDate: m.dueDate,
            completed: m.completed, completedAt: m.completedAt, notes: m.notes,
            createdAt: m.createdAt
        )
    }
}

extension LearningStreakDTO {
    init(_ m: LearningStreak) {
        self.init(
            module: m.module, currentStreak: m.currentStreak, longestStreak: m.longestStreak,
            lastCompletedDate: m.lastCompletedDate, totalMinutesAllTime: m.totalMinutesAllTime
        )
    }
}

extension CharacterStateLogDTO {
    init(_ m: CharacterStateLog) {
        self.init(
            timestamp: m.timestamp, stateRaw: m.stateRaw,
            triggerReason: m.triggerReason, durationSeconds: m.durationSeconds
        )
    }
}

extension ActivityArchiveDTO {
    init(_ m: ActivityArchive) {
        self.init(
            date: m.date,
            workoutVolumeTotal: m.workoutVolumeTotal,
            workoutCount: m.workoutCount,
            fastingHours: m.fastingHours,
            hydrationOz: m.hydrationOz,
            learningMinutes: m.learningMinutes,
            dominantMascotState: m.dominantMascotState,
            masterMetric: m.masterMetric,
            stepsHK: m.stepsHK,
            activeCaloriesHK: m.activeCaloriesHK,
            exerciseMinutesHK: m.exerciseMinutesHK,
            sleepMinutesHK: m.sleepMinutesHK,
            hrvAvgHK: m.hrvAvgHK,
            restingHRHK: m.restingHRHK
        )
    }
}

extension DetectedPatternDTO {
    init(_ m: DetectedPattern) {
        self.init(
            detectedAt: m.detectedAt,
            patternTypeRaw: m.patternTypeRaw,
            confidence: m.confidence,
            summary: m.summary,
            detail: m.detail,
            actionableSuggestion: m.actionableSuggestion,
            dismissed: m.dismissed,
            snoozedUntil: m.snoozedUntil
        )
    }
}

extension PrescribedWorkoutDTO {
    init(_ m: PrescribedWorkout) {
        self.init(
            generatedAt: m.generatedAt,
            forDate: m.forDate,
            workoutTypeRaw: m.workoutTypeRaw,
            template: m.template,
            rationale: m.rationale,
            statusRaw: m.statusRaw,
            sessionUUIDString: m.sessionUUIDString,
            tokenUsage: m.tokenUsage,
            modelUsed: m.modelUsed
        )
    }
}

extension ScheduleSuggestionDTO {
    init(_ m: ScheduleSuggestion) {
        self.init(
            generatedAt: m.generatedAt,
            summary: m.summary,
            detail: m.detail,
            changeTypeRaw: m.changeTypeRaw,
            changePayload: m.changePayload,
            statusRaw: m.statusRaw,
            rationaleData: m.rationaleData,
            snoozedUntil: m.snoozedUntil
        )
    }
}

extension WeeklyProgramDTO {
    init(_ m: WeeklyProgram) {
        self.init(
            weekStartDate: m.weekStartDate,
            generatedAt: m.generatedAt,
            programJSON: m.programJSON,
            coachNarrative: m.coachNarrative,
            statusRaw: m.statusRaw,
            tokenUsage: m.tokenUsage,
            modelUsed: m.modelUsed
        )
    }
}

// MARK: - Service

@MainActor
enum JSONExportService {

    /// Encodes the full SwiftData store (excluding Keychain items and external files)
    /// into a versioned JSON payload per SECURITY.md.
    /// Version 2 (M3.7) adds ActivityArchive, DetectedPattern, PrescribedWorkout,
    /// ScheduleSuggestion, WeeklyProgram, plus expanded UserProfile fields.
    static func export(modelContext: ModelContext, exportedAt: Date = Date()) throws -> Data {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let scheduleBlocks = try modelContext.fetch(FetchDescriptor<ScheduleBlock>())
        let dailyLogs = try modelContext.fetch(FetchDescriptor<DailyLog>())
        let liftSessions = try modelContext.fetch(FetchDescriptor<LiftSession>())
        let basketball = try modelContext.fetch(FetchDescriptor<BasketballSession>())
        let swims = try modelContext.fetch(FetchDescriptor<SwimSession>())
        let labs = try modelContext.fetch(FetchDescriptor<LabDraw>())
        let wearables = try modelContext.fetch(FetchDescriptor<WearableEntry>())
        let protocols = try modelContext.fetch(FetchDescriptor<ProtocolEntry>())
        let pomodoros = try modelContext.fetch(FetchDescriptor<PomodoroSession>())
        let admins = try modelContext.fetch(FetchDescriptor<AdminTask>())
        let streaks = try modelContext.fetch(FetchDescriptor<LearningStreak>())
        let characterLogs = try modelContext.fetch(FetchDescriptor<CharacterStateLog>())
        let archives = try modelContext.fetch(FetchDescriptor<ActivityArchive>())
        let patterns = try modelContext.fetch(FetchDescriptor<DetectedPattern>())
        let prescribed = try modelContext.fetch(FetchDescriptor<PrescribedWorkout>())
        let suggestions = try modelContext.fetch(FetchDescriptor<ScheduleSuggestion>())
        let weeklyPrograms = try modelContext.fetch(FetchDescriptor<WeeklyProgram>())

        let payload = ExportPayload(
            version: 2,
            exportedAt: exportedAt,
            userProfile: profiles.first.map(UserProfileDTO.init),
            scheduleBlocks: scheduleBlocks.map(ScheduleBlockDTO.init),
            dailyLogs: dailyLogs.map(DailyLogDTO.init),
            liftSessions: liftSessions.map(LiftSessionDTO.init),
            basketballSessions: basketball.map(BasketballSessionDTO.init),
            swimSessions: swims.map(SwimSessionDTO.init),
            labDraws: labs.map(LabDrawDTO.init),
            wearableEntries: wearables.map(WearableEntryDTO.init),
            protocolEntries: protocols.map(ProtocolEntryDTO.init),
            pomodoroSessions: pomodoros.map(PomodoroSessionDTO.init),
            adminTasks: admins.map(AdminTaskDTO.init),
            learningStreaks: streaks.map(LearningStreakDTO.init),
            characterStateLogs: characterLogs.map(CharacterStateLogDTO.init),
            activityArchives: archives.map(ActivityArchiveDTO.init),
            detectedPatterns: patterns.map(DetectedPatternDTO.init),
            prescribedWorkouts: prescribed.map(PrescribedWorkoutDTO.init),
            scheduleSuggestions: suggestions.map(ScheduleSuggestionDTO.init),
            weeklyPrograms: weeklyPrograms.map(WeeklyProgramDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
