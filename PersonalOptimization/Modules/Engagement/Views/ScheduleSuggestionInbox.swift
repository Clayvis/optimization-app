import SwiftUI
import SwiftData
import CryptoKit

/// Inline inbox surfaced on TodayView. Shows pending suggestions with one-tap
/// dismiss / snooze. Identity-framed copy. Inline (not buried in a menu) per
/// the design principles addendum (friction reduction first).
///
/// M4.1: dismissing a suggestion now writes a CoachMemory row keyed on the
/// suggestion's change signature, so the next adaptation pass won't re-surface
/// the same idea. Also shipped: a "Why this?" disclosure that exposes the
/// pattern data backing the suggestion, and a summary-line header.
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
                Text(headerSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

    private var headerSummary: String {
        let count = pending.count
        if count == 1 { return "1 suggestion ready." }
        return "\(count) suggestions ready."
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: ScheduleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.summary)
                .font(.subheadline.weight(.medium))
            Text(suggestion.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !suggestion.rationaleData.isEmpty {
                DisclosureGroup("Why this?") {
                    ForEach(parseRationale(suggestion.rationaleData), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.top, 2)
            }

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
        recordRejection(suggestion)
    }

    /// Writes a CoachMemory row keyed by the suggestion's change signature.
    /// Key shape: "rejected_suggestion_<sha256-prefix>". Expires in 60 days;
    /// the memory service auto-prunes on read.
    private func recordRejection(_ suggestion: ScheduleSuggestion) {
        let key = Self.rejectionKey(changeType: suggestion.changeTypeRaw,
                                    payload: suggestion.changePayload)
        let memoryService = CoachMemoryService(modelContext: modelContext)
        // Compact one-line value so prompts can scan a list quickly.
        let value = "\(suggestion.changeType.rawValue): \(suggestion.summary)"
        _ = try? memoryService.add(value: value, key: key, importance: 2, expiresIn: 60)
    }

    /// Deterministic key for a suggestion's change signature. Same shape →
    /// same key → CoachMemoryService.add dedupes (overwrites prior with same key).
    static func rejectionKey(changeType: String, payload: String) -> String {
        let normalized = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(changeType)|\(normalized)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "rejected_suggestion_\(hex)"
    }

    /// Parses the comma-separated rationale data stored on the suggestion
    /// into human-readable bullet lines.
    /// Input shape: "wednesday_afternoon_skip:0.78,morning_lifts_drift:0.62"
    private func parseRationale(_ data: String) -> [String] {
        data
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { entry -> String in
                let parts = entry.split(separator: ":")
                guard parts.count == 2 else { return entry }
                let pattern = parts[0].replacingOccurrences(of: "_", with: " ")
                return "Pattern: \(pattern) · confidence \(parts[1])"
            }
    }
}
