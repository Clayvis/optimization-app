import Foundation
import SwiftData

/// Structured representation of the user's personality + coaching preferences.
/// Populated three ways:
///   1. Active inference — the coach asks 1 question per week (see PersonaService.nextQuestion).
///   2. Free-text parsing — when the user replies to a coach card, AI extracts updates.
///   3. Passive inference — TrendAnalyticsService watches adherence patterns and proposes
///      updates (v2; the field set is already in place to receive them).
///
/// Every field is optional. The Coach prompts only inject what's been filled in.
/// Confidence accumulates as more signal arrives.
///
/// Single-user app: one persona row per user, lives next to UserProfile.
@Model
final class UserPersona {

    // MARK: - Curated, multi-choice fields (set via questionnaire)

    /// What pulls the user forward most reliably.
    /// Mastery: get better at the thing. Accomplishment: hit the number. Autonomy:
    /// do it my way, on my time. Social: people I care about. Identity: the kind
    /// of person I'm becoming. Vitality: feel good in my body.
    var motivationDriverRaw: String?           // PersonaMotivationDriver

    /// How the user wants coach copy framed.
    /// Direct: cut to the move. Warm: relational, encouraging. Technical: cite
    /// the physiology. Philosophical: link to the bigger why.
    var communicationStyleRaw: String?         // PersonaCommunicationStyle

    /// How the user wants accountability handled when they slip.
    /// Gentle: notice it, no pressure. Hard: name it, expect better. Data: just
    /// show the number, I'll judge. Encouragement: pivot to what's working.
    var accountabilityPreferenceRaw: String?   // PersonaAccountabilityPreference

    /// Default response when the user has had a hard day / week.
    /// Push: train through it. Recalibrate: shorten the session. Rest: take the
    /// day. Talk: process it before deciding.
    var failureResponseRaw: String?            // PersonaFailureResponse

    /// How the user reads their own recovery signals.
    /// Low listener: tends to override fatigue. Balanced. High listener: stops at
    /// the first signal. Self-honest answer matters more than the "right" one.
    var recoverySensitivityRaw: String?        // PersonaRecoverySensitivity

    /// Best window for cognitively demanding work.
    /// Self-report — used by AI scheduling to place hardest blocks at peak.
    var peakAlertnessRaw: String?              // PersonaPeakAlertness

    /// How the user makes decisions.
    /// Data: show me numbers. Gut: I'll feel it. Advice: tell me what to do.
    /// Mix: depends on the call.
    var decisionStyleRaw: String?              // PersonaDecisionStyle

    // MARK: - Free-text fields (set via question card replies)

    /// Self-described identity anchors. CSV. Examples: "competitor", "teacher",
    /// "trying to be a good dad", "recovering from burnout", "marathoner in
    /// training". Coach uses these for framing without imputing anything else.
    var identityAnchorsCSV: String = ""

    /// Things the user has tried and abandoned, plus what stopped them.
    /// CSV. Examples: "noom: too restrictive", "5am gym: kids sick disrupted",
    /// "running: hurt knee". Coach uses these to avoid re-recommending failed
    /// patterns.
    var historicalAttemptsCSV: String = ""

    /// What does "a good week" look like to the user, in their own words.
    /// Free-text. Coach uses this to frame insights at the end of each week.
    var goodWeekDescription: String = ""

    /// One sentence the user wishes a coach would say to them at the right
    /// moment. Free-text. Coach can echo or honor this when relevant.
    var idealCoachLine: String = ""

    // MARK: - Inferred fields (set by passive observation; v2)

    /// 0-100, rough confidence the persona model has accumulated enough
    /// signal to be trusted by the Coach. Increments when the user answers
    /// questions or when behavior patterns confirm a trait.
    var confidence: Int = 0

    /// Timestamp of the last question card surfaced. Used by PersonaService
    /// to throttle to roughly 1 per week.
    var lastQuestionAskedAt: Date?

    /// Comma-separated list of question keys the user has answered. Lets
    /// PersonaService pick the next gap rather than repeat questions.
    var answeredQuestionKeysCSV: String = ""

    init() {}
}

// MARK: - Field enums

enum PersonaMotivationDriver: String, CaseIterable, Sendable {
    case mastery, accomplishment, autonomy, social, identity, vitality

    var displayName: String {
        switch self {
        case .mastery:        return "Mastery (get better at the thing)"
        case .accomplishment: return "Accomplishment (hit the number)"
        case .autonomy:       return "Autonomy (my way, on my time)"
        case .social:         return "Social (people I care about)"
        case .identity:       return "Identity (the kind of person I'm becoming)"
        case .vitality:       return "Vitality (feel good in my body)"
        }
    }
}

enum PersonaCommunicationStyle: String, CaseIterable, Sendable {
    case direct, warm, technical, philosophical

    var displayName: String {
        switch self {
        case .direct:        return "Direct — cut to the move"
        case .warm:          return "Warm — relational"
        case .technical:     return "Technical — cite the physiology"
        case .philosophical: return "Philosophical — link to the bigger why"
        }
    }
}

enum PersonaAccountabilityPreference: String, CaseIterable, Sendable {
    case gentleCheckIn, hardTruth, dataOnly, encouragement

    var displayName: String {
        switch self {
        case .gentleCheckIn:  return "Gentle — notice it, no pressure"
        case .hardTruth:      return "Hard truth — name it, expect better"
        case .dataOnly:       return "Data — show the number, I'll judge"
        case .encouragement:  return "Encouragement — pivot to what's working"
        }
    }
}

enum PersonaFailureResponse: String, CaseIterable, Sendable {
    case pushThrough, recalibrate, rest, talkItOut

    var displayName: String {
        switch self {
        case .pushThrough:  return "Push through — train anyway"
        case .recalibrate:  return "Recalibrate — shorten it"
        case .rest:         return "Rest — take the day"
        case .talkItOut:    return "Talk it out — process first"
        }
    }
}

enum PersonaRecoverySensitivity: String, CaseIterable, Sendable {
    case lowListener, balanced, highListener

    var displayName: String {
        switch self {
        case .lowListener:  return "I tend to override fatigue"
        case .balanced:     return "Balanced — depends on the day"
        case .highListener: return "I stop at the first signal"
        }
    }
}

enum PersonaPeakAlertness: String, CaseIterable, Sendable {
    case earlyMorning, morning, afternoon, evening, lateNight

    var displayName: String {
        switch self {
        case .earlyMorning: return "Early morning (5–7 AM)"
        case .morning:      return "Morning (7–11 AM)"
        case .afternoon:    return "Afternoon (12–4 PM)"
        case .evening:      return "Evening (5–9 PM)"
        case .lateNight:    return "Late night (10 PM+)"
        }
    }
}

enum PersonaDecisionStyle: String, CaseIterable, Sendable {
    case data, gut, advice, mix

    var displayName: String {
        switch self {
        case .data:    return "Data — show me numbers"
        case .gut:     return "Gut — I'll feel it"
        case .advice:  return "Advice — tell me what to do"
        case .mix:     return "Mix — depends on the call"
        }
    }
}
