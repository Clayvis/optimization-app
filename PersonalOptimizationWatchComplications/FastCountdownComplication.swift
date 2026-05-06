import WidgetKit
import SwiftUI
import SwiftData

struct FastCountdownComplication: Widget {
    let kind: String = "FastCountdownComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastCountdownTimelineProvider()) { entry in
            FastCountdownComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fast Countdown")
        .description("Time remaining in current fast or until next fast.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct FastCountdownComplicationView: View {
    let entry: FastCountdownEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCircular:
            circular
        case .accessoryInline:
            inline
        case .accessoryCorner:
            corner
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(entry.primary).font(.headline).monospacedDigit()
            Text(entry.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var circular: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(entry.shortLabel).font(.caption2.weight(.bold))
                Text(entry.compactDuration).font(.caption2.weight(.semibold)).monospacedDigit()
            }
        }
    }

    private var inline: some View {
        Text("\(entry.shortLabel) \(entry.compactDuration)")
    }

    private var corner: some View {
        Text(entry.compactDuration)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .widgetCurvesContent()
    }
}
