import Foundation

/// Enumerates the "what are you trying to optimize" buckets the user can
/// declare. Persisted as a CSV on `UserProfile.optimizationFocusesCSV` and
/// surfaced in both onboarding and Settings. Custom entries use the
/// "custom:<label>" form so they round-trip through the CSV without breaking
/// the enum.
///
/// The AI prompts (CoachPrompts.generateSchedule, .suggestSchedule, and
/// dailyInsight) inject the list as an explicit "must respect" block so
/// authored schedules give each focus at least one weekly slot when possible.
enum OptimizationFocus: Equatable, Hashable, Sendable {
    case language
    case music
    case strength
    case endurance
    case fasting
    case sleepQuality
    case deepWork
    case mobility
    case nutrition
    case custom(String)

    static let builtIn: [OptimizationFocus] = [
        .language, .music, .strength, .endurance,
        .fasting, .sleepQuality, .deepWork, .mobility, .nutrition
    ]

    /// CSV-friendly raw value. Custom labels are prefixed "custom:" so a CSV
    /// like "strength,custom:Calligraphy,sleep_quality" round-trips cleanly.
    var rawValue: String {
        switch self {
        case .language:     return "language"
        case .music:        return "music"
        case .strength:     return "strength"
        case .endurance:    return "endurance"
        case .fasting:      return "fasting"
        case .sleepQuality: return "sleep_quality"
        case .deepWork:     return "deep_work"
        case .mobility:     return "mobility"
        case .nutrition:    return "nutrition"
        case .custom(let label): return "custom:\(label)"
        }
    }

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("custom:") {
            let label = String(trimmed.dropFirst("custom:".count))
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { return nil }
            self = .custom(label)
            return
        }
        switch trimmed {
        case "language":      self = .language
        case "music":         self = .music
        case "strength":      self = .strength
        case "endurance":     self = .endurance
        case "fasting":       self = .fasting
        case "sleep_quality": self = .sleepQuality
        case "deep_work":     self = .deepWork
        case "mobility":      self = .mobility
        case "nutrition":     self = .nutrition
        default: return nil
        }
    }

    /// Human-readable display name for the chip / list row.
    var displayName: String {
        switch self {
        case .language:     return "Language"
        case .music:        return "Music"
        case .strength:     return "Strength"
        case .endurance:    return "Endurance"
        case .fasting:      return "Fasting cadence"
        case .sleepQuality: return "Sleep quality"
        case .deepWork:     return "Deep work"
        case .mobility:     return "Mobility"
        case .nutrition:    return "Nutrition"
        case .custom(let label): return label
        }
    }

    /// SF Symbol for the chip / list row.
    var systemImage: String {
        switch self {
        case .language:     return "character.book.closed.fill"
        case .music:        return "music.note"
        case .strength:     return "figure.strengthtraining.traditional"
        case .endurance:    return "figure.run"
        case .fasting:      return "hourglass"
        case .sleepQuality: return "moon.zzz.fill"
        case .deepWork:     return "brain.head.profile"
        case .mobility:     return "figure.flexibility"
        case .nutrition:    return "leaf.fill"
        case .custom:       return "star.fill"
        }
    }
}

// MARK: - CSV round-trip

extension Array where Element == OptimizationFocus {
    /// Parses the CSV stored on `UserProfile.optimizationFocusesCSV`.
    /// Drops empty / malformed tokens silently.
    static func fromCSV(_ csv: String) -> [OptimizationFocus] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { OptimizationFocus(rawValue: $0) }
    }

    /// Serializes back to CSV form for `UserProfile` persistence.
    var asCSV: String {
        map(\.rawValue).joined(separator: ",")
    }
}
