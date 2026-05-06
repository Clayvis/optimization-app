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
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
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
            stepsToday: nil,
            mascotState: mascotState,
            motivationStyle: profile.motivationStyle,
            customStylePrompt: profile.customStylePrompt
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
