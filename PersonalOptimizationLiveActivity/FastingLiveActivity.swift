import ActivityKit
import WidgetKit
import SwiftUI

struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            LockScreenFastingView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Fast", systemImage: "timer")
                        .foregroundStyle(.tint)
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...context.attributes.endDate, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.windowLabel.capitalized + " window")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.attributes.startDate...context.attributes.endDate, countsDown: false)
                        .tint(.accentColor)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startDate...context.attributes.endDate, countsDown: true, showsHours: true)
                    .monospacedDigit()
                    .frame(maxWidth: 60)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.tint)
            }
        }
    }
}

struct LockScreenFastingView: View {
    let context: ActivityViewContext<FastingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Fasting", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text(context.attributes.windowLabel.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.2))
                    .clipShape(Capsule())
            }

            ProgressView(timerInterval: context.attributes.startDate...context.attributes.endDate, countsDown: false)
                .tint(.accentColor)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(timerInterval: context.attributes.startDate...context.attributes.endDate, countsDown: true)
                        .monospacedDigit()
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Ends")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(context.attributes.endDate, style: .time)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding()
    }
}
