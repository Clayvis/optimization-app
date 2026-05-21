#if os(iOS)
import SwiftUI
import SwiftData

/// Form that collects a `ScheduleIntake`, calls `ScheduleAIService.generate`,
/// and pushes to `ScheduleDiffView` on success. Used from onboarding (the
/// "Build me a schedule" tile) and Settings ("Generate with AI" button).
@MainActor
struct ScheduleGenerationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var intake: ScheduleIntake = .blank
    @State private var newAnchor: String = ""
    @State private var isGenerating: Bool = false
    @State private var generationError: String?
    @State private var proposalResult: ScheduleAIService.Result?

    /// Caller can opt out of dismiss-on-apply (onboarding wants to advance to
    /// the next screen instead of dismissing the navigation stack).
    var onApplied: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("Goals") {
                Picker("Primary goal", selection: $intake.primaryGoal) {
                    ForEach(ScheduleIntake.PrimaryGoal.allCases, id: \.self) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("What does a great week look like for you?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $intake.freeText)
                        .frame(minHeight: 80)
                }
            }

            Section("Available days") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(weekdayLabel(day), isOn: Binding(
                        get: { intake.availableDays.contains(day) },
                        set: { isOn in
                            if isOn { intake.availableDays.insert(day) }
                            else { intake.availableDays.remove(day) }
                        }
                    ))
                }
            }

            Section {
                Stepper("Earliest I can start: \(format(intake.earliestTrainingHour))",
                        value: $intake.earliestTrainingHour, in: 0...23)
                Stepper("Latest I can finish: \(format(intake.latestTrainingHour))",
                        value: $intake.latestTrainingHour, in: 0...23)
                Stepper("Target sessions/week: \(intake.weeklyTrainingTargetSessions)",
                        value: $intake.weeklyTrainingTargetSessions, in: 1...7)
                Stepper("Realistic time/day: \(intake.availableTimeMinutesPerDay) min",
                        value: $intake.availableTimeMinutesPerDay,
                        in: 30...480, step: 15)
            } header: {
                Text("When can you actually work out?")
            } footer: {
                Text("The AI will only schedule training blocks (lifts, cardio, etc.) between these times. Mornings before kids, lunch breaks, evenings after dinner — pick what's real. Learning and recovery blocks aren't restricted to this window.")
            }

            Section {
                ForEach(OptimizationFocus.builtIn, id: \.rawValue) { focus in
                    Toggle(isOn: focusBinding(for: focus)) {
                        Label(focus.displayName, systemImage: focus.systemImage)
                    }
                }
            } header: {
                Text("What are you optimizing?")
            } footer: {
                Text("Language, music, strength, sleep — pick what you're sharpening this season. Each one gets at least one weekly block.")
            }

            Section("Sleep window") {
                Stepper("Start: \(format(intake.sleepStartHour))",
                        value: $intake.sleepStartHour, in: 0...23)
                Stepper("End: \(format(intake.sleepEndHour))",
                        value: $intake.sleepEndHour, in: 0...23)
            }

            Section {
                ForEach(intake.anchorEvents, id: \.self) { anchor in
                    HStack {
                        Text(anchor.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        Button(role: .destructive) {
                            intake.anchorEvents.removeAll { $0 == anchor }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                HStack {
                    TextField("e.g. after_kid_dropoff", text: $newAnchor)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Button {
                        addAnchor()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newAnchor.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Anchors (optional)")
            } footer: {
                Text("Predictable triggers your blocks can ride along: after_kid_dropoff, after_coffee, after_dinner.")
            }

            if let generationError {
                Section {
                    Text(generationError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button {
                    Task { await runGenerate() }
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Generating...")
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || !canGenerate)
            }
        }
        .navigationTitle("Build my schedule")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: Binding(
            get: { proposalResult != nil },
            set: { if !$0 { proposalResult = nil } }
        )) {
            if let result = proposalResult {
                ScheduleDiffView(
                    drafts: result.proposal.blocks,
                    rationale: result.proposal.rationale,
                    warnings: result.proposal.warnings,
                    runID: result.runID,
                    anchorEvents: intake.anchorEvents,
                    optimizationFocusesCSV: intake.optimizationFocusesCSV,
                    onApplied: {
                        onApplied?()
                        dismiss()
                    }
                )
            }
        }
        .onAppear { hydrateFromProfile() }
        .onChange(of: intake) { _, newValue in
            persistIntake(newValue)
        }
    }

    private var canGenerate: Bool {
        !intake.availableDays.isEmpty
            && intake.latestTrainingHour > intake.earliestTrainingHour
    }

    private func runGenerate() async {
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        let service = ScheduleAIService(modelContext: modelContext)
        do {
            let result = try await service.generate(intake: intake)
            proposalResult = result
        } catch let error as ScheduleAIService.ServiceError {
            generationError = error.errorDescription ?? "Generation failed."
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func hydrateFromProfile() {
        guard let profile = profiles.first else { return }

        // M4.2 T0b: if the user filled out the intake form previously and
        // dismissed without applying, restore those answers verbatim. This is
        // the primary hydration path on re-entry. Profile defaults below only
        // fill in fields the prior session didn't touch.
        if let json = profile.lastIntakeJSON,
           let data = json.data(using: .utf8),
           let saved = try? JSONDecoder().decode(ScheduleIntake.self, from: data) {
            intake = saved
            return
        }

        intake.equipmentAccess = profile.equipmentAccess
        intake.restrictionsCSV = profile.restrictionsCSV
        intake.weeklyTrainingTargetSessions = profile.weeklyTrainingTargetSessions
        intake.motivationStyle = profile.motivationStyle
        intake.sleepStartHour = profile.fastWindowStartHour    // sensible default before user picks
        intake.sleepEndHour = profile.fastWindowEndHour
        intake.optimizationFocusesCSV = profile.optimizationFocusesCSV
        let existing = profile.anchorEvents
        if !existing.isEmpty {
            intake.anchorEvents = existing
        }
    }

    /// Writes the current intake to `UserProfile.lastIntakeJSON` so the form
    /// hydrates next time the user opens it. Cheap — runs on each field edit.
    private func persistIntake(_ intake: ScheduleIntake) {
        guard let profile = profiles.first else { return }
        guard let data = try? JSONEncoder().encode(intake),
              let json = String(data: data, encoding: .utf8) else { return }
        profile.lastIntakeJSON = json
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    private func addAnchor() {
        let normalized = newAnchor
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty, !intake.anchorEvents.contains(normalized) else {
            newAnchor = ""
            return
        }
        intake.anchorEvents.append(normalized)
        newAnchor = ""
    }

    private func focusBinding(for focus: OptimizationFocus) -> Binding<Bool> {
        Binding(
            get: {
                let current = [OptimizationFocus].fromCSV(intake.optimizationFocusesCSV)
                return current.contains(focus)
            },
            set: { isOn in
                var current = [OptimizationFocus].fromCSV(intake.optimizationFocusesCSV)
                if isOn {
                    if !current.contains(focus) { current.append(focus) }
                } else {
                    current.removeAll { $0 == focus }
                }
                intake.optimizationFocusesCSV = current.asCSV
            }
        )
    }

    private func format(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    private func weekdayLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Sunday"
        }
    }
}
#endif
