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

    /// Bundle resource filename (no extension) for the JSON seed. Blank uses an
    /// empty seed. Each non-blank template maps to a generic, non-personal JSON
    /// so new users (e.g., partner installs) never inherit Clay's
    /// `default_schedule.json`.
    var resourceName: String? {
        switch self {
        case .balanced:        return "schedule_balanced"
        case .gymFocused:      return "schedule_gym_focused"
        case .languageFocused: return "schedule_language_focused"
        case .fastingFocused:  return "schedule_fasting_focused"
        case .blank:           return nil
        }
    }
}

/// Applies a ScheduleTemplate by re-seeding from the chosen JSON. Preserves
/// `isCustom` blocks (user-defined rows survive across template swaps).
/// Each non-blank template maps to its own generic JSON via `resourceName`.
@MainActor
enum ScheduleTemplateApplier {
    /// Applies a template using the SchedulePlanner against the supplied
    /// anchors. The four bundled templates ship in v2 (parametric) form;
    /// the planner resolves their anchor-based blocks against
    /// `anchors.trainingStartHHMM` (and friends) so a user who picked a
    /// morning training window gets 06:30 lifts instead of 18:00 lifts.
    ///
    /// Callers that don't have anchors handy can pass
    /// `.defaultForFallback` — that mirrors the v1 evening-anchor times so
    /// nothing surprises a legacy caller. New callers (onboarding, settings)
    /// MUST pass the user's actual anchors so the template respects them.
    static func apply(_ template: ScheduleTemplate,
                      modelContext: ModelContext,
                      anchors: SchedulePlanner.AnchorSet = .defaultForFallback,
                      bundle: Bundle = .main) throws {
        if template == .blank {
            // Wipe non-custom blocks; do not re-seed.
            let descriptor = FetchDescriptor<ScheduleBlock>(
                predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
            )
            // MARK: - try? justified because best-effort cleanup; the save
            // below catches the underlying failure if SwiftData is broken.
            let toDelete = (try? modelContext.fetch(descriptor)) ?? []
            for block in toDelete { modelContext.delete(block) }
            try modelContext.save()
            return
        }
        guard let resourceName = template.resourceName else {
            // Defensive: every non-blank template above has a resourceName.
            // If a new case is added without one, fall back to blank semantics.
            return
        }
        try ScheduleSeed.resetToParametricTemplate(
            resourceName: resourceName,
            anchors: anchors,
            modelContext: modelContext,
            bundle: bundle
        )
    }
}

extension SchedulePlanner.AnchorSet {
    /// Fallback anchors used by callers that haven't collected the user's
    /// preferences yet. Mirrors the original v1 hardcoded times so the
    /// behavior is no worse than before the re-haul. Production code paths
    /// (onboarding, settings, re-apply) should pass the live profile's
    /// anchors via `.from(profile:)` instead of relying on this.
    static let defaultForFallback = SchedulePlanner.AnchorSet(
        wakeHHMM: "06:00",
        bedtimeHHMM: "22:00",
        kidDropHHMM: "09:00",
        kidPickupHHMM: "17:00",
        trainingStartHHMM: "18:00",
        learningStartHHMM: "19:00"
    )
}
