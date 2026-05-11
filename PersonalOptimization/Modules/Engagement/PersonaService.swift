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
