import WidgetKit
import SwiftUI
import SwiftData

/// Hydration progress complication. Surfaces today's intake vs the day's
/// target as a circular ring + corner glyph + inline text. Reload-on-write
/// is event-driven (`WidgetCenter.shared.reloadAllTimelines()` after a log).
/// This complication itself uses a 30-min timeline cadence as the safe
/// fallback when no reload event fires.
struct HydrationComplicationEntry: TimelineEntry, Sendable {
    let date: Date
    let progress: Double           // 0...1
    let intakeOz: Int
    let targetOz: Int
}

struct HydrationTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> HydrationComplicationEntry {
        HydrationComplicationEntry(date: Date(), progress: 0.5, intakeOz: 32, targetOz: 64)
    }

    func getSnapshot(in context: Context, completion: @escaping (HydrationComplicationEntry) -> Void) {
        let entry = MainActor.assumeIsolated { Self.makeEntry(at: Date()) }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationComplicationEntry>) -> Void) {
        let entries: [HydrationComplicationEntry] = MainActor.assumeIsolated {
            let now = Date()
            // Sparse 30-min ticks for the rest of the day; reloads after a
            // log will refresh on demand.
            return stride(from: TimeInterval(0), through: 12 * 3600, by: 30 * 60)
                .map { Self.makeEntry(at: now.addingTimeInterval($0)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    @MainActor
    static func makeEntry(at date: Date) -> HydrationComplicationEntry {
        guard let container = sharedContainer() else {
            return HydrationComplicationEntry(date: date, progress: 0, intakeOz: 0, targetOz: 64)
        }
        let context = container.mainContext
        let cal = jstCalendar()
        let day = cal.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        let log = (try? context.fetch(descriptor))?.first
        let intake = log?.waterOz ?? 0
        let target = (try? ScheduleConfigLoader.load().hydrationTargetsOz)
            .map { dayTargetMin(for: date, targets: $0) } ?? 64
        let progress: Double = target > 0 ? min(1.0, intake / target) : 0
        return HydrationComplicationEntry(
            date: date,
            progress: progress,
            intakeOz: Int(intake),
            targetOz: Int(target)
        )
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        let schema = Schema(versionedSchema: SchemaV8.self)
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

    private static func dayTargetMin(for date: Date, targets: HydrationTargetsOz) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let raw = cal.component(.weekday, from: date)
        let weekday = raw == 1 ? 7 : raw - 1
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }

    private static func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return cal
    }
}

struct HydrationComplication: Widget {
    let kind: String = "HydrationComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HydrationTimelineProvider()) { entry in
            HydrationComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hydration")
        .description("Shows today's hydration progress.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct HydrationComplicationView: View {
    let entry: HydrationComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Circle()
                    .stroke(Color.blue.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("\(entry.intakeOz)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
            }
        case .accessoryCorner:
            Text("\(entry.intakeOz)oz")
                .font(.caption2.weight(.bold))
                .widgetCurvesContent()
        case .accessoryInline:
            Text("Hydration \(entry.intakeOz) / \(entry.targetOz) oz")
        default:
            Text("\(entry.intakeOz) / \(entry.targetOz) oz")
        }
    }
}
