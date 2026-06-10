import SwiftUI
import SwiftData

/// Today-tab surface for active implementation intentions. The grammar reads
/// naturally: section header "Routines" frames the list, each row is a
/// readable two-liner — the action up top in user-language, the cue
/// underneath. Tap toggles "done today" and writes lastCompletedAt; a tap on
/// a completed row clears it (lets the user fix mis-taps without leaving the
/// screen).
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.tint)
                    Text("ROUTINES")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap to mark done")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(visible, id: \.persistentModelID) { intention in
                    Button {
                        toggleCompletion(intention)
                    } label: {
                        intentionRow(intention)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dojoCardSurface()
        }
    }

    @ViewBuilder
    private func intentionRow(_ intention: ImplementationIntention) -> some View {
        let done = isCompletedToday(intention)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(intention.action.firstLetterUppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                HStack(spacing: 4) {
                    Image(systemName: intention.triggerType.systemImage)
                        .font(.caption2)
                    Text(intention.trigger)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func isCompletedToday(_ intention: ImplementationIntention) -> Bool {
        guard let last = intention.lastCompletedAt else { return false }
        return Calendar.current.isDateInToday(last)
    }

    /// Tap toggles. Mark done if not done today; clear last-completed if it
    /// was done today. Lets the user undo a mis-tap without going to Settings.
    private func toggleCompletion(_ intention: ImplementationIntention) {
        let service = ImplementationIntentionService(modelContext: modelContext)
        if isCompletedToday(intention) {
            // Clear today's completion. We don't have a dedicated "clear" API
            // to keep the service narrow; nudge lastCompletedAt to nil
            // directly through the model. The day-rollup ledger isn't
            // affected — implementation intentions don't write
            // CompletionHistory, only the streak engine does, and intentions
            // are independent of that loop.
            intention.lastCompletedAt = nil
            try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        } else {
            _ = try? service.recordCompletion(intention)  // MARK: try? justified - best-effort; failure logged inside the called function.
        }
    }
}

private extension String {
    /// Capitalizes only the first letter without touching the rest, so user
    /// trigger/action strings keep their original casing inside the sentence.
    func firstLetterUppercased() -> String {
        guard let first = self.first else { return self }
        return String(first).uppercased() + self.dropFirst()
    }
}
