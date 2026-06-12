import SwiftUI
import SwiftData

/// V11 Settings surface for editing the user's daily anchors after
/// onboarding. Reuses ScheduleAnchorDraft from OnboardingView so both
/// surfaces speak the same shape. On save, prompts the user to re-apply
/// the most recently-applied template against the new anchors. Custom
/// blocks survive the re-apply because ScheduleSeed preserves
/// `isCustom == true` rows.
@MainActor
struct ScheduleAnchorEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var draft: ScheduleAnchorDraft = .init()
    @State private var didLoadDraft = false
    @State private var showReapplyPrompt = false
    @State private var feedback: String?
    @State private var pendingTemplate: ScheduleTemplate?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            Section {
                Text("Templates resolve against these anchors. Move them here when your routine shifts. You can re-apply the current template right after saving — your custom blocks survive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Daily anchors") {
                DatePicker(
                    "Wake time",
                    selection: $draft.wakeDate,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Bedtime",
                    selection: $draft.bedtimeDate,
                    displayedComponents: .hourAndMinute
                )
            }
            Section("Kids") {
                DatePicker(
                    "Drop off",
                    selection: $draft.kidDropDate,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Pickup",
                    selection: $draft.kidPickupDate,
                    displayedComponents: .hourAndMinute
                )
            }
            Section("Training") {
                Picker("Preferred window", selection: $draft.preferredTrainingTimeOfDay) {
                    ForEach(TimeOfDayPreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if draft.preferredTrainingTimeOfDay == .custom {
                    DatePicker(
                        "Training starts",
                        selection: $draft.trainingStartDate,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            Section("Learning") {
                DatePicker(
                    "Evening learning starts",
                    selection: $draft.learningStartDate,
                    displayedComponents: .hourAndMinute
                )
            }
            if draft.isValid == false {
                Section {
                    Text("Wake must be before bedtime and drop-off must be before pickup.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    save()
                } label: {
                    Label("Save anchors", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.isValid == false)
            }
            if let feedback {
                Section {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Time anchors")
        .task { loadDraftIfNeeded() }
        .confirmationDialog(
            "Re-apply current template with new anchors?",
            isPresented: $showReapplyPrompt,
            titleVisibility: .visible
        ) {
            Button("Re-apply (keep custom blocks)", role: .destructive) { reapply() }
            Button("Save anchors only", role: .cancel) {
                feedback = "Anchors saved."
                pendingTemplate = nil
            }
        } message: {
            Text("Your custom blocks survive. Seeded blocks are replaced using the new anchors.")
        }
    }

    private func loadDraftIfNeeded() {
        guard !didLoadDraft, let profile else { return }
        draft = ScheduleAnchorDraft.from(profile: profile)
        didLoadDraft = true
    }

    private func save() {
        guard draft.isValid, let profile else { return }
        draft.writeTo(profile: profile)
        do {
            try modelContext.save()
        } catch {
            feedback = "Save failed: \(error.localizedDescription)"
            return
        }
        // If the user has an inferable "current template" (from
        // lastAppliedTemplateRaw or a sensible default), offer to re-apply.
        // Otherwise just confirm the save inline.
        if let inferred = inferredCurrentTemplate(profile: profile) {
            pendingTemplate = inferred
            showReapplyPrompt = true
        } else {
            feedback = "Anchors saved."
        }
    }

    private func reapply() {
        guard let template = pendingTemplate, let profile else { return }
        let anchors = SchedulePlanner.AnchorSet.from(profile: profile)
        do {
            try ScheduleTemplateApplier.apply(
                template,
                modelContext: modelContext,
                anchors: anchors
            )
            feedback = "Re-applied: \(template.displayName)"
        } catch {
            feedback = "Re-apply failed: \(error.localizedDescription)"
        }
        pendingTemplate = nil
    }

    /// Best-effort inference of the template the user is currently on.
    /// V11 does not persist a `lastAppliedTemplate` field (additive-only
    /// migrations only), so we fall back to `.balanced` if the user has
    /// any seeded (non-custom, non-override) blocks. Returns nil if the
    /// schedule is empty or fully custom so the editor doesn't bug a
    /// user who built every block by hand.
    private func inferredCurrentTemplate(profile: UserProfile) -> ScheduleTemplate? {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let count = modelContext.fetchCountOrZero(descriptor)
        return count > 0 ? .balanced : nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScheduleAnchorEditorView()
            .modelContainer(for: [UserProfile.self, ScheduleBlock.self], inMemory: true)
    }
}
#endif
