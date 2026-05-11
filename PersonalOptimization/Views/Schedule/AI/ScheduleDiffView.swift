#if os(iOS)
import SwiftUI
import SwiftData

/// Side-by-side preview of the existing weekly schedule vs the AI-proposed
/// schedule. Stacked layout for iPhone width (existing first, proposed
/// second). Tag each proposed block with the visual change indicator.
///
/// Footer actions: Apply, Discard. The optional onApplied closure lets
/// onboarding advance to the next screen instead of dismissing the stack.
@MainActor
struct ScheduleDiffView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingBlocks: [ScheduleBlock]

    let drafts: [ScheduleBlockDraft]
    let rationale: String
    let warnings: [String]
    let runID: PersistentIdentifier
    let anchorEvents: [String]
    var onApplied: (() -> Void)? = nil

    @State private var applying: Bool = false
    @State private var applyError: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Nothing applied yet — tap Apply to make this your week.")
                        .font(.callout.weight(.medium))
                }
                .padding(.vertical, 4)
            }

            if !rationale.isEmpty {
                Section {
                    Text(rationale)
                        .font(.body)
                }
            }

            if !warnings.isEmpty {
                Section("Notes") {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }

            Section("Proposed week") {
                ForEach(1...7, id: \.self) { day in
                    let dayDrafts = drafts
                        .filter { $0.dayOfWeek == day }
                        .sorted { $0.startTime < $1.startTime }
                    if !dayDrafts.isEmpty {
                        DisclosureGroup(weekdayLabel(day) + " · \(dayDrafts.count) block\(dayDrafts.count == 1 ? "" : "s")") {
                            ForEach(Array(dayDrafts.enumerated()), id: \.offset) { _, draft in
                                ProposedBlockRow(draft: draft, change: classify(draft))
                            }
                        }
                    }
                }
            }

            Section("Current week (will be replaced)") {
                ForEach(1...7, id: \.self) { day in
                    let dayBlocks = existingBlocks
                        .filter { !$0.isCustom && !$0.isOverride && $0.dayOfWeek == day }
                        .sorted { $0.startTime < $1.startTime }
                    if !dayBlocks.isEmpty {
                        DisclosureGroup(weekdayLabel(day) + " · \(dayBlocks.count) block\(dayBlocks.count == 1 ? "" : "s")") {
                            ForEach(dayBlocks, id: \.persistentModelID) { block in
                                ExistingBlockRow(block: block)
                            }
                        }
                    }
                }
                if existingBlocks.allSatisfy({ $0.isCustom || $0.isOverride }) {
                    Text("Nothing seeded yet. Custom blocks (if any) will be kept.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            if let applyError {
                Section {
                    Text(applyError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button {
                    Task { await applyProposal() }
                } label: {
                    HStack {
                        if applying {
                            ProgressView()
                        }
                        Label("Apply — this is my week", systemImage: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(applying)

                Button(role: .destructive) {
                    discard()
                } label: {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(applying)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func classify(_ draft: ScheduleBlockDraft) -> ChangeKind {
        // Same day + same activity = unchanged; different time but matching activity = modified;
        // no match by activity on that day = added. (Removed is implicit on the existing side.)
        let candidates = existingBlocks.filter {
            !$0.isCustom && !$0.isOverride && $0.dayOfWeek == draft.dayOfWeek
        }
        if candidates.isEmpty { return .added }
        if let exact = candidates.first(where: { $0.activity == draft.activity }) {
            if exact.startTime == draft.startTime && exact.endTime == draft.endTime {
                return .unchanged
            }
            return .modified
        }
        // Same module, different activity label still counts as modified.
        if let module = draft.module,
           candidates.contains(where: { $0.module == module }) {
            return .modified
        }
        return .added
    }

    private func applyProposal() async {
        applying = true
        applyError = nil
        defer { applying = false }

        do {
            try ScheduleSeed.applyDrafts(drafts,
                                         anchorEvents: anchorEvents,
                                         modelContext: modelContext)
            ScheduleAIService(modelContext: modelContext).markAccepted(runID: runID)
            onApplied?()
            dismiss()
        } catch {
            applyError = "Couldn't apply: \(error.localizedDescription)"
        }
    }

    private func discard() {
        ScheduleAIService(modelContext: modelContext).markDiscarded(runID: runID)
        dismiss()
    }

    private func weekdayLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Mon"
        case 2: return "Tue"
        case 3: return "Wed"
        case 4: return "Thu"
        case 5: return "Fri"
        case 6: return "Sat"
        default: return "Sun"
        }
    }
}

enum ChangeKind {
    case added, removed, modified, unchanged

    var systemImage: String {
        switch self {
        case .added:     return "plus.circle.fill"
        case .removed:   return "minus.circle.fill"
        case .modified:  return "arrow.triangle.2.circlepath"
        case .unchanged: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .added:     return .green
        case .removed:   return .red
        case .modified:  return .yellow
        case .unchanged: return .gray
        }
    }

    var label: String {
        switch self {
        case .added:     return "Added"
        case .removed:   return "Removed"
        case .modified:  return "Changed"
        case .unchanged: return "Same"
        }
    }
}

@MainActor
private struct ProposedBlockRow: View {
    let draft: ScheduleBlockDraft
    let change: ChangeKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: change.systemImage)
                .foregroundStyle(change.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.activity)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text("\(draft.startTime)–\(draft.endTime)")
                    if let anchor = draft.anchorEvent {
                        Text("· \(anchorLabel(anchor, offset: draft.anchorOffsetMinutes))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(change.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(change.color)
        }
        .padding(.vertical, 4)
        .opacity(change == .unchanged ? 0.5 : 1.0)
    }

    private func anchorLabel(_ anchor: String, offset: Int?) -> String {
        let pretty = anchor.replacingOccurrences(of: "_", with: " ")
        guard let offset, offset != 0 else { return pretty }
        let sign = offset > 0 ? "after" : "before"
        return "\(abs(offset)) min \(sign) \(pretty)"
    }
}

@MainActor
private struct ExistingBlockRow: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(block.activity)
                    .font(.body)
                Text("\(block.startTime)–\(block.endTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
#endif
