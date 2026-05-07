import Foundation
import SwiftData
import os

/// Manages user-defined activity templates and the sessions logged against them.
/// Mirrors the shape of LiftService/SwimService/BasketballService — start a
/// session, mutate it, end it. End writes a `WorkoutEvent` (source = .custom)
/// so streaks, master metric, and TrendAnalytics see custom activities the
/// same as the typed sessions.
@MainActor
final class CustomActivityService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger.app

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    // MARK: - Templates

    /// All non-archived templates, oldest first by createdAt so the user-curated
    /// order is stable.
    func templates() -> [CustomActivityTemplate] {
        let descriptor = FetchDescriptor<CustomActivityTemplate>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { !$0.archived }
    }

    @discardableResult
    func addTemplate(name: String,
                     systemImageName: String = "figure.run",
                     defaultDurationMinutes: Int = 30,
                     trackDistance: Bool = false,
                     notes: String? = nil) throws -> CustomActivityTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let template = CustomActivityTemplate(
            name: trimmed.isEmpty ? "Activity" : trimmed,
            systemImageName: systemImageName,
            defaultDurationMinutes: max(1, defaultDurationMinutes),
            trackDistance: trackDistance,
            notes: notes
        )
        modelContext.insert(template)
        try modelContext.save()
        return template
    }

    func archiveTemplate(_ template: CustomActivityTemplate) throws {
        template.archived = true
        try modelContext.save()
    }

    func updateTemplate(_ template: CustomActivityTemplate,
                        name: String,
                        systemImageName: String,
                        defaultDurationMinutes: Int,
                        trackDistance: Bool,
                        notes: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        template.name = trimmed.isEmpty ? template.name : trimmed
        template.systemImageName = systemImageName
        template.defaultDurationMinutes = max(1, defaultDurationMinutes)
        template.trackDistance = trackDistance
        template.notes = notes
        try modelContext.save()
    }

    /// Seeds a small starter set for first-launch profiles. Idempotent: only
    /// runs when no templates exist yet. Names + glyphs picked to cover the
    /// common cases the wife test profile asked about (running, walking, HIIT,
    /// yoga) without forcing them on Clay's existing setup.
    func seedDefaultsIfNeeded() throws {
        let descriptor = FetchDescriptor<CustomActivityTemplate>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        let starters: [(String, String, Int, Bool)] = [
            ("Running",       "figure.run",                    30, true),
            ("Walking",       "figure.walk",                   30, true),
            ("HIIT",          "figure.highintensity.intervaltraining", 25, false),
            ("Yoga",          "figure.yoga",                   30, false),
            ("Cycling",       "figure.outdoor.cycle",          45, true),
            ("Hiking",        "figure.hiking",                 60, true)
        ]
        for (name, glyph, mins, distance) in starters {
            let t = CustomActivityTemplate(
                name: name,
                systemImageName: glyph,
                defaultDurationMinutes: mins,
                trackDistance: distance
            )
            modelContext.insert(t)
        }
        try modelContext.save()
        logger.info("Seeded \(starters.count, privacy: .public) default custom activity templates")
    }

    // MARK: - Sessions

    /// Starts a new session against a template. Pre-fills duration with the
    /// template default; user adjusts before ending.
    @discardableResult
    func startSession(for template: CustomActivityTemplate, at start: Date = Date()) throws -> CustomActivitySession {
        let session = CustomActivitySession(
            date: start,
            templateName: template.name,
            durationMinutes: 0,
            distanceMeters: nil,
            intensity: nil,
            notes: nil
        )
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    /// True when there's a session for `template` today with durationMinutes==0.
    func currentSession(for template: CustomActivityTemplate, asOf date: Date = Date()) -> CustomActivitySession? {
        let descriptor = FetchDescriptor<CustomActivitySession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return sessions.first {
            $0.templateName == template.name
                && $0.durationMinutes == 0
                && cal.isDate($0.date, inSameDayAs: date)
        }
    }

    /// Closes the session and writes the workout ledger so streaks pick it up.
    func endSession(_ session: CustomActivitySession,
                    durationMinutes: Int,
                    distanceMeters: Double? = nil,
                    intensity: String? = nil,
                    avgHR: Int? = nil,
                    caloriesKcal: Double? = nil,
                    notes: String? = nil) throws {
        session.durationMinutes = max(1, durationMinutes)
        session.distanceMeters = distanceMeters
        session.intensity = intensity
        session.avgHR = avgHR
        session.caloriesKcal = caloriesKcal
        session.notes = notes
        try modelContext.save()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: session.date)
        modelContext.insert(WorkoutEvent(date: day, completed: true, source: .custom))
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .workout, at: session.date, modelContext: modelContext)
        logger.info("Ended custom activity \(session.templateName, privacy: .public) duration=\(session.durationMinutes, privacy: .public)")
    }
}
