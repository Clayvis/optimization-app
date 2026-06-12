import Foundation
import SwiftData
import os

/// One-shot launch migration: renames seeded "Lift B" schedule-block labels to
/// "My Workout" now that the hub's second lift slot is the user's custom
/// workout. Touches only display text on non-custom `module == "lift_b"` rows;
/// user-created blocks (`isCustom == true`) and all session history stay
/// untouched. UserDefaults-gated so it runs once per device. Pure update, no
/// deletes, so the retention guarantee holds.
@MainActor
enum LiftBRenameOnce {
    private static let key = "LiftBRename.v1.completed"

    /// Maps the known seeded labels to their My Workout equivalents. Unknown
    /// labels (already renamed, or hand-edited while still non-custom) pass
    /// through unchanged.
    static func newActivityLabel(for activity: String) -> String? {
        switch activity {
        case "Lift B (different exercises than Mon)": return "My Workout (custom lift)"
        case "Lift B": return "My Workout"
        case "Heavy lift B": return "My Workout (heavy)"
        default: return nil
        }
    }

    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.module == "lift_b" && $0.isCustom == false }
        )
        do {
            let blocks = try modelContext.fetch(descriptor)
            var renamed = 0
            for block in blocks {
                if let newLabel = newActivityLabel(for: block.activity) {
                    block.activity = newLabel
                    renamed += 1
                }
            }
            if renamed > 0 {
                try modelContext.save()
            }
            UserDefaults.standard.set(true, forKey: key)
            Logger.schedule.info("LiftBRenameOnce renamed \(renamed, privacy: .public) seeded blocks")
        } catch {
            Logger.schedule.error("LiftBRenameOnce failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
