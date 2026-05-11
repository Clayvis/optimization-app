import Foundation
import SwiftData
import os

/// Owns the `UserPersona` entity: load/save, curated question library,
/// gap detection (what should we ask next?), and the prompt-context block
/// that the Coach injects into every generation call.
///
/// Throttle: at most one question card per week. The Settings questionnaire
/// view exposes the full library so users who want to fill it all in at once
/// can. The TodayView card is the slow-drip surface that fits the "coach who
/// learns you over time" feel.
@MainActor
final class PersonaService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.rawlins.PersonalOptimization", category: "persona")
    private let now: () -> Date

    init(modelContext: ModelContext, now: @escaping () -> Date = Date.init) {
        self.modelContext = modelContext
        self.now = now
    }

    // MARK: - Persona load/save

    /// Returns the current persona row, creating one if absent.
    @discardableResult
    func currentOrCreate() -> UserPersona {
        if let existing = (try? modelContext.fetch(FetchDescriptor<UserPersona>()))?.first {
            return existing
        }
        let new = UserPersona()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    /// Marks a question key as answered and bumps confidence.
    func recordAnswer(key: String) {
        let persona = currentOrCreate()
        var answered = persona.answeredQuestionKeysCSV
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        if !answered.contains(key) {
            answered.append(key)
            persona.answeredQuestionKeysCSV = answered.joined(separator: ",")
            persona.confidence = min(100, persona.confidence + 10)
        }
        try? modelContext.save()
    }

    /// True when at least 7 days have passed since the last question card and
    /// the persona still has gaps. Used by TodayView to decide whether to show
    /// the weekly card.
    func shouldShowWeeklyQuestion(asOf date: Date? = nil) -> Bool {
        let now = date ?? self.now()
        let persona = currentOrCreate()
        if persona.lastQuestionAskedAt == nil { return nextQuestion() != nil }
        guard let last = persona.lastQuestionAskedAt else { return true }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return last < weekAgo && nextQuestion() != nil
    }

    /// Returns the next unanswered question from the curated library, or nil if
    /// every question has been asked.
    func nextQuestion() -> PersonaQuestion? {
        let persona = currentOrCreate()
        let answered = Set(
            persona.answeredQuestionKeysCSV
                .split(separator: ",")
                .map(String.init)
        )
        return PersonaQuestion.library.first { !answered.contains($0.key) }
    }

    /// Marks the moment a question card was shown so the next-week throttle
    /// can count.
    func markQuestionAsked() {
        let persona = currentOrCreate()
        persona.lastQuestionAskedAt = now()
        try? modelContext.save()
    }

    // MARK: - Behavioral inference (v2 passive signals)

    /// Reads recent training, recovery, and suggestion data and returns
    /// persona-update proposals the user can accept or dismiss. Skips fields
    /// the user has already answered (active beats passive — their declared
    /// preference wins). Skips signals the user has previously dismissed
    /// (recorded in CoachMemory under `personaSignalDismissedKey`).
    ///
    /// Idempotent: calling repeatedly with the same data returns the same
    /// proposals, sorted by confidence descending.
    func inferFromBehavior(asOf date: Date? = nil) -> [PersonaBehavioralInference.PersonaSignal] {
        let asOf = date ?? now()
        let cal = Calendar.current
        let lookbackStart = cal.date(byAdding: .day, value: -60, to: asOf) ?? asOf

        let persona = currentOrCreate()
        let answered = Set(persona.answeredQuestionKeysCSV
            .split(separator: ",").map(String.init))
        let dismissed = dismissedSignalKeys()

        var signals: [PersonaBehavioralInference.PersonaSignal] = []

        // Peak alertness — only propose if not already declared.
        if !answered.contains("peak_alertness") {
            let liftStarts = recentLiftStarts(since: lookbackStart)
            if let s = PersonaBehavioralInference.inferPeakAlertness(from: liftStarts) {
                signals.append(s)
            }
        }

        // Recovery sensitivity.
        if !answered.contains("recovery_sensitivity") {
            let recoveryDays = recentRecoveryDays(from: lookbackStart, to: asOf)
            if let s = PersonaBehavioralInference.inferRecoverySensitivity(from: recoveryDays) {
                signals.append(s)
            }
        }

        // Failure response.
        if !answered.contains("failure_response") {
            let pairs = recentSkipPairs(since: lookbackStart, asOf: asOf)
            if let s = PersonaBehavioralInference.inferFailureResponse(from: pairs) {
                signals.append(s)
            }
        }

        // Decision style.
        if !answered.contains("decision_style") {
            let outcomes = suggestionOutcomes(since: lookbackStart)
            if let s = PersonaBehavioralInference.inferDecisionStyle(from: outcomes) {
                signals.append(s)
            }
        }

        return signals
            .filter { !dismissed.contains($0.key) }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Apply a behavior-derived signal: write the field, mark the question
    /// answered so the active-inference questionnaire skips it, and bump
    /// confidence. The user has just validated the inference.
    func acceptSignal(_ signal: PersonaBehavioralInference.PersonaSignal) {
        let persona = currentOrCreate()
        switch signal.field {
        case .peakAlertness:
            persona.peakAlertnessRaw = signal.proposedRaw
            markAnswered("peak_alertness", on: persona)
        case .recoverySensitivity:
            persona.recoverySensitivityRaw = signal.proposedRaw
            markAnswered("recovery_sensitivity", on: persona)
        case .failureResponse:
            persona.failureResponseRaw = signal.proposedRaw
            markAnswered("failure_response", on: persona)
        case .decisionStyle:
            persona.decisionStyleRaw = signal.proposedRaw
            markAnswered("decision_style", on: persona)
        }
        persona.confidence = min(100, persona.confidence + 10)
        try? modelContext.save()
    }

    /// Record that the user rejected a signal so we do not surface it again.
    /// We don't permanently silence the *field* — if behavior shifts and a new
    /// proposal lands on a different value, that will be a different key.
    func dismissSignal(_ signal: PersonaBehavioralInference.PersonaSignal) {
        let memory = CoachMemory(
            key: personaSignalDismissedKey(signal.key),
            value: "User dismissed behavioral inference: \(signal.proposedDisplay) (\(signal.field.rawValue)).",
            importance: 1,
            expiresAt: nil
        )
        modelContext.insert(memory)
        try? modelContext.save()
    }

    // MARK: - Behavioral inference helpers (private)

    private func personaSignalDismissedKey(_ signalKey: String) -> String {
        "persona_signal_dismissed_\(signalKey)"
    }

    private func dismissedSignalKeys() -> Set<String> {
        let memories = (try? modelContext.fetch(FetchDescriptor<CoachMemory>())) ?? []
        return Set(memories.compactMap { mem -> String? in
            let prefix = "persona_signal_dismissed_"
            guard mem.key.hasPrefix(prefix) else { return nil }
            return String(mem.key.dropFirst(prefix.count))
        })
    }

    private func markAnswered(_ key: String, on persona: UserPersona) {
        var answered = persona.answeredQuestionKeysCSV
            .split(separator: ",").map(String.init).filter { !$0.isEmpty }
        if !answered.contains(key) {
            answered.append(key)
            persona.answeredQuestionKeysCSV = answered.joined(separator: ",")
        }
    }

    private func recentLiftStarts(since: Date) -> [PersonaBehavioralInference.LiftStart] {
        let sessions = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let cal = Calendar.current
        return sessions
            .filter { $0.date >= since }
            .map { PersonaBehavioralInference.LiftStart(hourOfDay: cal.component(.hour, from: $0.date)) }
    }

    private func recentRecoveryDays(from start: Date, to end: Date) -> [PersonaBehavioralInference.RecoveryDay] {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let cal = Calendar.current

        let inRangeLogs = logs.filter { $0.date >= start && $0.date <= end }
        return inRangeLogs.map { log in
            let trained = events.contains { ev in
                ev.completed && cal.isDate(ev.date, inSameDayAs: log.date)
            }
            return PersonaBehavioralInference.RecoveryDay(
                hrvRmssd: log.hrvRmssd,
                sleepHours: log.sleepHours,
                trained: trained
            )
        }
    }

    private func recentSkipPairs(since: Date, asOf: Date) -> [PersonaBehavioralInference.SkipDayPair] {
        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let cal = Calendar.current

        // Typical duration baseline = median of completed lift sessions in range.
        let recentLifts = lifts.filter { $0.date >= since && $0.durationMinutes > 0 }
        let typical: Int = {
            let durations = recentLifts.map { $0.durationMinutes }.sorted()
            guard !durations.isEmpty else { return 45 }
            return durations[durations.count / 2]
        }()

        let skipKinds: Set<String> = [
            WorkoutEventSource.manualSkip.rawValue,
            WorkoutEventSource.sickDay.rawValue,
            WorkoutEventSource.travel.rawValue
        ]
        let skips = events
            .filter { $0.date >= since }
            .filter { skipKinds.contains($0.source) || ($0.completed == false && $0.date < cal.startOfDay(for: asOf)) }
            .sorted { $0.date < $1.date }

        return skips.compactMap { skip -> PersonaBehavioralInference.SkipDayPair? in
            let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: skip.date)) ?? skip.date
            // Skip events with no observable "next day" yet.
            guard nextDay < cal.startOfDay(for: asOf) else { return nil }
            let nextLift = recentLifts.first { cal.isDate($0.date, inSameDayAs: nextDay) }
            let trainedNext = nextLift != nil
            return PersonaBehavioralInference.SkipDayPair(
                trainedNextDay: trainedNext,
                nextDayDurationMinutes: nextLift?.durationMinutes,
                typicalDurationMinutes: typical
            )
        }
    }

    private func suggestionOutcomes(since: Date) -> PersonaBehavioralInference.SuggestionOutcomes {
        let all = (try? modelContext.fetch(FetchDescriptor<ScheduleSuggestion>())) ?? []
        let inRange = all.filter { $0.generatedAt >= since }
        var a = 0, d = 0, s = 0
        for sug in inRange {
            switch sug.status {
            case .accepted:  a += 1
            case .dismissed: d += 1
            case .snoozed:   s += 1
            case .pending:   break
            }
        }
        return PersonaBehavioralInference.SuggestionOutcomes(accepted: a, dismissed: d, snoozed: s)
    }

    // MARK: - Prompt context

    /// Compact prompt block injected into every Coach prompt. Lists only the
    /// fields the user has actually filled in (avoid wasting tokens on nulls
    /// and avoid feeding Claude empty-default noise).
    func promptContextBlock() -> String {
        let persona = currentOrCreate()
        var lines: [String] = []

        if let v = persona.motivationDriverRaw,
           let driver = PersonaMotivationDriver(rawValue: v) {
            lines.append("Motivation driver: \(driver.rawValue) (\(driver.displayName)).")
        }
        if let v = persona.communicationStyleRaw,
           let style = PersonaCommunicationStyle(rawValue: v) {
            lines.append("Communication style: \(style.rawValue) (\(style.displayName)).")
        }
        if let v = persona.accountabilityPreferenceRaw,
           let pref = PersonaAccountabilityPreference(rawValue: v) {
            lines.append("Accountability preference: \(pref.rawValue) (\(pref.displayName)).")
        }
        if let v = persona.failureResponseRaw,
           let resp = PersonaFailureResponse(rawValue: v) {
            lines.append("Failure response: \(resp.rawValue) (\(resp.displayName)).")
        }
        if let v = persona.recoverySensitivityRaw,
           let sens = PersonaRecoverySensitivity(rawValue: v) {
            lines.append("Recovery sensitivity: \(sens.rawValue) (\(sens.displayName)).")
        }
        if let v = persona.peakAlertnessRaw,
           let peak = PersonaPeakAlertness(rawValue: v) {
            lines.append("Peak alertness window: \(peak.displayName).")
        }
        if let v = persona.decisionStyleRaw,
           let style = PersonaDecisionStyle(rawValue: v) {
            lines.append("Decision style: \(style.rawValue) (\(style.displayName)).")
        }

        let identities = persona.identityAnchorsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !identities.isEmpty {
            lines.append("Identity anchors (their words): \(identities.joined(separator: ", ")).")
        }

        let history = persona.historicalAttemptsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !history.isEmpty {
            lines.append("Previously tried + abandoned: \(history.joined(separator: " | ")). Do NOT re-recommend these patterns.")
        }

        if !persona.goodWeekDescription.isEmpty {
            lines.append("'Good week' in their words: \"\(persona.goodWeekDescription)\"")
        }
        if !persona.idealCoachLine.isEmpty {
            lines.append("Coach line they want to hear: \"\(persona.idealCoachLine)\"")
        }

        if lines.isEmpty { return "" }
        let header = "=== USER PERSONA (confidence \(persona.confidence)/100) ==="
        let footer = "Honor these preferences when shaping copy, framing, and tactics. They are user-declared; do not override them with defaults."
        return ([header] + lines + [footer]).joined(separator: "\n")
    }
}

