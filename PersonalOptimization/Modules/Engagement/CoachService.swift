import Foundation
import SwiftData
import os

/// Aggregated context handed to the Claude system prompt to generate today's insight.
/// Pure value type so tests can construct deterministic snapshots without persistence.
struct CoachContext: Sendable {
    var protocolAdherenceText: String       // e.g. "3/4 of today's protocol complete"
    var workoutStreakDays: Int
    var hydrationStreakDays: Int
    var fastingStreakDays: Int
    var learningStreakDays: Int
    var fastingActive: Bool
    var lastFastEndedAgoHours: Double?
    var hydrationOzToday: Double
    var hydrationTargetMin: Double
    var sevenDayWorkoutCount: Int
    var liftPRSetToday: Bool
    var swimPRSetToday: Bool
    var basketballAchillesScore: Int?
    var sleepHoursLastNight: Double?
    var restingHRToday: Int?
    var hrvRmssdToday: Double?
    var stepsToday: Int?
    var mascotState: String
    var motivationStyle: String
    var customStylePrompt: String?

    // M4.2 — HealthKit-derived signals from DailyLog. Only the day-to-day
    // high-signal fields are surfaced to Claude; slow trends (body fat,
    // wrist temperature) belong in TrendAnalyticsService aggregates.
    var heartRateRecovery1minBpm: Int?
    var respiratoryRateToday: Double?
    var mindfulMinutesToday: Int?
    var dietaryKcalToday: Double?
    var caffeineMgToday: Double?
    var timeInDaylightMinutesToday: Int?
    var appleExerciseMinutesToday: Int?
    var bodyFatPercentage: Double?
    var optimizationFocuses: [String]

    /// Compact, deterministic dump used as the user content of the Claude API call,
    /// and persisted alongside the insight for debugging/audit.
    var summaryForPrompt: String {
        var lines: [String] = []
        lines.append("Today: \(protocolAdherenceText).")
        lines.append("Streaks: workout \(workoutStreakDays)d, hydration \(hydrationStreakDays)d, fasting \(fastingStreakDays)d, learning \(learningStreakDays)d.")
        lines.append("Fasting: \(fastingActive ? "in fast window" : (lastFastEndedAgoHours.map { "broke fast \(Int($0))h ago" } ?? "no recent fast")).")
        lines.append("Hydration today: \(Int(hydrationOzToday))/\(Int(hydrationTargetMin)) oz minimum.")
        lines.append("Last 7d workouts: \(sevenDayWorkoutCount).")
        if liftPRSetToday { lines.append("Lift PR set today.") }
        if swimPRSetToday { lines.append("Swim PR set today.") }
        if let achilles = basketballAchillesScore { lines.append("Latest Achilles pain: \(achilles)/10.") }
        if let sleep = sleepHoursLastNight { lines.append("Sleep last night: \(String(format: "%.1f", sleep))h.") }
        if let hr = restingHRToday { lines.append("Resting HR: \(hr) bpm.") }
        if let hrv = hrvRmssdToday { lines.append("HRV (RMSSD): \(String(format: "%.0f", hrv)).") }
        if let steps = stepsToday { lines.append("Steps today: \(steps).") }

        // M4.2 — HealthKit-derived signals, surfaced only when present.
        if let recovery = heartRateRecovery1minBpm {
            lines.append("HR recovery (1 min): \(recovery) bpm.")
        }
        if let rr = respiratoryRateToday {
            lines.append("Respiratory rate: \(String(format: "%.1f", rr))/min.")
        }
        if let exercise = appleExerciseMinutesToday {
            lines.append("Apple exercise minutes today: \(exercise).")
        }
        if let mindful = mindfulMinutesToday, mindful > 0 {
            lines.append("Mindful minutes today: \(mindful).")
        }
        if let kcal = dietaryKcalToday {
            lines.append("Dietary kcal today: \(Int(kcal)).")
        }
        if let caffeine = caffeineMgToday, caffeine > 0 {
            lines.append("Caffeine today: \(Int(caffeine)) mg.")
        }
        if let daylight = timeInDaylightMinutesToday {
            lines.append("Time in daylight today: \(daylight) min.")
        }
        if let bf = bodyFatPercentage {
            lines.append("Body fat: \(String(format: "%.1f", bf))%.")
        }
        if !optimizationFocuses.isEmpty {
            lines.append("Optimization focuses: \(optimizationFocuses.joined(separator: ", ")).")
        }

        lines.append("Mascot state: \(mascotState).")
        return lines.joined(separator: "\n")
    }
}

