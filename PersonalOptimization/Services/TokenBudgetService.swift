import Foundation
import SwiftData
import os

/// Enforces a daily AI token budget so unattended runs (or runaway Coach
/// retries) can't quietly spend more than the user opted into. The budget
/// lives on UserProfile.dailyTokenBudget; this service reads it and tracks
/// spending in SwiftData via TokenUsageEntry.
///
/// Behavior:
/// - 0 = AI features off entirely. Coach falls back to curated content.
/// - >0 = budget cap. Pre-call estimates check the cap. Post-call usage is
///   recorded against the day's running total.
@MainActor
final class TokenBudgetService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let logger = Logger.api

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    static func forUser(modelContext: ModelContext) -> TokenBudgetService {
        TokenBudgetService(
            modelContext: modelContext,
            calendar: UserCalendar.current(modelContext: modelContext)
        )
    }

    /// User-configured daily budget. 0 = AI off.
    var dailyBudget: Int {
        let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        return profile?.dailyTokenBudget ?? 50_000
    }

    /// True if the requested call would push today's spend past the cap.
    /// Always true when dailyBudget == 0 (AI disabled).
    func wouldExceed(estimatedTokens: Int) -> Bool {
        let budget = dailyBudget
        if budget <= 0 { return true }
        return (spentToday() + estimatedTokens) > budget
    }

    /// Record actual usage after a successful API call.
    func record(inputTokens: Int, outputTokens: Int) {
        let total = inputTokens + outputTokens
        guard total > 0 else { return }
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<TokenUsageEntry>(
            predicate: #Predicate<TokenUsageEntry> { $0.date == day }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
            existing.inputTokens += inputTokens
            existing.outputTokens += outputTokens
            existing.callCount += 1
            existing.lastCallAt = now
        } else {
            let entry = TokenUsageEntry(
                date: day,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                callCount: 1,
                lastCallAt: now
            )
            modelContext.insert(entry)
        }
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        logger.info("Token usage +\(total, privacy: .public) tokens (day total now \(self.spentToday(), privacy: .public))")
    }

    /// Today's running spend (input + output tokens).
    func spentToday() -> Int {
        let day = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<TokenUsageEntry>(
            predicate: #Predicate<TokenUsageEntry> { $0.date == day }
        )
        let entry = modelContext.fetchFirstOrNil(descriptor)
        return (entry?.inputTokens ?? 0) + (entry?.outputTokens ?? 0)
    }

    /// Month-to-date spend across all entries. Diagnostics convenience.
    func spentThisMonth() -> Int {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
            return 0
        }
        let descriptor = FetchDescriptor<TokenUsageEntry>(
            predicate: #Predicate<TokenUsageEntry> { $0.date >= monthStart }
        )
        let entries = modelContext.fetchOrEmpty(descriptor)
        return entries.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }
}
