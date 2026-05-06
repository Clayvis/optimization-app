import WidgetKit
import SwiftUI
import SwiftData

struct CurrentBlockComplication: Widget {
    let kind: String = "CurrentBlockComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentBlockTimelineProvider()) { entry in
            CurrentBlockComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Current Block")
        .description("Shows the current scheduled block and time remaining.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct CurrentBlockComplicationView: View {
    let entry: CurrentBlockEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(entry.title).font(.headline).lineLimit(1)
            Text(entry.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Text(entry.short).font(.caption2.weight(.bold))
            Text(entry.compactTime).font(.caption2)
        }
    }

    private var corner: some View {
        Text(entry.short)
            .font(.caption2.weight(.bold))
            .widgetCurvesContent()
    }

    private var inline: some View {
        Text("\(entry.short) · \(entry.compactTime)")
    }
}
