import WidgetKit
import SwiftUI
import SwiftData

struct MascotEntry: TimelineEntry, Sendable {
    let date: Date
    let stateRaw: String
    let assetName: String
    let triggerReason: String
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
        MascotEntry(date: Date(), stateRaw: "neutral", assetName: "NinjaMale_Neutral", triggerReason: "default")
    }

    @MainActor
    static func makeEntry(at date: Date) -> MascotEntry {
        guard let container = sharedContainer() else {
            return staticPlaceholder()
        }
        let inputs = CharacterStateService.gatherInputs(modelContext: container.mainContext,
                                                        timezone: TimeZone(identifier: "Asia/Tokyo") ?? .current)
        let resolved = CharacterStateService.resolve(inputs: inputs)
        // Variant-aware: read the user's chosen mascot variant so the
        // complication renders the female ninja for the wife test profile
        // without code changes per variant.
        let variant = inputs.profile?.mascotVariant ?? "ninja_male"
        return MascotEntry(date: date,
                           stateRaw: resolved.state.rawValue,
                           assetName: resolved.state.assetName(for: variant),
                           triggerReason: resolved.reason)
    }

    @MainActor
    private static func sharedContainer() -> ModelContainer? {
        let schema = Schema(versionedSchema: SchemaV7.self)
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

struct MascotComplication: Widget {
    let kind: String = "MascotComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MascotTimelineProvider()) { entry in
            MascotComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mascot")
        .description("Shows your character's current emotional state.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct MascotComplicationView: View {
    let entry: MascotEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(entry.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            }
        case .accessoryInline:
            Text(entry.stateRaw.capitalized)
        case .accessoryCorner:
            Text(entry.stateRaw.capitalized.prefix(3))
                .font(.caption2.weight(.bold))
                .widgetCurvesContent()
        default:
            Text(entry.stateRaw.capitalized)
        }
    }
}
