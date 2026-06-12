import WidgetKit
import SwiftUI
import SwiftData

struct MascotEntry: TimelineEntry, Sendable {
    let date: Date
    let stateRaw: String
    let assetName: String
    let triggerReason: String
    /// Today's protocol tally so the rectangular (Smart Stack) family can
    /// show the goals next to the character.
    let completedGoals: Int
    let totalGoals: Int
}

struct MascotTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> MascotEntry {
        Self.staticPlaceholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (MascotEntry) -> Void) {
        let entry = MainActor.assumeIsolated { Self.makeEntry(at: Date()) }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MascotEntry>) -> Void) {
        // Mascot complication updates every 30 minutes. Sparser than schedule complication
        // to stay within the <1%/12hr battery budget noted in M3.5 perf goals.
        let entries: [MascotEntry] = MainActor.assumeIsolated {
            let now = Date()
            var collected: [MascotEntry] = []
            let step: TimeInterval = 30 * 60
            for offset in stride(from: TimeInterval(0), through: 6 * 3600, by: step) {
                collected.append(Self.makeEntry(at: now.addingTimeInterval(offset)))
            }
            return collected
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func staticPlaceholder() -> MascotEntry {
        MascotEntry(date: Date(), stateRaw: "neutral", assetName: "NinjaMale_Neutral",
                    triggerReason: "default", completedGoals: 2, totalGoals: 4)
    }

    @MainActor
    static func makeEntry(at date: Date) -> MascotEntry {
        guard let container = sharedContainer() else {
            return staticPlaceholder()
        }
        // Device/user timezone, not a hardcoded JST pin, so the mascot's
        // time-of-day state (thirsty, fasting) follows travel.
        let tz = UserCalendar.timezone(modelContext: container.mainContext)
        let inputs = CharacterStateService.gatherInputs(modelContext: container.mainContext,
                                                        timezone: tz)
        let resolved = CharacterStateService.resolve(inputs: inputs)
        // Variant-aware: read the user's chosen mascot variant so the
        // complication renders the female ninja for the wife test profile
        // without code changes per variant.
        let variant = inputs.profile?.mascotVariant ?? "ninja_male"
        // Same rules as the phone's master metric and the watch home ring.
        let snap = ProtocolGoalSnapshot.make(modelContext: container.mainContext, asOf: date)
        return MascotEntry(date: date,
                           stateRaw: resolved.state.rawValue,
                           assetName: resolved.state.assetName(for: variant),
                           triggerReason: resolved.reason,
                           completedGoals: snap.completedDomains,
                           totalGoals: snap.totalDomains)
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        ComplicationStore.container()
    }
}

struct MascotComplication: Widget {
    let kind: String = "MascotComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MascotTimelineProvider()) { entry in
            MascotComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mascot")
        .description("Your character and today's goals, at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner, .accessoryRectangular])
    }
}

struct MascotComplicationView: View {
    let entry: MascotEntry

    @Environment(\.widgetFamily) var family

    private var progress: Double {
        entry.totalGoals > 0 ? Double(entry.completedGoals) / Double(entry.totalGoals) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Goal ring around the mascot: the watch-face tamagotchi.
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                Image(entry.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            }
        case .accessoryRectangular:
            // Smart Stack card: mascot beside today's goals.
            HStack(spacing: 8) {
                Image(entry.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.completedGoals) of \(entry.totalGoals) goals")
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                    Text(entry.stateRaw.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Gauge(value: progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mascot \(entry.stateRaw), \(entry.completedGoals) of \(entry.totalGoals) goals done")
        case .accessoryInline:
            Text("\(entry.stateRaw.capitalized) · \(entry.completedGoals)/\(entry.totalGoals)")
        case .accessoryCorner:
            Text(entry.stateRaw.capitalized.prefix(3))
                .font(.caption2.weight(.bold))
                .widgetCurvesContent()
        default:
            Text(entry.stateRaw.capitalized)
        }
    }
}
