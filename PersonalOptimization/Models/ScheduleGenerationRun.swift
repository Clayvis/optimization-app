import Foundation
import SwiftData

/// Audit trail for AI-driven schedule generations. One row per call to
/// `ScheduleAIService.generate`. Persisted so the user can revisit a discarded
/// proposal ("oh wait, that one was fine") and so Settings → Diagnostics can
/// surface "AI calls this month" with token + cost rollup. Auto-purged after
/// 30 days via `ScheduleGenerationRun.purgeStale`.
@Model
final class ScheduleGenerationRun {
    var generatedAt: Date = Date.distantPast
    var modelUsed: String = ""              // e.g. "claude-opus-4-7"
    var intakeJSON: String = ""             // captured intake form values, for replay/debug
    var proposalJSON: String = ""           // full GenerationProposal payload
    var statusRaw: String = ScheduleGenerationRunStatus.proposed.rawValue
    var tokenUsage: Int = 0                 // input + output tokens
    var costEstimateCents: Int = 0          // rounded; surface as "$X.YY this month"

    var status: ScheduleGenerationRunStatus {
        get { ScheduleGenerationRunStatus(rawValue: statusRaw) ?? .proposed }
        set { statusRaw = newValue.rawValue }
    }

    init(generatedAt: Date,
         modelUsed: String,
         intakeJSON: String,
         proposalJSON: String,
         status: ScheduleGenerationRunStatus = .proposed,
         tokenUsage: Int = 0,
         costEstimateCents: Int = 0) {
        self.generatedAt = generatedAt
        self.modelUsed = modelUsed
        self.intakeJSON = intakeJSON
        self.proposalJSON = proposalJSON
        self.statusRaw = status.rawValue
        self.tokenUsage = tokenUsage
        self.costEstimateCents = costEstimateCents
    }
}

enum ScheduleGenerationRunStatus: String, Codable, CaseIterable, Sendable {
    case proposed       // generated, awaiting user decision
    case accepted       // user tapped Apply
    case discarded      // user tapped Discard
}

extension ScheduleGenerationRun {
    /// Deletes rows older than 30 days. Called once per app launch.
    @MainActor
    static func purgeStale(modelContext: ModelContext, asOf: Date = Date()) {
        let cutoff = asOf.addingTimeInterval(-30 * 86_400)
        let descriptor = FetchDescriptor<ScheduleGenerationRun>(
            predicate: #Predicate<ScheduleGenerationRun> { $0.generatedAt < cutoff }
        )
        // MARK: try? justified - best-effort purge; nil result means nothing to purge.
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }
        for row in stale { modelContext.delete(row) }
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }
}
