import SwiftUI
import SwiftData

/// Today-tab visual surface for active implementation intentions. Per M4 spec:
/// "Active plans reveal in TodayView under 'When you... I will remind you to...'
/// section." Identity-framed copy. Tap on a plan logs completion (lastCompletedAt).
@MainActor
struct IntentionsStrip: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ImplementationIntention.createdAt, order: .forward)])
    private var intentions: [ImplementationIntention]

    private var visible: [ImplementationIntention] {
        Array(intentions.filter { $0.active }.prefix(5))
    }

    var body: some View {
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.tint)
                    Text("WHEN YOU…")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ForEach(visible, id: \.persistentModelID) { intention in
                    Button {
                        recordCompletion(intention)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: intention.triggerType.systemImage)
                                .foregroundStyle(.tint)
                                .font(.subheadline)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("When \(intention.trigger.lowercased())")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("I will \(intention.action.lowercased())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let last = intention.lastCompletedAt,
                               Calendar.current.isDateInToday(last) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func recordCompletion(_ intention: ImplementationIntention) {
        _ = try? ImplementationIntentionService(modelContext: modelContext)
            .recordCompletion(intention)
    }
}