enum CoachServiceError: LocalizedError {
    case missingAPIKey
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Anthropic API key is not set. Add it in Settings."
        case .generationFailed(let underlying): return "Coach insight failed: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class CoachService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let api: CoachAPIInvoking
    private let now: () -> Date
    private let logger = Logger.coach

    /// One day in seconds. Cache TTL.
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current,
         api: CoachAPIInvoking = LiveCoachAPI(),
         now: @escaping () -> Date = Date.init) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.api = api
        self.now = now
    }

    /// Returns a cached insight if one exists in the last 24h. Otherwise hits the
    /// Claude API and persists the result. Returns CoachInsight without throwing
    /// on cache hit; on API failure throws CoachServiceError.
    func todayInsight() async throws -> CoachInsight {
        if let cached = mostRecentInsight(), now().timeIntervalSince(cached.generatedAt) < cacheTTL {
            return cached
        }
        return try await generateAndPersist(refresh: false)
    }

    // MARK: - Coach v2 (M3.7)

    /// Builds the full v2 context (M3.6 today snapshot + historical summary + goals
    /// + equipment + restrictions + minutes-available + temperature stub).
    func gatherFullContext(profile: UserProfile,
                           historicalRange: DateRange? = nil) -> CoachContextV2 {
        let today = gatherContext(profile: profile)
        let range = historicalRange ?? DateRange.lastNDays(30, asOf: now(), timezone: timezone)
        let trends = TrendAnalyticsService(
            modelContext: modelContext,
            timezone: timezone,
            hydrationTargets: try? ScheduleConfigLoader.load().hydrationTargetsOz
        )
        let historical = trends.summaryForCoach(over: range)

        let secondary = profile.secondaryGoalsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let restrictions = profile.restrictionsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let memoryService = CoachMemoryService(modelContext: modelContext)
        let userMemoryBlock = memoryService.summaryForCoach()
        let recentInsightsBlock = recentInsightsSummary()
        let lapseNote = lapseStateNote()
        let recoveryNote = recoveryStateNote(profile: profile)
        let personaBlock = PersonaService(modelContext: modelContext).promptContextBlock()

        return CoachContextV2(
            today: today,
            historical: historical,
            primaryGoal: profile.primaryGoal,
            secondaryGoals: secondary,
            equipmentAccess: profile.equipmentAccess,
            weeklyTrainingTargetSessions: profile.weeklyTrainingTargetSessions,
            restrictions: restrictions,
            minutesAvailableToday: minutesAvailableToday(),
            temperatureF: nil,
            userMemoryBlock: userMemoryBlock,
            recentInsightsBlock: recentInsightsBlock,
            lapseStateNote: lapseNote,
            recoveryNote: recoveryNote,
            personaBlock: personaBlock
        )
    }

    /// Pulls the 3 most recent persisted CoachInsight rows and compresses
    /// each into a one-line bullet so the Coach prompt can reference them.
    /// Empty when there's no history yet.
    private func recentInsightsSummary() -> String {
        var descriptor = FetchDescriptor<CoachInsight>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return rows.reversed().map { insight in
            let date = formatter.string(from: insight.generatedAt)
            // Keep each bullet under ~140 chars to avoid blowing the prompt.
            let trimmed = String(insight.insightText.prefix(140))
            return "- (\(date)) \(trimmed)"
        }.joined(separator: "\n")
    }

    /// Composes a short note about today's lapse status, if any, so the
    /// Coach can warm the message rather than scolding a returning user.
    private func lapseStateNote() -> String {
        let descriptor = FetchDescriptor<LapseEvent>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        guard let active = recent.first(where: { $0.resolvedAt == nil }) else { return "" }
        switch active.severity {
        case .soft:
            return "User just had a soft slip (2 days low). Welcome warmly; suggest one small win."
        case .hard:
            return "User is returning from a 5+ day lapse. Soften the message; celebrate showing up. No volume pressure."
        case .crisis:
            return "User has been low-engagement 14+ days. Ask, don't prescribe. Offer to simplify the schedule."
        }
    }

    /// Composes a recovery note when the RecoveryGate flagged a downgrade or
    /// rest day. Lets the prescribe/dailyInsight prompts honor recovery
    /// without each prompt re-deriving the rules.
    private func recoveryStateNote(profile: UserProfile) -> String {
        let gate = RecoveryGate(modelContext: modelContext)
        let status = gate.evaluate(profile: profile, asOf: now())
        switch status.recommendation {
        case .normal:
            return ""
        case .downgrade:
            return "Recovery flag: downgrade today. Reason: \(status.reason). Prescribe deload variant."
        case .rest:
            return "Recovery flag: rest day mandatory. Reason: \(status.reason). Honor the rest; prescribe rest as the work."
        }
    }

    /// Generates and persists today's PrescribedWorkout. Idempotent: a second call
    /// for the same day reuses the existing row in `.suggested` status. Manual
    /// re-prescription requires deleting the prior row (or using a new `forDate`).
    func prescribeTodaysWorkout(profile: UserProfile? = nil,
                                forceRefresh: Bool = false) async throws -> PrescribedWorkout {
        let resolvedProfile = profile ?? ensureProfile()
        let cal = jstCalendar()
        let today = cal.startOfDay(for: now())

        if !forceRefresh, let existing = existingPrescription(for: today) {
            return existing
        }

        let context = gatherFullContext(profile: resolvedProfile)
        let systemPrompt = CoachPrompts.system(
            for: .prescribeWorkout,
            style: resolvedProfile.motivationStyle,
            customStylePrompt: resolvedProfile.customStylePrompt
        )
        let response: ClaudeAPIClient.Response
        do {
            response = try await api.complete(
                model: resolvedProfile.anthropicModel,
                systemPrompt: systemPrompt,
                userPrompt: context.summaryForPrompt,
                maxTokens: CoachPrompts.defaultMaxTokens(for: .prescribeWorkout)
            )
        } catch ClaudeAPIError.missingAPIKey {
            throw CoachServiceError.missingAPIKey
        } catch {
            throw CoachServiceError.generationFailed(error)
        }

        let parsed = parsePrescription(jsonText: response.text)
        let prescription = upsertPrescription(for: today)
        prescription.generatedAt = now()
        prescription.workoutTypeRaw = parsed.workoutType.rawValue
        prescription.template = parsed.templateJSON
        prescription.rationale = parsed.rationale
        prescription.creativeTitle = parsed.creativeTitle
        prescription.statusRaw = PrescribedWorkoutStatus.suggested.rawValue
        prescription.tokenUsage = response.totalTokens
        prescription.modelUsed = resolvedProfile.anthropicModel
        try? modelContext.save()
        logger.info("Prescription generated type=\(parsed.workoutType.rawValue, privacy: .public) tokens=\(response.totalTokens, privacy: .public)")
        return prescription
    }

    /// Generates 0-1 ScheduleSuggestion rows based on detected patterns. Returns the
    /// rows persisted this call. Skips API call entirely when no patterns clear the
    /// confidence threshold (saves cost on quiet weeks).
    func suggestScheduleOptimizations(profile: UserProfile? = nil,
                                      lookbackDays: Int = 30) async throws -> [ScheduleSuggestion] {
        let resolvedProfile = profile ?? ensureProfile()
        let range = DateRange.lastNDays(lookbackDays, asOf: now(), timezone: timezone)
        let trends = TrendAnalyticsService(
            modelContext: modelContext,
            timezone: timezone,
            hydrationTargets: try? ScheduleConfigLoader.load().hydrationTargetsOz
        )
        let patterns = trends.patternsDetected(over: range, minConfidence: 0.5)
        guard !patterns.isEmpty else {
            logger.info("Schedule suggestions skipped — no patterns above threshold")
            return []
        }

        let context = gatherFullContext(profile: resolvedProfile, historicalRange: range)
        let patternsBlock = patterns.prefix(3).map {
            "- [\($0.patternType.rawValue) conf=\(String(format: "%.2f", $0.confidence))] \($0.summary)"
        }.joined(separator: "\n")

        // M4.1: feed rejected-proposal memory into the prompt so the same
        // bad suggestion never re-surfaces. CoachMemoryService auto-prunes
        // expired rows on read; empty list yields an empty rejection block.
        let memoryService = CoachMemoryService(modelContext: modelContext)
        let rejected = memoryService.active(asOf: now())
            .filter { $0.key.hasPrefix("rejected_suggestion_") }
            .prefix(8)
            .map { "- \($0.value)" }
            .joined(separator: "\n")
        let rejectedBlock: String
        if rejected.isEmpty {
            rejectedBlock = ""
        } else {
            rejectedBlock = "\n\n=== Previously rejected (do not repeat) ===\n\(rejected)"
        }

        let userPrompt = """
        \(context.summaryForPrompt)

        === Detected patterns ===
        \(patternsBlock)\(rejectedBlock)
        """

        let systemPrompt = CoachPrompts.system(
            for: .suggestSchedule,
            style: resolvedProfile.motivationStyle,
            customStylePrompt: resolvedProfile.customStylePrompt
        )
        let response: ClaudeAPIClient.Response
        do {
            response = try await api.complete(
                model: resolvedProfile.anthropicModel,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: CoachPrompts.defaultMaxTokens(for: .suggestSchedule)
            )
        } catch ClaudeAPIError.missingAPIKey {
            throw CoachServiceError.missingAPIKey
        } catch {
            throw CoachServiceError.generationFailed(error)
        }

        let parsed = parseSuggestion(jsonText: response.text)
        guard let parsed else {
            logger.warning("Schedule suggestion parse failed; skipping persistence")
            return []
        }
        let rationaleData = patterns.prefix(3).map { "\($0.patternType.rawValue):\(String(format: "%.2f", $0.confidence))" }.joined(separator: ",")
        let suggestion = ScheduleSuggestion(
            generatedAt: now(),
            summary: parsed.summary,
            detail: parsed.detail,
            changeType: parsed.changeType,
            changePayload: parsed.changePayloadJSON,
            rationaleData: rationaleData
        )
        modelContext.insert(suggestion)
        try? modelContext.save()
        logger.info("Schedule suggestion persisted change=\(parsed.changeType.rawValue, privacy: .public) tokens=\(response.totalTokens, privacy: .public)")
        return [suggestion]
    }

    /// Generates a WeeklyProgram for the upcoming week. Idempotent per
    /// `weekStartDate` (Monday of next week, or current week if today is Monday).
    func generateWeeklyProgrammingPass(profile: UserProfile? = nil,
                                       forceRefresh: Bool = false) async throws -> WeeklyProgram {
        let resolvedProfile = profile ?? ensureProfile()
        let weekStart = mondayOfThisWeek()

        if !forceRefresh, let existing = existingWeeklyProgram(weekStart: weekStart) {
            return existing
        }

        let context = gatherFullContext(profile: resolvedProfile)
        let systemPrompt = CoachPrompts.system(
            for: .weeklyProgram,
            style: resolvedProfile.motivationStyle,
            customStylePrompt: resolvedProfile.customStylePrompt
        )
        let response: ClaudeAPIClient.Response
        do {
            response = try await api.complete(
                model: resolvedProfile.anthropicModel,
                systemPrompt: systemPrompt,
                userPrompt: context.summaryForPrompt,
                maxTokens: CoachPrompts.defaultMaxTokens(for: .weeklyProgram)
            )
        } catch ClaudeAPIError.missingAPIKey {
            throw CoachServiceError.missingAPIKey
        } catch {
            throw CoachServiceError.generationFailed(error)
        }

        let parsed = parseWeeklyProgram(jsonText: response.text)
        let program = upsertWeeklyProgram(weekStart: weekStart)
        program.generatedAt = now()
        program.programJSON = parsed.programJSON
        program.coachNarrative = parsed.narrative
        program.statusRaw = WeeklyProgramStatus.active.rawValue
        program.tokenUsage = response.totalTokens
        program.modelUsed = resolvedProfile.anthropicModel
        try? modelContext.save()
        logger.info("Weekly program generated weekStart=\(weekStart, privacy: .public) tokens=\(response.totalTokens, privacy: .public)")
        return program
    }

    /// Today's prescription if one exists (any status). Used by TrainView to render
    /// the prescribed-workout card.
    func todaysPrescription() -> PrescribedWorkout? {
        existingPrescription(for: jstCalendar().startOfDay(for: now()))
    }

    /// Pending schedule suggestions (status == .pending), newest first.
    func pendingScheduleSuggestions(limit: Int = 5) -> [ScheduleSuggestion] {
        var descriptor = FetchDescriptor<ScheduleSuggestion>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 4
        let pendingRaw = ScheduleSuggestionStatus.pending.rawValue
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Array(all.filter { $0.statusRaw == pendingRaw }.prefix(limit))
    }

    /// Active weekly program for the current week, if any.
    func activeWeeklyProgram() -> WeeklyProgram? {
        existingWeeklyProgram(weekStart: mondayOfThisWeek())
    }

    // MARK: - Internal helpers (v2)

    private func minutesAvailableToday() -> Int {
        // Naive heuristic: total minutes of un-blocked time between 06:00 and 22:00,
        // i.e. (16h * 60) minus sum of training/study block durations from today.
        let weekday = isoWeekday(for: now())
        let blocks = ((try? modelContext.fetch(FetchDescriptor<ScheduleBlock>())) ?? [])
            .filter { $0.dayOfWeek == weekday && !$0.isOverride }
        let blocked = blocks.reduce(0) { acc, block in
            guard let s = ScheduleService.parseTimeToMinutes(block.startTime),
                  let e = ScheduleService.parseTimeToMinutes(block.endTime) else { return acc }
            return acc + max(0, e - s)
        }
        let waking = 16 * 60
        return max(0, waking - blocked)
    }

    private func existingPrescription(for day: Date) -> PrescribedWorkout? {
        let descriptor = FetchDescriptor<PrescribedWorkout>(
            predicate: #Predicate<PrescribedWorkout> { $0.forDate == day }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func upsertPrescription(for day: Date) -> PrescribedWorkout {
        if let existing = existingPrescription(for: day) { return existing }
        let new = PrescribedWorkout(generatedAt: now(), forDate: day, workoutType: .rest)
        modelContext.insert(new)
        return new
    }

    private func existingWeeklyProgram(weekStart: Date) -> WeeklyProgram? {
        let descriptor = FetchDescriptor<WeeklyProgram>(
            predicate: #Predicate<WeeklyProgram> { $0.weekStartDate == weekStart }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func upsertWeeklyProgram(weekStart: Date) -> WeeklyProgram {
        if let existing = existingWeeklyProgram(weekStart: weekStart) { return existing }
        let new = WeeklyProgram(weekStartDate: weekStart, generatedAt: now())
        modelContext.insert(new)
        return new
    }

    private func mondayOfThisWeek() -> Date {
        let cal = jstCalendar()
        let today = cal.startOfDay(for: now())
        let weekday = isoWeekday(for: today)
        let delta = -(weekday - 1)
        return cal.date(byAdding: .day, value: delta, to: today) ?? today
    }

    private func isoWeekday(for date: Date) -> Int {
        let raw = jstCalendar().component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    // MARK: - JSON parsing (Coach v2 outputs)

    private struct ParsedPrescription {
        var workoutType: PrescribedWorkoutType
        var templateJSON: String
        var rationale: String
        var creativeTitle: String
    }

    private struct ParsedSuggestion {
        var summary: String
        var detail: String
        var changeType: ScheduleSuggestionChangeType
        var changePayloadJSON: String
    }

    private struct ParsedWeeklyProgram {
        var narrative: String
        var programJSON: String
    }

    private func parsePrescription(jsonText: String) -> ParsedPrescription {
        let cleaned = stripCodeFences(jsonText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedPrescription(
                workoutType: .rest,
                templateJSON: "{}",
                rationale: jsonText.trimmingCharacters(in: .whitespacesAndNewlines),
                creativeTitle: ""
            )
        }
        let typeRaw = (obj["workoutType"] as? String) ?? "rest"
        let workoutType = PrescribedWorkoutType(rawValue: typeRaw) ?? .rest
        let rationale = (obj["rationale"] as? String) ?? ""
        let title = (obj["creativeTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var templateJSON = "{}"
        if let template = obj["template"], let templateData = try? JSONSerialization.data(withJSONObject: template),
           let templateString = String(data: templateData, encoding: .utf8) {
            templateJSON = templateString
        }
        return ParsedPrescription(
            workoutType: workoutType,
            templateJSON: templateJSON,
            rationale: rationale,
            creativeTitle: title
        )
    }

    private func parseSuggestion(jsonText: String) -> ParsedSuggestion? {
        let cleaned = stripCodeFences(jsonText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = obj["summary"] as? String,
              let detail = obj["detail"] as? String,
              let typeRaw = obj["changeType"] as? String else {
            return nil
        }
        let changeType: ScheduleSuggestionChangeType = {
            switch typeRaw {
            case "shift_block": return .shiftBlock
            case "add_block":   return .addBlock
            case "remove_block": return .removeBlock
            case "merge":        return .mergeBlocks
            case "split":        return .splitBlock
            default:             return .shiftBlock
            }
        }()
        var payloadJSON = "{}"
        if let payload = obj["changePayload"],
           let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            payloadJSON = payloadString
        }
        return ParsedSuggestion(
            summary: summary,
            detail: detail,
            changeType: changeType,
            changePayloadJSON: payloadJSON
        )
    }

    private func parseWeeklyProgram(jsonText: String) -> ParsedWeeklyProgram {
        let cleaned = stripCodeFences(jsonText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedWeeklyProgram(
                narrative: jsonText.trimmingCharacters(in: .whitespacesAndNewlines),
                programJSON: "{}"
            )
        }
        let narrative = (obj["narrative"] as? String) ?? ""
        var programJSON = "{}"
        if let days = obj["days"],
           let daysData = try? JSONSerialization.data(withJSONObject: days),
           let daysString = String(data: daysData, encoding: .utf8) {
            programJSON = daysString
        }
        return ParsedWeeklyProgram(narrative: narrative, programJSON: programJSON)
    }

    private func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fenceLeading = "```json"
        let fenceLeading2 = "```"
        if s.hasPrefix(fenceLeading) { s = String(s.dropFirst(fenceLeading.count)) }
        else if s.hasPrefix(fenceLeading2) { s = String(s.dropFirst(fenceLeading2.count)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Forces a fresh API call, increments refreshCount on the existing cached row
    /// (or creates a new one if none yet today).
    func refresh() async throws -> CoachInsight {
        return try await generateAndPersist(refresh: true)
    }

    /// The latest cached insight if any, regardless of age. Used by views to render
    /// stale content with a "last updated X hours ago" hint while a refresh runs.
    func cachedInsight() -> CoachInsight? {
        mostRecentInsight()
    }

    // MARK: - Internals

    private func generateAndPersist(refresh: Bool) async throws -> CoachInsight {
        let profile = ensureProfile()
        let context = gatherContext(profile: profile)
        let style = profile.motivationStyle
        let customStylePrompt = profile.customStylePrompt
        let model = profile.anthropicModel
        let systemPrompt = Self.systemPrompt(style: style, customStylePrompt: customStylePrompt)

        let response: ClaudeAPIClient.Response
        do {
            response = try await api.complete(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: context.summaryForPrompt,
                maxTokens: 256
            )
        } catch ClaudeAPIError.missingAPIKey {
            throw CoachServiceError.missingAPIKey
        } catch {
            throw CoachServiceError.generationFailed(error)
        }

        let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let cal = jstCalendar()
        let today = cal.startOfDay(for: now())
        if refresh, let existing = mostRecentInsight(), cal.isDate(existing.generatedAt, inSameDayAs: today) {
            existing.generatedAt = now()
            existing.insightText = trimmed
            existing.contextSummary = context.summaryForPrompt
            existing.tokenUsage = response.totalTokens
            existing.refreshCount += 1
            try? modelContext.save()
            logger.info("Coach insight refreshed; tokens=\(response.totalTokens, privacy: .public) refreshCount=\(existing.refreshCount, privacy: .public)")
            return existing
        }

        let insight = CoachInsight(
            generatedAt: now(),
            insightText: trimmed,
            contextSummary: context.summaryForPrompt,
            tokenUsage: response.totalTokens,
            refreshCount: 0
        )
        modelContext.insert(insight)
        try? modelContext.save()
        logger.info("Coach insight generated; tokens=\(response.totalTokens, privacy: .public)")
        return insight
    }

    private func mostRecentInsight() -> CoachInsight? {
        var descriptor = FetchDescriptor<CoachInsight>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func gatherContext(profile: UserProfile) -> CoachContext {
        let cal = jstCalendar()
        let asOf = now()
        let today = cal.startOfDay(for: asOf)

        let summary = DailySummaryService(modelContext: modelContext).todayProtocol(asOf: asOf)
        let counters = (try? modelContext.fetch(FetchDescriptor<StreakCounter>())) ?? []
        let workout = counters.first { $0.domain == StreakDomain.workout.rawValue }?.currentStreak ?? 0
        let hydration = counters.first { $0.domain == StreakDomain.hydration.rawValue }?.currentStreak ?? 0
        let fasting = counters.first { $0.domain == StreakDomain.fasting.rawValue }?.currentStreak ?? 0
        let learning = counters.first { $0.domain == StreakDomain.learning.rawValue }?.currentStreak ?? 0

        let todayLog = (try? modelContext.fetch(FetchDescriptor<DailyLog>()))?.first {
            cal.isDate($0.date, inSameDayAs: today)
        }

        let nowMin = (cal.component(.hour, from: asOf)) * 60 + cal.component(.minute, from: asOf)
        let startMin = profile.fastWindowStartHour * 60
        let endMin = profile.fastWindowEndHour * 60
        let inFast: Bool = {
            if startMin > endMin {
                return nowMin >= startMin || nowMin < endMin
            }
            return nowMin >= startMin && nowMin < endMin
        }()
        let lastFastEnded: Double? = {
            guard let end = todayLog?.fastEnd else { return nil }
            return asOf.timeIntervalSince(end) / 3600
        }()

        let workoutEvents = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let recentWorkouts = workoutEvents.filter { $0.completed && $0.date >= weekAgo }.count

        let liftSessions = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let todaysLifts = liftSessions.filter { cal.isDate($0.date, inSameDayAs: today) }
        let priorMaxLiftVolume = liftSessions.filter { !cal.isDate($0.date, inSameDayAs: today) }
            .map { $0.totalVolumeLbs }.max() ?? 0
        let liftPR = !todaysLifts.isEmpty
            && (todaysLifts.map { $0.totalVolumeLbs }.max() ?? 0) > priorMaxLiftVolume
            && priorMaxLiftVolume > 0

        let swimSessions = (try? modelContext.fetch(FetchDescriptor<SwimSession>())) ?? []
        let todaysSwims = swimSessions.filter { cal.isDate($0.date, inSameDayAs: today) }
        let priorMaxSwimDist = swimSessions.filter { !cal.isDate($0.date, inSameDayAs: today) }
            .map { $0.totalMeters }.max() ?? 0
        let swimPR = !todaysSwims.isEmpty
            && (todaysSwims.map { $0.totalMeters }.max() ?? 0) > priorMaxSwimDist
            && priorMaxSwimDist > 0

        let mascotState = CharacterStateService.shared.currentState.rawValue

        // Hydration target floor for today.
        let hydrationTargetMin: Double = (try? ScheduleConfigLoader.load().hydrationTargetsOz)
            .map { targets in
                let weekday: Int = {
                    let raw = cal.component(.weekday, from: asOf)
                    return raw == 1 ? 7 : raw - 1
                }()
                if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
                if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
                if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
                return targets.rest.min
            } ?? 64

        let focuses = [OptimizationFocus].fromCSV(profile.optimizationFocusesCSV)
            .map(\.displayName)
        return CoachContext(
            protocolAdherenceText: summary.displayText,
            workoutStreakDays: workout,
            hydrationStreakDays: hydration,
            fastingStreakDays: fasting,
            learningStreakDays: learning,
            fastingActive: inFast,
            lastFastEndedAgoHours: lastFastEnded,
            hydrationOzToday: todayLog?.waterOz ?? 0,
            hydrationTargetMin: hydrationTargetMin,
            sevenDayWorkoutCount: recentWorkouts,
            liftPRSetToday: liftPR,
            swimPRSetToday: swimPR,
            basketballAchillesScore: todayLog?.achillesPain,
            sleepHoursLastNight: todayLog?.sleepHours,
            restingHRToday: todayLog?.restingHR,
            hrvRmssdToday: todayLog?.hrvRmssd,
            stepsToday: todayLog?.stepCount,
            mascotState: mascotState,
            motivationStyle: profile.motivationStyle,
            customStylePrompt: profile.customStylePrompt,
            heartRateRecovery1minBpm: todayLog?.heartRateRecovery1minBpm,
            respiratoryRateToday: todayLog?.respiratoryRate,
            mindfulMinutesToday: todayLog?.mindfulMinutes,
            dietaryKcalToday: todayLog?.dietaryKcal,
            caffeineMgToday: todayLog?.caffeineMg,
            timeInDaylightMinutesToday: todayLog?.timeInDaylightMinutes,
            appleExerciseMinutesToday: todayLog?.appleExerciseMinutes,
            bodyFatPercentage: todayLog?.bodyFatPercentage,
            optimizationFocuses: focuses
        )
    }

    private func ensureProfile() -> UserProfile {
        if let existing = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let p = UserProfile()
        modelContext.insert(p)
        try? modelContext.save()
        return p
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    /// System prompt is locked per M3.6_SPEC. Style placeholder is filled from profile.
    static func systemPrompt(style: String, customStylePrompt: String?) -> String {
        let resolvedStyle: String = {
            if style == "custom", let custom = customStylePrompt, !custom.isEmpty {
                return "custom: \(custom)"
            }
            return style
        }()
        return """
        You are a holistic optimizer combining the perspectives of a strength coach,
        nutritionist, and life coach. Read the user's day-in-context and produce
        ONE concise insight (max 80 words).

        Style: \(resolvedStyle).

        Rules:
        - No filler. No motivational platitudes. No em dashes.
        - Anchor advice to specific data points from the context.
        - Identity framing: speak to who they are, not what they did.
        - One actionable nudge, max.
        - If their data shows they need rest, prescribe rest.
        """
    }
}

// MARK: - API protocol for tests

protocol CoachAPIInvoking: Sendable {
    func complete(model: String,
                  systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int) async throws -> ClaudeAPIClient.Response
}

struct LiveCoachAPI: CoachAPIInvoking {
    func complete(model: String,
                  systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        try await ClaudeAPIClient.shared.complete(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
    }
}
