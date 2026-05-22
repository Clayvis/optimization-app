import Foundation
import SwiftData
import os

/// CRUD + retrieval for `CoachMemory`. Pulled into `CoachService.gatherFullContext`
/// so the Coach can reference the user's stated context across days instead of
/// starting cold every call. Auto-prunes expired rows on read so memory doesn't
/// inflate.
@MainActor
final class CoachMemoryService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "coach-memory")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Active (non-expired) memories, sorted by importance descending and
    /// recency. Caller can take the top N when assembling a token-budgeted
    /// prompt block.
    func active(asOf date: Date = Date()) -> [CoachMemory] {
        pruneExpired(asOf: date)
        let descriptor = FetchDescriptor<CoachMemory>(
            sortBy: [
                SortDescriptor(\.importance, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        let all = modelContext.fetchOrEmpty(descriptor)
        return all.filter { ($0.expiresAt ?? .distantFuture) > date }
    }

    @discardableResult
    func add(value: String,
             key: String = "",
             importance: Int = 3,
             expiresIn days: Int? = nil) throws -> CoachMemory {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoachMemoryError.empty }

        // Dedupe by key when key is supplied — newer note overwrites older.
        if !key.isEmpty {
            let descriptor = FetchDescriptor<CoachMemory>(
                predicate: #Predicate<CoachMemory> { $0.key == key }
            )
            for prior in modelContext.fetchOrEmpty(descriptor) {
                modelContext.delete(prior)
            }
        }

        let expires: Date? = days.map { Date().addingTimeInterval(TimeInterval($0) * 86400) }
        let memory = CoachMemory(
            key: key,
            value: trimmed,
            importance: importance,
            expiresAt: expires
        )
        modelContext.insert(memory)
        try modelContext.save()
        return memory
    }

    func delete(_ memory: CoachMemory) throws {
        modelContext.delete(memory)
        try modelContext.save()
    }

    /// Compact text block ready to inject into the Coach prompt. Trimmed to
    /// `tokenBudget` characters as a rough heuristic (~3.5 chars per token).
    /// Top-importance items go in first.
    func summaryForCoach(asOf date: Date = Date(), characterBudget: Int = 1200) -> String {
        let memories = active(asOf: date)
        guard !memories.isEmpty else { return "" }

        var lines: [String] = []
        var total = 0
        for memory in memories {
            let bullet = "- \(memory.value)"
            if total + bullet.count > characterBudget { break }
            lines.append(bullet)
            total += bullet.count
        }
        guard !lines.isEmpty else { return "" }
        return "User-supplied context to remember:\n" + lines.joined(separator: "\n")
    }

    private func pruneExpired(asOf date: Date) {
        let descriptor = FetchDescriptor<CoachMemory>()
        let all = modelContext.fetchOrEmpty(descriptor)
        var pruned = 0
        for memory in all {
            if let expires = memory.expiresAt, expires <= date {
                modelContext.delete(memory)
                pruned += 1
            }
        }
        if pruned > 0 {
            try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
            logger.info("Pruned \(pruned, privacy: .public) expired CoachMemory rows")
        }
    }
}

enum CoachMemoryError: LocalizedError {
    case empty

    var errorDescription: String? {
        switch self {
        case .empty: return "Memory cannot be empty."
        }
    }
}
