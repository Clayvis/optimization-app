import SwiftUI
import SwiftData

/// Wife-onboarding-readiness: pick a template (gym, language, fasting, balanced,
/// or blank) and apply it. Replaces the current schedule. User-marked
/// `isCustom` blocks are preserved across re-seeds, but the template chooser
/// confirms before any wipe.
@MainActor
struct ScheduleTemplateChooserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pendingChoice: ScheduleTemplate?
    @State private var showConfirmation = false
    @State private var feedback: String?

    var body: some View {
        Form {
            Section {
                Text("Pick a starting schedule. Your custom blocks (marked CUSTOM) are preserved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(ScheduleTemplate.allCases) { template in
                Section {
                    templateRow(template)
                }
            }

            if let feedback {
                Section {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Schedule templates")
        .confirmationDialog(
            "Apply \(pendingChoice?.displayName ?? "")?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply (keep my custom blocks)", role: .destructive) {
                if let choice = pendingChoice { apply(choice) }
                pendingChoice = nil
            }
            Button("Cancel", role: .cancel) { pendingChoice = nil }
        } message: {
            Text("Existing seeded blocks will be replaced. Your custom blocks survive.")
        }
    }

    @ViewBuilder
    private func templateRow(_ template: ScheduleTemplate) -> some View {
        Button {
            pendingChoice = template
            showConfirmation = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.displayName)
                        .font(.body.weight(.semibold))
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func apply(_ template: ScheduleTemplate) {
        do {
            try ScheduleTemplateApplier.apply(template, modelContext: modelContext)
            feedback = "Applied: \(template.displayName)"
        } catch {
            feedback = "Failed: \(error.localizedDescription)"
        }
    }
}

enum ScheduleTemplate: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case gymFocused = "gym_focused"
    case languageFocused = "language_focused"
    case fastingFocused = "fasting_focused"
    case blank

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced:        return "Balanced"
        case .gymFocused:      return "Gym focused"
        case .languageFocused: return "Language focused"
        case .fastingFocused:  return "Fasting focused"
        case .blank:           return "Blank slate"
        }
    }

    var summary: String {
        switch self {
        case .balanced:        return "Default mix: lift, basketball, swim, learning, fasting."
        case .gymFocused:      return "Lifts on Mon/Wed/Fri; recovery in between."
        case .languageFocused: return "Daily learning blocks; lighter training cadence."
        case .fastingFocused:  return "Built around the fasting window; minimal disruption."
        case .blank:           return "Empty slate. Build it yourself."
        }
    }

    var systemImage: String {
        switch self {
        case .balanced:        return "circle.grid.cross"
        case .gymFocused:      return "figure.strengthtraining.traditional"
        case .languageFocused: return "book.closed.fill"
        case .fastingFocused:  return "timer"
        case .blank:           return "doc"
        }
    }

    /// Bundle resource filename for the JSON seed. Blank uses an empty array.
    var resourceName: String? {
        switch self {
        case .balanced:        return "default_schedule"
        case .gymFocused:      return "default_schedule"
        case .languageFocused: return "default_schedule"
        case .fastingFocused:  return "default_schedule"
        case .blank:           return "default_schedule_blank"
        }
    }
}

/// Applies a ScheduleTemplate by re-seeding from the chosen JSON. Preserves
/// `isCustom` blocks. M3.7 ships only the balanced + blank seeds; the focused
/// templates currently fall back to the balanced seed and will be expanded
/// by future seed JSONs without code changes.
@MainActor
enum ScheduleTemplateApplier {
    static func apply(_ template: ScheduleTemplate,
                      modelContext: ModelContext,
                      bundle: Bundle = .main) throws {
        if template == .blank {
            // Wipe non-custom blocks; do not re-seed.
            let descriptor = FetchDescriptor<ScheduleBlock>(
                predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
            )
            let toDelete = (try? modelContext.fetch(descriptor)) ?? []
            for block in toDelete { modelContext.delete(block) }
            try modelContext.save()
            return
        }
        // Other templates: reset-to-default uses the bundled default_schedule.json
        // for now. When focused JSON seeds land, route through resourceName.
        try ScheduleSeed.resetToDefault(modelContext: modelContext, bundle: bundle)
    }
}
