import Foundation
import SwiftData
import os

@MainActor
enum ProfileService {

    /// Returns the single canonical UserProfile, creating one if none exists.
    /// Single-user app: if multiple profiles exist (rare CloudKit edge case), returns the first.
    static func currentOrCreate(modelContext: ModelContext) -> UserProfile {
        let fetched = modelContext.fetchOrEmpty(FetchDescriptor<UserProfile>())
        if let existing = fetched.first {
            return existing
        }
        let new = UserProfile()
        modelContext.insert(new)
        do {
            try modelContext.save()
        } catch {
            Logger.persistence.error("Failed to save new UserProfile: \(error.localizedDescription, privacy: .public)")
        }
        return new
    }
}

/// First-launch values stay in a draft until a valid, complete save. Height
/// and weight start empty so nobody inherits another person's measurements.
struct QuickProfileDraft {
    var name = ""
    var usesMetric = false
    var heightMajor = ""
    var heightMinor = "0"
    var weight = ""
    var goal = "Build a consistent routine"
    var weeklyWorkouts = 3
    var dailyMinutes = 10
    var equipment = "bodyweight"
    var mascotVariant = "ninja_male"

    var heightInches: Double? {
        guard let major = Self.number(heightMajor) else { return nil }
        if usesMetric { return major / 2.54 }
        guard major.rounded() == major, let minor = Self.number(heightMinor),
              minor >= 0, minor < 12 else { return nil }
        return major * 12 + minor
    }

    var weightLbs: Double? {
        Self.number(weight).map { usesMetric ? $0 * 2.2046226218 : $0 }
    }

    func validateBody() throws {
        guard let heightInches, heightInches.isFinite, (24...108).contains(heightInches) else {
            throw QuickProfileError.invalidHeight
        }
        guard let weightLbs, weightLbs.isFinite, (1...1500).contains(weightLbs) else {
            throw QuickProfileError.invalidWeight
        }
    }

    mutating func changeUnits(toMetric: Bool) {
        guard usesMetric != toMetric else { return }
        let inches = heightInches
        let pounds = weightLbs
        usesMetric = toMetric
        if let inches, inches.isFinite, (24...108).contains(inches) {
            // Round the total before splitting feet and inches, so a value
            // near the next foot cannot become an invalid "5 feet, 12 inches".
            let roundedInches = (inches * 100).rounded() / 100
            heightMajor = Self.format(toMetric ? inches * 2.54 : floor(roundedInches / 12))
            heightMinor = toMetric ? "0" : Self.format(roundedInches.truncatingRemainder(dividingBy: 12))
        } else {
            heightMajor = ""
            heightMinor = "0"
        }
        if let pounds, pounds.isFinite, (1...1500).contains(pounds) {
            weight = Self.format(toMetric ? pounds / 2.2046226218 : pounds)
        } else {
            weight = ""
        }
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use the user's decimal separator; reject grouping and stray text.
        let decimal = Locale.current.decimalSeparator ?? "."
        return Double(trimmed.replacingOccurrences(of: decimal, with: "."))
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}

enum QuickProfileError: LocalizedError {
    case invalidHeight, invalidWeight, invalidGoal

    var errorDescription: String? {
        switch self {
        case .invalidHeight: return String(localized: "Enter your height using the selected units.")
        case .invalidWeight: return String(localized: "Enter your weight using the selected units.")
        case .invalidGoal: return String(localized: "Choose a goal and a weekly plan before starting.")
        }
    }
}

extension ProfileService {
    /// Saves the quick profile atomically. Validation and store errors are
    /// thrown to onboarding; failure cannot mark the profile complete.
    /// Repeated completion never overwrites an already configured profile.
    static func completeQuickSetup(_ draft: QuickProfileDraft, profile: UserProfile,
                                   modelContext: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !profile.onboardingCompleted else { return }
        try draft.validateBody()
        let goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, (1...7).contains(draft.weeklyWorkouts), [5, 10, 20].contains(draft.dailyMinutes),
              ["gym", "home_full", "home_minimal", "bodyweight", "outdoor"].contains(draft.equipment),
              ["ninja_male", "ninja_female"].contains(draft.mascotVariant),
              let height = draft.heightInches, let weight = draft.weightLbs else {
            throw QuickProfileError.invalidGoal
        }
        try modelContext.transaction {
            profile.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.heightInches = height
            profile.weightLbs = weight
            profile.primaryGoal = goal
            profile.weeklyTrainingTargetSessions = draft.weeklyWorkouts
            profile.equipmentAccess = draft.equipment
            profile.mascotVariant = draft.mascotVariant
            profile.mascotEnabled = true
            profile.timezone = TimeZone.current.identifier
            profile.setMetadata("quickProfile.completed", value: true)
            profile.setMetadata("dailyWorkout.goalMinutes", value: draft.dailyMinutes)
            profile.setMetadata("dailyWorkout.weeklyGoal", value: draft.weeklyWorkouts)
            profile.setMetadata("profile.measurementSystem", value: draft.usesMetric ? "metric" : "imperial")
            profile.onboardingCompleted = true
            try modelContext.save()
        }
        defaults.set(draft.dailyMinutes, forKey: "dailyWorkout.goalMinutes")
        defaults.set(draft.weeklyWorkouts, forKey: "dailyWorkout.weeklyGoal")
    }
}
