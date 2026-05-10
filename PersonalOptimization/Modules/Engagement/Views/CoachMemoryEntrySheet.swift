import SwiftUI
import SwiftData

/// Lightweight sheet for adding ephemeral context the Coach should remember.
/// Surfaces a few pre-canned templates ("Sick kid this week", "Achilles
/// flaring up", "Travel 5/15-5/22") plus a free-text entry. Auto-expiry is
/// 7 days unless the user picks "Persistent".
@MainActor
struct CoachMemoryEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var importance: Int = 3
    @State private var expiry: Expiry = .week

    enum Expiry: String, CaseIterable, Identifiable {
        case threeDays = "3 days"
        case week = "1 week"
        case month = "1 month"
        case persistent = "Persistent"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .threeDays:  return 3
            case .week:       return 7
            case .month:      return 30
            case .persistent: return nil
            }
        }
    }

    private let presets: [String] = [
        "Sick kid this week, sleep is bad.",
        "Achilles flaring up — keep load light.",
        "Traveling for work, gym access limited.",
        "High-stress week at work, going easy.",
        "On vacation; logging only the basics."
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick presets") {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            text = preset
                        } label: {
                            Label(preset, systemImage: "text.quote")
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                Section("What should the Coach remember?") {
                    TextField("Free text", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("How long?") {
                    Picker("Expiry", selection: $expiry) {
                        ForEach(Expiry.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Importance") {
                    Stepper("Priority: \(importance)/5", value: $importance, in: 1...5)
                }
                Section {
                    Text("The Coach will reference this until it expires. Recovery flags from this note (achilles, sleep) feed into prescription downgrades automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Tell the Coach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let key = derivedKey(for: text)
        _ = try? CoachMemoryService(modelContext: modelContext)
            .add(value: text,
                 key: key,
                 importance: importance,
                 expiresIn: expiry.days)
    }

    /// Auto-derive a dedupe key from common phrasings so re-saving "achilles
    /// flaring" replaces the previous note instead of stacking duplicates.
    private func derivedKey(for value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("achilles") { return "achilles_flare" }
        if lower.contains("sick") { return "user_sick" }
        if lower.contains("travel") || lower.contains("vacation") { return "travel" }
        if lower.contains("stress") { return "stress" }
        return ""  // empty = no dedup
    }
}
