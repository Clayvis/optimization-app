import SwiftUI
import WidgetKit

/// The small value object passed from the app to WidgetKit through the shared
/// App Group. It deliberately contains no personal health samples—only the
/// already-resolved mascot presentation and today's aggregate goal count.
private struct MascotHomeEntry: TimelineEntry {
    let date: Date
    let state: String
    let assetName: String
    let reason: String
    let completedGoals: Int
    let totalGoals: Int
    let streak: Int

    var progress: Double {
        guard totalGoals > 0 else { return 0 }
        return min(1, max(0, Double(completedGoals) / Double(totalGoals)))
    }
}

private struct MascotHomeProvider: TimelineProvider {
    private let appGroupID = "group.com.rawlins.PersonalOptimization"

    func placeholder(in context: Context) -> MascotHomeEntry {
        MascotHomeEntry(
            date: Date(),
            state: "neutral",
            assetName: "NinjaMale_Neutral",
            reason: "Ready for today's protocol",
            completedGoals: 2,
            totalGoals: 4,
            streak: 7
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MascotHomeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MascotHomeEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> MascotHomeEntry {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return MascotHomeEntry(
                date: Date(), state: "neutral", assetName: "NinjaMale_Neutral",
                reason: "Open Optimization to begin", completedGoals: 0, totalGoals: 4, streak: 0
            )
        }

        let updatedAt = defaults.double(forKey: "mascotWidget.updatedAt")
        let date = updatedAt > 0 ? Date(timeIntervalSince1970: updatedAt) : Date()
        let total = defaults.integer(forKey: "mascotWidget.totalGoals")

        return MascotHomeEntry(
            date: date,
            state: defaults.string(forKey: "mascotWidget.state") ?? "neutral",
            assetName: defaults.string(forKey: "mascotWidget.assetName") ?? "NinjaMale_Neutral",
            reason: defaults.string(forKey: "mascotWidget.reason") ?? "Open Optimization to begin",
            completedGoals: defaults.integer(forKey: "mascotWidget.completedGoals"),
            totalGoals: total > 0 ? total : 4,
            streak: defaults.integer(forKey: "mascotWidget.streak")
        )
    }
}

struct MascotHomeWidget: Widget {
    let kind = "MascotHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MascotHomeProvider()) { entry in
            MascotHomeWidgetView(entry: entry)
                .widgetURL(URL(string: "personaloptimization://today"))
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.045, blue: 0.055),
                                 Color(red: 0.09, green: 0.10, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Dojo Mascot")
        .description("Keep your mascot, protocol progress, and streak on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct MascotHomeWidgetView: View {
    let entry: MascotHomeEntry
    @Environment(\.widgetFamily) private var family

    private let crimson = Color(red: 0.90, green: 0.22, blue: 0.29)
    private let gold = Color(red: 0.84, green: 0.64, blue: 0.23)

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    private var smallLayout: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.001, entry.progress))
                    .stroke(
                        AngularGradient(colors: [crimson, gold], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(entry.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(10)
            }
            .frame(width: 92, height: 92)

            Text("\(entry.completedGoals) of \(entry.totalGoals) complete")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            Image(entry.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 8) {
                Text("THE DOJO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(crimson)

                Text(entry.state.capitalized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(displayReason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)

                ProgressView(value: entry.progress)
                    .tint(crimson)

                HStack(spacing: 10) {
                    Label("\(entry.completedGoals)/\(entry.totalGoals)", systemImage: "checkmark.seal.fill")
                    if entry.streak > 0 {
                        Label("\(entry.streak)d", systemImage: "flame.fill")
                            .foregroundStyle(gold)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var displayReason: String {
        let reason = entry.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty || reason == "default" ? "Ready for today's protocol" : reason
    }

    private var accessibilitySummary: String {
        "Mascot \(entry.state), \(entry.completedGoals) of \(entry.totalGoals) goals complete, \(entry.streak) day streak"
    }
}

#Preview(as: .systemSmall) {
    MascotHomeWidget()
} timeline: {
    MascotHomeEntry(date: Date(), state: "proud", assetName: "NinjaMale_Proud",
                    reason: "workout streak milestone", completedGoals: 3, totalGoals: 4, streak: 12)
}

#Preview(as: .systemMedium) {
    MascotHomeWidget()
} timeline: {
    MascotHomeEntry(date: Date(), state: "proud", assetName: "NinjaMale_Proud",
                    reason: "workout streak milestone", completedGoals: 3, totalGoals: 4, streak: 12)
}
