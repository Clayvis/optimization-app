import Foundation
import SwiftData
import os

/// CRUD + lookup for ImplementationIntention rows. The service is iOS-only
/// (lives in Engagement module) and writes are user-initiated (form submits).
@MainActor
final class ImplementationIntentionService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.rawlins.PersonalOptimization", category: "intentions")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// All non-archived intentions, oldest first.
    func active() -> [ImplementationIntention] {
        let descriptor = FetchDescriptor<ImplementationIntention>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.active }
    }

    @discardableResult
    func add(trigger: String,
             triggerType: TriggerType,
             action: String,
             scheduleBlockID: UUID? = nil,
             triggerTimeMinutes: Int? = nil) throws -> ImplementationIntention {
        let trimmed = trigger.trimmingCharacters(in: .whitespaces)
        let trimmedAction = action.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmedAction.isEmpty else {
            throw IntentionError.invalidInput
        }
        let intention = ImplementationIntention(
            trigger: trimmed,
            triggerType: triggerType,
            action: trimmedAction,
            scheduleBlockID: scheduleBlockID,
            triggerTimeMinutes: triggerTimeMinutes
        )
        modelContext.insert(intention)
        try modelContext.save()
        logger.info("Added intention type=\(triggerType.rawValue, privacy: .public)")
        return intention
    }

    func update(_ intention: ImplementationIntention,
                trigger: String,
                triggerType: TriggerType,
                action: String,
                scheduleBlockID: UUID? = nil,
                triggerTimeMinutes: Int? = nil) throws {
        intention.trigger = trigger.trimmingCharacters(in: .whitespaces)
        intention.triggerTypeRaw = triggerType.rawValue
        intention.action = action.trimmingCharacters(in: .whitespaces)
        intention.scheduleBlockID = scheduleBlockID
        intention.triggerTimeMinutes = triggerTimeMinutes
        try modelContext.save()
    }

    func archive(_ intention: ImplementationIntention) throws {
        intention.active = false
        try modelContext.save()
    }

    func recordCompletion(_ intention: ImplementationIntention, at date: Date = Date()) throws {
        intention.lastCompletedAt = date
        try modelContext.save()
    }

    /// Seeds 5 starter intentions for the user during onboarding when none
    /// exist yet. Templates pulled from CLAUDE.md user profile + the seven
    /// principles (anchored to events, friction-reduced, identity-framed).
    @discardableResult
    func seedStartersIfNeeded() throws -> Int {
        let descriptor = FetchDescriptor<ImplementationIntention>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return 0 }

        let starters: [(String, TriggerType, String)] = [
            ("After morning coffee",      .afterEvent, "Drink 16 oz of water"),
            ("After kid drop-off at 0900", .time,       "Start the morning training block"),
            ("After dinner",              .afterEvent, "Close the eating window"),
            ("Before bed",                .afterEvent, "Log 10 minutes of Japanese"),
            ("Sunday morning",            .afterEvent, "Review the week and plan the next")
        ]
        for (trigger, type, action) in starters {
            let timeMinutes: Int? = (type == .time && trigger.contains("0900")) ? (9 * 60) : nil
            let intention = ImplementationIntention(
                trigger: trigger,
                triggerType: type,
                action: action,
                triggerTimeMinutes: timeMinutes
            )
            modelContext.insert(intention)
        }
        try modelContext.save()
        return starters.count
    }
}

enum IntentionError: LocalizedError {
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Trigger and action are both required."
        }
    }
}
