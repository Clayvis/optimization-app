import Foundation
import WidgetKit
import SwiftData

struct CurrentBlockEntry: TimelineEntry, Sendable {
    let date: Date
    let label: String       // "NOW" or "NEXT"
    let title: String       // full activity
    let subtitle: String    // "09:30 – 11:00" or "starts 09:00"
    let short: String       // 10-char fallback
    let compactTime: String // "10:30" or "1h 30m"
}

struct CurrentBlockTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> CurrentBlockEntry {
        Self.staticPlaceholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentBlockEntry) -> Void) {
        let entry = MainActor.assumeIsolated { Self.makeEntry(at: Date()) }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentBlockEntry>) -> Void) {
        let entries: [CurrentBlockEntry] = MainActor.assumeIsolated {
            let now = Date()
            var collected: [CurrentBlockEntry] = []
            let step: TimeInterval = 15 * 60
            for offset in stride(from: TimeInterval(0), through: 6 * 3600, by: step) {
                collected.append(Self.makeEntry(at: now.addingTimeInterval(offset)))
            }
            return collected
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func staticPlaceholder() -> CurrentBlockEntry {
        CurrentBlockEntry(
            date: Date(),
            label: "NOW",
            title: "Lift A",
            subtitle: "09:30 – 11:00",
            short: "Lift A",
            compactTime: "10:30"
        )
    }

    @MainActor
    static func makeEntry(at date: Date) -> CurrentBlockEntry {
        guard let container = sharedContainer() else {
            return CurrentBlockEntry(
                date: date,
                label: "OFFLINE",
                title: "PersonalOptimization",
                subtitle: "Sync pending",
                short: "—",
                compactTime: "—"
            )
        }

        let service = ScheduleService(modelContext: container.mainContext)

        if let current = service.currentBlock(at: date) {
            let remaining = service.timeUntilNextTransition(from: date) ?? 0
            return CurrentBlockEntry(
                date: date,
                label: "NOW",
                title: current.activity,
                subtitle: "\(current.startTime) – \(current.endTime)",
                short: shortLabel(for: current),
                compactTime: compactDuration(remaining)
            )
        }

        if let next = service.nextBlock(after: date) {
            return CurrentBlockEntry(
                date: date,
                label: "NEXT",
                title: next.activity,
                subtitle: "starts \(next.startTime)",
                short: shortLabel(for: next),
                compactTime: next.startTime
            )
        }

        return CurrentBlockEntry(
            date: date,
            label: "DONE",
            title: "Day complete",
            subtitle: "—",
            short: "Done",
            compactTime: "—"
        )
    }

    private static func shortLabel(for block: ScheduleBlock) -> String {
        if let module = block.module, !module.isEmpty {
            return module.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return String(block.activity.prefix(10))
    }

    private static func compactDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(mins)m"
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        let schema = Schema(versionedSchema: SchemaV6.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        return try? ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }
}