// MARK: - Question library

/// Single curated question. Multi-choice questions list options up-front.
/// Free-text questions accept any string.
struct PersonaQuestion: Sendable, Identifiable, Hashable {
    enum Kind: Sendable, Hashable {
        case motivationDriver
        case communicationStyle
        case accountabilityPreference
        case failureResponse
        case recoverySensitivity
        case peakAlertness
        case decisionStyle
        case identityAnchors    // free text → CSV
        case historicalAttempts // free text → CSV
        case goodWeek           // free text
        case idealCoachLine     // free text
    }

    let key: String
    let prompt: String
    let kind: Kind

    var id: String { key }

    /// Curated question library. Order = surface order in both Settings and
    /// the weekly question card. Designed to feel like a real coach asking
    /// progressively deeper questions, not a survey.
    static let library: [PersonaQuestion] = [
        PersonaQuestion(
            key: "motivation_driver",
            prompt: "When you finish a hard week, what feels most like 'win'? Getting better at the thing, hitting the number, doing it your way, the people you did it for, who you're becoming, or just feeling good in your body?",
            kind: .motivationDriver
        ),
        PersonaQuestion(
            key: "communication_style",
            prompt: "How do you want a coach to talk to you? Cut straight to the move, warm and relational, technical with the physiology, or zoomed-out to the bigger why?",
            kind: .communicationStyle
        ),
        PersonaQuestion(
            key: "peak_alertness",
            prompt: "When in the day does your head work best? Early morning, mid-morning, afternoon, evening, or late night?",
            kind: .peakAlertness
        ),
        PersonaQuestion(
            key: "failure_response",
            prompt: "Tough day, you don't feel it. Default move? Train anyway, shorten the session, take the day, or talk it through before you decide?",
            kind: .failureResponse
        ),
        PersonaQuestion(
            key: "recovery_sensitivity",
            prompt: "Honest check: do you tend to override fatigue, stop at the first signal, or land somewhere in between?",
            kind: .recoverySensitivity
        ),
        PersonaQuestion(
            key: "accountability_preference",
            prompt: "You skip a day. How should the coach hold you? Gentle check-in, hard truth, just the data, or pivot to what's working?",
            kind: .accountabilityPreference
        ),
        PersonaQuestion(
            key: "decision_style",
            prompt: "When you have to make a call about your training, do you reach for data, your gut, advice, or a mix?",
            kind: .decisionStyle
        ),
        PersonaQuestion(
            key: "identity_anchors",
            prompt: "If a friend asked who you're being right now, comma-separated, what would you say? (e.g., 'competitor, teacher, dad trying to stay strong')",
            kind: .identityAnchors
        ),
        PersonaQuestion(
            key: "historical_attempts",
            prompt: "Anything you've tried and abandoned that the coach should know NOT to re-suggest? List with reason, comma-separated. (e.g., 'Noom: too restrictive | 5am gym: kids needed me')",
            kind: .historicalAttempts
        ),
        PersonaQuestion(
            key: "good_week",
            prompt: "Describe a 'good week' for you, in your own words. One or two sentences.",
            kind: .goodWeek
        ),
        PersonaQuestion(
            key: "ideal_coach_line",
            prompt: "What's one sentence you wish a coach would say to you at the right moment? (Used as a flavor cue, not parroted back.)",
            kind: .idealCoachLine
        )
    ]
}
