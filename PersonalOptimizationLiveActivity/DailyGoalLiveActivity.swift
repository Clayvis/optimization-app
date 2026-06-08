import ActivityKit
import WidgetKit
import SwiftUI

/// The daily protocol goal as a glanceable shape on the lock screen and Dynamic
/// Island. A ring fills as the day's tracks close; the streak sits at the center.
/// No number is required to read state, which is the point.
struct DailyGoalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailyGoalActivityAttributes.self) { context in
            LockScreenDailyGoalView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Protocol", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedDomains)/\(context.state.totalDomains)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isComplete ? "Today belongs to the disciplined" : "\(context.state.streak)-day streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.orange)
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(context.state.completedDomains)/\(context.state.totalDomains)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            } minimal: {
                DailyGoalRing(progress: context.state.progress, lineWidth: 3)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

struct LockScreenDailyGoalView: View {
    let state: DailyGoalActivityAttributes.State

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                DailyGoalRing(progress: state.progress, lineWidth: 6)
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(state.streak)")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's protocol")
                    .font(.headline)
                Text(state.isComplete
                     ? "Today belongs to the disciplined."
                     : "\(state.completedDomains) of \(state.totalDomains) tracks closed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

/// Reusable completion ring. Filled arc + faint track, rounded cap.
struct DailyGoalRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
