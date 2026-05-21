import Foundation
import WidgetKit
import SwiftData

struct FastCountdownEntry: TimelineEntry, Sendable {
    let date: Date
    let label: String        // "FASTING" or "EATING"
    let primary: String      // big text like "12:34" remaining or "starts 22:00"
    let subtitle: String     // window label or eating-state caption
    let shortLabel: String   // "FAST" or "EAT"
    let compactDuration: String
    let progress: Double     // 0..1 for circular ring
}

struct FastCountdownTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> FastCountdownEntry {
        FastCountdownEntry(
            date: Date(),
            label: "FASTING",
            primary: "8h 12m",
            subtitle: "training fast",
            shortLabel: "FAST",
            compactDuration: "8h 12m",
            progress: 0.4
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FastCountdownEntry) -> Void) {
        let entry = MainActor.assumeIsolated { Self.makeEntry(at: Date()) }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastCountdownEntry>) -> Void) {
        let entries: [FastCountdownEntry] = MainActor.assumeIsolated {
            let now = Date()
            var collected: [FastCountdownEntry] = []
            let step: TimeInterval = 5 * 60
            for offset in stride(from: TimeInterval(0), through: 6 * 3600, by: step) {
                collected.append(Self.makeEntry(at: now.addingTimeInterval(offset)))
            }
            return collected
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    @MainActor
    static func makeEntry(at date: Date) -> FastCountdownEntry {
        guard let container = sharedContainer(),
              let config = try? ScheduleConfigLoader.load() else {
            return placeholderEntry(at: date)
        }

        let context = container.mainContext
        let profile = ProfileService.currentOrCreate(modelContext: context)
        let service = FastingService(modelContext: context, defaults: config.fastingDefaults)

        if let window = service.currentWindow(at: date, profile: profile) {
            let total = window.end.timeIntervalSince(window.start)
            let elapsed = service.elapsedFasting(at: date, profile: profile)
            let progress = total > 0 ? min(1.0, max(0.0, elapsed / total)) : 0
            let remaining = service.remainingInFast(at: date, profile: profile) ?? 0
            return FastCountdownEntry(
                date: date,
                label: "FASTING",
                primary: compact(remaining),
                subtitle: "\(window.label) fast",
                shortLabel: "FAST",
                compactDuration: compact(remaining),
                progress: progress
            )
        }

        let next = service.nextWindow(after: date, profile: profile)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return FastCountdownEntry(
            date: date,
            label: "EATING",
            primary: "starts \(formatter.string(from: next.start))",
            subtitle: "\(next.label) fast next",
            shortLabel: "EAT",
            compactDuration: formatter.string(from: next.start),
            progress: 0
        )
    }

    private static func placeholderEntry(at date: Date) -> FastCountdownEntry {
        FastCountdownEntry(
            date: date,
            label: "OFFLINE",
            primary: "—",
            subtitle: "Sync pending",
            shortLabel: "—",
            compactDuration: "—",
            progress: 0
        )
    }

    private static func compact(_ seconds: TimeInterval) -> String {
        let mins = max(0, Int(seconds / 60))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(mins)m"
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        let schema = AppSchema.schema()
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        return try? ModelContainer(
            for: schema,
            migrationPlan: AppSchema.migrationPlan,
            configurations: [config]
        )
    }
}
