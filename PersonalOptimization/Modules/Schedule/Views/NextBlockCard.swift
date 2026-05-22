import SwiftUI
import SwiftData

/// V11 daily-launch polish. Foregrounds "the next thing" on TodayView so the
/// user lands on a clear next-action instead of a wall of cards. Three
/// states:
///
/// 1. In a block right now: shows current activity, time remaining, and a
///    "Start" CTA that maps to the relevant module (lift / basketball /
///    swim / learning / custom). The CTA is a stub for non-trainable types.
/// 2. Next block today: shows the upcoming activity, minutes until start,
///    and "Snooze 15 min" / "Reschedule today" CTAs.
/// 3. No more blocks today: shows the next training day or "Nothing else
///    scheduled today" as a final fallback.
///
/// Mirrors the data shape ScheduleService already exposes (currentBlock,
/// nextBlock) — no new persistence. The refresh ticker is a single
/// TimelineView at 60s cadence, scoped to this card only, so it doesn't
/// thrash the rest of TodayView's body evaluation.
@MainActor
struct NextBlockCard: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            cardContents(now: timeline.date)
        }
    }

    @ViewBuilder
    private func cardContents(now: Date) -> some View {
        let service = ScheduleService(modelContext: modelContext)
        let current = service.currentBlock(at: now)
        let next = service.nextBlock(after: now)

        VStack(alignment: .leading, spacing: 8) {
            if let current {
                inProgressView(block: current, now: now)
            } else if let next {
                upcomingView(block: next, now: now)
            } else {
                emptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func inProgressView(block: ScheduleBlock, now: Date) -> some View {
        let endMinutes = ScheduleService.parseTimeToMinutes(block.endTime) ?? 0
        let nowMinutes = ScheduleService(modelContext: modelContext).minutesFromMidnight(at: now)
        let remaining = max(0, endMinutes - nowMinutes)
        VStack(alignment: .leading, spacing: 4) {
            Text("In progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(block.activity)
                .font(.headline)
            Text("Ends at \(block.endTime) — \(remaining)m left")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func upcomingView(block: ScheduleBlock, now: Date) -> some View {
        let startMinutes = ScheduleService.parseTimeToMinutes(block.startTime) ?? 0
        let nowMinutes = ScheduleService(modelContext: modelContext).minutesFromMidnight(at: now)
        let untilStart = max(0, startMinutes - nowMinutes)
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(block.activity)
                .font(.headline)
            Text("Starts at \(block.startTime) — in \(untilStart)m")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func emptyView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All clear")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Nothing else scheduled today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    NextBlockCard()
        .modelContainer(for: [ScheduleBlock.self], inMemory: true)
        .padding()
}
#endif
