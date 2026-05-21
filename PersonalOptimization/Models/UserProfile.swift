import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = ""
    var dob: Date = Date.distantPast
    var sex: String = "male"
    var heightInches: Double = 74
    var weightLbs: Double = 205
    var timezone: String = "Asia/Tokyo"
    var fastWindowStartHour: Int = 22
    var fastWindowEndHour: Int = 10
    var bottleSizeOz: Double = 32
    var anthropicModel: String = "claude-sonnet-4-6"
    var rolloutPhase: Int = 1
    var notificationBundling: Bool = false
    var mascotEnabled: Bool = true
    var reducedMotion: Bool = false
    var sickDayActiveUntil: Date?
    var travelModeActiveUntil: Date?
    var motivationStyle: String = "balanced"
    var customStylePrompt: String?
    var achillesCheckInEnabled: Bool = true
    var aiQuotesEnabled: Bool = false
    var onboardingCompleted: Bool = false
    var hydrationQuickPicksOzCSV: String = "4,8,12,16,20,24,32"

    // M3.7 additions (Block 3 + Block 4) — additive with defaults.
    var mascotVariant: String = "ninja_male"          // "ninja_male" | "ninja_female" | "custom"
    var primaryGoal: String?                          // free-text user-stated goal
    var secondaryGoalsCSV: String = ""                // comma-separated secondary goals
    var equipmentAccess: String = "gym"               // "gym" | "home_full" | "home_minimal" | "bodyweight" | "outdoor"
    var weeklyTrainingTargetSessions: Int = 5
    var restrictionsCSV: String = ""                  // injuries / dietary / time, comma-separated

    // V1 opportunities pass — Partner Mode scaffold (Opp 1).
    /// 6-character pairing code the user can share with their partner.
    /// Generated on demand. Expires 24h after creation. The CloudKit shared
    /// zone for partner data is wired up post-paid-developer; v1 ships UI +
    /// pairing state so users can opt in cleanly when it lands.
    var partnerPairingCode: String?
    var partnerPairingCodeExpiresAt: Date?
    /// Apple ID record name of the linked partner (set after a successful
    /// pair). Read by partner-mode views; nil = not paired.
    var partnerRecordID: String?
    var partnerLinkedAt: Date?
    var partnerOptedIntoSharing: Bool = true          // user can revoke per-domain in Settings later

    // V1 opportunities pass — Recovery + lapse scaffolding (Opps 3, 4).
    /// Last user-acknowledged "I feel fine, give me the regular workout"
    /// override against the RecoveryGate. Used so the gate can tell the user
    /// when overrides are repeated.
    var lastRecoveryOverrideAt: Date?
    var recoveryOverrideCountThisMonth: Int = 0

    // M4.1 — AI schedule generation. anchorEventsCSV holds user-declared
    // trigger labels (after_kid_dropoff, after_coffee, after_dinner) the AI
    // can ride blocks along. lastGeneratedAt powers the Settings cooldown
    // and the "Last generated" surface.
    var anchorEventsCSV: String = ""
    var lastGeneratedAt: Date?

    // M4.2 — Persist the user's most recent ScheduleIntake JSON so the form
    // hydrates next time they open it (instead of losing all their typing on
    // dismiss). Stored as a JSON string for forward compat — the intake
    // shape may grow.
    var lastIntakeJSON: String?

    // M4.2 — "What are you optimizing?" CSV of OptimizationFocus raw values
    // plus custom labels prefixed "custom:". Fed into both ScheduleAIService
    // and CoachService prompts so generations + suggestions respect them.
    var optimizationFocusesCSV: String = ""
    /// Last time the routine "anything new you're sharpening?" Coach card
    /// fired. Used by the 30-day cadence gate in TodayView.
    var lastFocusPromptAt: Date?

    // Pre-TestFlight P0/P1 pass — single-source-of-truth knobs and resilience.
    /// When true, app logic uses the device timezone instead of the pinned
    /// `timezone` field. Lets the user travel without splitting calendar days.
    /// Default false (pinned-to-profile behavior).
    var travelModeFollowsDevice: Bool = false
    /// Hydration / notification quiet hours start (HH:mm, user-tz).
    var sleepWindowStartHHMM: String = "22:00"
    /// Hydration / notification quiet hours end (HH:mm, user-tz).
    var sleepWindowEndHHMM: String = "07:00"
    /// Daily AI token budget. 0 disables Claude calls entirely (local-only).
    var dailyTokenBudget: Int = 50_000
    /// True when the user opts in to syncing the Anthropic key across their
    /// Apple devices via iCloud Keychain. M4.2 set this to true by default
    /// via a forced migration; users can opt out by flipping this to false
    /// in Settings (the key is re-written with `ThisDeviceOnly` posture).
    var apiKeyICloudSync: Bool = true
    /// Free-form metadata blob for additive, non-queried fields. Lets future
    /// milestones evolve UserProfile without bumping the SwiftData schema.
    /// See AppSchema.swift for the rule.
    var metadataBlob: Data?

    /// Parsed view of `anchorEventsCSV`. Empty CSV → empty array.
    /// Trims whitespace, drops empty tokens.
    var anchorEvents: [String] {
        anchorEventsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    init(name: String = "", dob: Date = .distantPast, sex: String = "male") {
        self.name = name
        self.dob = dob
        self.sex = sex
    }
}
