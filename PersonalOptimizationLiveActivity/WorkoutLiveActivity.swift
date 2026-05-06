import ActivityKit
import WidgetKit
import SwiftUI

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.workoutType, systemImage: "figure.run")
                        .foregroundStyle(.tint)
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startDate, style: .timer)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.primaryMetric)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "figure.run").foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.attributes.startDate, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 60)
            } minimal: {
                Image(systemName: "figure.run").foregroundStyle(.tint)
            }
        }
    }
}

struct LockScreenWorkoutView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.workoutType, systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                Text(context.attributes.startDate, style: .timer)
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
            }
            Text(context.state.primaryMetric)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
