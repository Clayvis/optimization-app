import SwiftUI
import SwiftData

/// Inline inbox surfaced on TodayView. Shows pending suggestions with one-tap
/// dismiss / snooze. Identity-framed copy. Inline (not buried in a menu) per
/// the design principles addendum (friction reduction first).
@MainActor
struct ScheduleSuggestionInbox: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ScheduleSuggestion.generatedAt, order: .reverse)])
    private var allSuggestions: [ScheduleSuggestion]

    private var pending: [ScheduleSuggestion] {
        let pendingRaw = ScheduleSuggestionStatus.pending.rawValue
        return allSuggestions.filter { $0.statusRaw == pendingRaw }
    }

    var body: some View {
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "tray.fill")
                        .foregroundStyle(.tint)
                    Text("SCHEDULE SUGGESTIONS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pending.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                ForEach(pending.prefix(3), id: \.persistentModelID) { suggestion in
                    suggestionRow(suggestion)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: ScheduleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.summary)
                .font(.subheadline.weight(.medium))
            Text(suggestion.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    accept(suggestion)
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    dismiss(suggestion)
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func accept(_ suggestion: ScheduleSuggestion) {
        // Acceptance currently records intent only; applying the change to
        // ScheduleBlock will land in the M3.7+ schedule-mutator pass once the
        // payload schemas are pinned per changeType.
        suggestion.status = .accepted
        try? modelContext.save()
    }

    private func dismiss(_ suggestion: ScheduleSuggestion) {
        suggestion.status = .dismissed
        try? modelContext.save()
    }
}
