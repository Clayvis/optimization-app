import WidgetKit
import SwiftUI
import SwiftData

/// The single daily goal as a glanceable shape (build sheet section 1: the goal
/// IS the visual). A circular ring shows today's protocol completion across the
/// four tracks (workout / fasting / hydration / learning) with the master streak
/// number at its center, so a low-energy day still has a winnable, visible goal.
/// Device-timezone day boundaries match the in-app streak engine.
struct ProtocolGoalEntry: TimelineEntry, Sendable {
    let date: Date
    let streak: Int
    let completedDomains: Int   // 0...4
    let totalDomains: Int       // 4
}

struct ProtocolGoalTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ProtocolGoalEntry {
        ProtocolGoalEntry(date: Date(), streak: 7, completedDomains: 3, totalDomains: 4)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProtocolGoalEntry) -> Void) {
        completion(MainActor.assumeIsolated { Self.makeEntry(at: Date()) })
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProtocolGoalEntry>) -> Void) {
        let entries: [ProtocolGoalEntry] = MainActor.assumeIsolated {
            let now = Date()
            return stride(from: TimeInterval(0), through: 6 * 3600, by: 30 * 60)
                .map { Self.makeEntry(at: now.addingTimeInterval($0)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    @MainActor
    static func makeEntry(at date: Date) -> ProtocolGoalEntry {
        guard let container = sharedContainer() else {
            return ProtocolGoalEntry(date: date, streak: 0, completedDomains: 0, totalDomains: 4)
        }
        // Shared computation so the ring never drifts from the in-app metric.
        let snap = ProtocolGoalSnapshot.make(modelContext: container.mainContext, asOf: date)
        return ProtocolGoalEntry(
            date: date,
            streak: snap.streak,
            completedDomains: snap.completedDomains,
            totalDomains: snap.totalDomains
        )
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        ComplicationStore.container()
    }
}

struct ProtocolGoalComplication: Widget {
    let kind: String = "ProtocolGoalComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProtocolGoalTimelineProvider()) { entry in
            ProtocolGoalComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Protocol goal")
        .description("Today's protocol completion and your streak, as a glanceable ring.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct ProtocolGoalComplicationView: View {
    let entry: ProtocolGoalEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        entry.totalDomains > 0 ? Double(entry.completedDomains) / Double(entry.totalDomains) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Circle()
                    .stroke(Color.orange.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(entry.streak)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("\(entry.completedDomains) of \(entry.totalDomains) protocol tracks done, \(entry.streak) day streak")
        case .accessoryCorner:
            Text("\(entry.completedDomains)/\(entry.totalDomains)")
                .font(.caption2.weight(.bold))
                .widgetCurvesContent()
        case .accessoryInline:
            Text("Protocol \(entry.completedDomains)/\(entry.totalDomains) \u{00B7} \(entry.streak)d")
        default:
            Text("\(entry.completedDomains)/\(entry.totalDomains)")
        }
    }
}
