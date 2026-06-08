import WidgetKit
import SwiftUI
import SwiftData

/// iOS lock-screen + Home Screen widget surfacing the daily protocol goal as a
/// shape with the streak (build sheet section 2: the streak surfaced on the
/// complication AND lock screen). Reuses ProtocolGoalSnapshot so it never drifts
/// from the in-app metric or the watch complication.
struct ProtocolGoalWidgetEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let completedDomains: Int
    let totalDomains: Int

    var progress: Double {
        totalDomains > 0 ? Double(completedDomains) / Double(totalDomains) : 0
    }
}

struct ProtocolGoalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProtocolGoalWidgetEntry {
        ProtocolGoalWidgetEntry(date: Date(), streak: 7, completedDomains: 3, totalDomains: 4)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProtocolGoalWidgetEntry) -> Void) {
        completion(MainActor.assumeIsolated { Self.makeEntry(at: Date()) })
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProtocolGoalWidgetEntry>) -> Void) {
        let entries: [ProtocolGoalWidgetEntry] = MainActor.assumeIsolated {
            let now = Date()
            return stride(from: TimeInterval(0), through: 6 * 3600, by: 30 * 60)
                .map { Self.makeEntry(at: now.addingTimeInterval($0)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    @MainActor
    static func makeEntry(at date: Date) -> ProtocolGoalWidgetEntry {
        guard let container = sharedContainer() else {
            return ProtocolGoalWidgetEntry(date: date, streak: 0, completedDomains: 0, totalDomains: 4)
        }
        let snap = ProtocolGoalSnapshot.make(modelContext: container.mainContext, asOf: date)
        return ProtocolGoalWidgetEntry(
            date: date,
            streak: snap.streak,
            completedDomains: snap.completedDomains,
            totalDomains: snap.totalDomains
        )
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        let schema = AppSchema.schema()
        // Read the SAME App-Group store the app writes to, but LOCALLY (no
        // CloudKit). The on-disk rows are already there from the app + its sync,
        // so the ring reflects the latest local data, and the widget needs no
        // iCloud entitlement (which would require a provisioned container for the
        // widget's own App ID and breaks the distribution export). A failed open
        // degrades to the 0/total placeholder via try?, never a crash.
        let storeURL = AppGroupContainer.storeURL()
            ?? URL.applicationSupportDirectory.appending(path: "default.store")
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, migrationPlan: AppSchema.migrationPlan, configurations: [config])
    }
}

struct ProtocolGoalWidget: Widget {
    let kind: String = "ProtocolGoalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProtocolGoalWidgetProvider()) { entry in
            ProtocolGoalWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Protocol goal")
        .description("Today's protocol completion and your streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct ProtocolGoalWidgetView: View {
    let entry: ProtocolGoalWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                ring(lineWidth: 4)
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    Text("\(entry.streak)").font(.caption.weight(.bold)).monospacedDigit()
                }
            }
            .accessibilityLabel("\(entry.completedDomains) of \(entry.totalDomains) tracks done, \(entry.streak) day streak")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                ring(lineWidth: 5).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Protocol \(entry.completedDomains)/\(entry.totalDomains)").font(.headline)
                    Text("\(entry.streak)-day streak").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text("Protocol \(entry.completedDomains)/\(entry.totalDomains) \u{00B7} \(entry.streak)d")
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY'S PROTOCOL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                ring(lineWidth: 8)
                    .frame(width: 56, height: 56)
                    .overlay(
                        VStack(spacing: 0) {
                            Image(systemName: "flame.fill").font(.caption).foregroundStyle(.orange)
                            Text("\(entry.streak)").font(.title3.weight(.bold)).monospacedDigit()
                        }
                    )
                Text("\(entry.completedDomains) of \(entry.totalDomains) tracks closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        default:
            Text("\(entry.completedDomains)/\(entry.totalDomains)")
        }
    }

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, entry.progress)))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
