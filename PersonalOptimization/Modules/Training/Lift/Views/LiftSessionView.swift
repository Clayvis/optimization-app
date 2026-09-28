import SwiftUI
import SwiftData
import HealthKit

struct LiftSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    let templateName: String
    /// When true (Training hub tiles), the session starts the moment the view
    /// loads instead of waiting on the preview's Start button. Resumes an
    /// existing draft when one is present.
    var autoStart: Bool = false
    var prescription: PrescribedWorkout? = nil
    var resumeSession: LiftSession? = nil

    @State private var template: LiftTemplate?
    @State private var session: LiftSession?
    @State private var service: LiftService?
    @State private var hasResumableDraft = false
    @State private var loadError: String?
    @State private var startedAt = Date()
    @State private var restTimerEndsAt: Date?
    @State private var showingAddSet = false
    @State private var addSetExercise: LiftExercise?
    @State private var editingSet: LiftSet?
    @State private var setDraft: LiftSetDraft?
    @State private var setError: String?
    @State private var customExerciseName: String = ""
    @State private var completionCount: Int = 0
    @State private var showingTemplateEditor = false
    @State private var liveMetrics: LiveWorkoutMetrics?

    private var isCustomTemplate: Bool {
        templateName == CustomLiftTemplateStore.templateName
    }

    var body: some View {
        Group {
            if let error = loadError {
                ContentUnavailableView("Could not load template", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let template, let service {
                if let session {
                    activeContent(session: session, service: service)
                } else {
                    previewContent(template: template, service: service)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(templateName)
        .toolbar {
            if isCustomTemplate {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTemplateEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit My Workout plan")
                }
            }
        }
        .sheet(isPresented: $showingTemplateEditor) {
            CustomLiftEditorSheet(profile: profiles.first) {
                // Reload so the preview targets reflect the new plan. An
                // active session keeps its inserted exercises; the new plan
                // applies from the next start.
                loadPreview()
            }
        }
        .task { loadPreview() }
        .onDisappear { liveMetrics?.end() }
        .sensoryFeedback(.success, trigger: completionCount)
    }

    // MARK: - Preview state (no session row inserted)

    @ViewBuilder
    private func previewContent(template: LiftTemplate, service: LiftService) -> some View {
        List {
            Section {
                Text(template.focus)
                    .font(.body)
                    .foregroundStyle(.secondary)
                LastWorkoutRecapRow(activityTypes: [.functionalStrengthTraining, .traditionalStrengthTraining])
            } header: {
                Text("Focus")
            } footer: {
                Text("Tap Start to begin tracking. You can leave and come back without losing progress.")
            }

            // M4.2 followup: surface a tactical hint tied to the user's stated
            // optimization focuses, so the same lift template feels tailored.
            // Static mapping — no AI call here, just a smarter way to frame
            // the same numbers per intent (strength → low reps/long rest;
            // endurance → higher reps/short rest; mobility → lighter/slower).
            if let hint = optimizationHint() {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hint.title)
                                .font(.subheadline.weight(.semibold))
                            Text(hint.tactic)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tint)
                    }
                } header: {
                    Text("Optimizing for")
                }
            }

            ForEach(template.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }), id: \.name) { exercise in
                Section(exercise.name) {
                    HStack {
                        Text("Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(exercise.targetSets) × \(exercise.targetReps) reps")
                            .font(.body.weight(.medium))
                    }
                    if let weight = exercise.suggestedWeightLbs {
                        Text("Suggested load: \(weight.formatted()) lb. Adjust to your ability today.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let rest = exercise.restSeconds { Text("Rest: \(rest) seconds").font(.caption) }
                    if let rir = exercise.targetRIR { Text("Target effort: \(rir) RIR. Log your actual effort after each set.").font(.caption) }
                }
            }

            Section {
                Button {
                    promoteToActiveSession(service: service)
                } label: {
                    Label(hasResumableDraft ? "Resume workout" : "Start workout", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("lift.startWorkout")
            }
        }
    }

    // MARK: - Active state (session inserted, set logging UI)

    @ViewBuilder
    private func activeContent(session: LiftSession, service: LiftService) -> some View {
        List {
            if let liveMetrics {
                LiveWorkoutStatsSection(metrics: liveMetrics)
            }

            if let endsAt = restTimerEndsAt {
                Section("Rest timer") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, endsAt.timeIntervalSince(context.date))
                        HStack {
                            Image(systemName: "timer").foregroundStyle(.tint)
                            Text(formatRemaining(remaining)).font(.title3.weight(.semibold)).monospacedDigit()
                            Spacer()
                            Button("Skip") { restTimerEndsAt = nil }
                        }
                    }
                }
            }

            ForEach(sortedExercises(session: session), id: \.persistentModelID) { exercise in
                Section(header: HStack {
                    Text(exercise.name)
                    if exercise.isCustom {
                        Text("CUSTOM")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }) {
                    let sets = (exercise.sets ?? []).sorted { $0.orderIndex < $1.orderIndex }

                    // M4.2 followup: keep the target on screen during the
                    // session so the user doesn't lose the workout shape after
                    // tapping Start. Looked up from the template by name; falls
                    // back silently for custom exercises with no template row.
                    HStack {
                        Text("Target").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(sets.count) of \(exercise.progressionSets) sets · \(exercise.progressionLowerReps)–\(exercise.progressionUpperReps) reps")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(sets.count >= exercise.progressionSets ? .green : .secondary)
                    }

                    ExerciseProgressionView(exercise: exercise)
                    ForEach(sets, id: \.persistentModelID) { set in
                        Button {
                            editingSet = set
                            addSetExercise = exercise
                            setDraft = LiftSetDraft(set: set, source: "Edit logged set")
                            showingAddSet = true
                        } label: {
                            HStack {
                                Text("Set \(set.orderIndex + 1)")
                                    .foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Text("\(set.weightLbs.formatted(.number.precision(.fractionLength(0...2)))) lb × \(set.reps)")
                                    .font(.body.weight(.medium))
                                if let rir = set.repsInReserve { Text("\(rir) RIR").font(.caption).foregroundStyle(.secondary) }
                                Image(systemName: "pencil").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit set \(set.orderIndex + 1), \(exercise.name), \(set.weightLbs) pounds, \(set.reps) reps")
                        .accessibilityIdentifier("lift.editSet")
                    }
                    Button {
                        do {
                            editingSet = nil
                            setDraft = try service.suggestedSet(for: exercise,
                                target: template?.exercises.first { $0.orderIndex == exercise.orderIndex && $0.name == exercise.name })
                            addSetExercise = exercise
                            showingAddSet = true
                        } catch { setError = error.localizedDescription }
                    } label: {
                        Label("Add set", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("lift.addSet")
                }
            }

            Section("Add custom exercise") {
                HStack {
                    TextField("Exercise name", text: $customExerciseName)
                        .autocapitalization(.words)
                    Button {
                        addCustomExercise(service: service, session: session)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customExerciseName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add custom exercise")
                }
            }

            Section {
                volumeSummaryFooter(session: session)
            }

            Section {
                Button(role: .destructive) {
                    Task { await endWorkout(service: service, session: session) }
                } label: {
                    Label("End workout", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let setError { ErrorBanner(message: setError) { self.setError = nil } }
        }
        .sheet(isPresented: $showingAddSet, onDismiss: {
            addSetExercise = nil
            editingSet = nil
            setDraft = nil
        }) {
            if let exercise = addSetExercise, let draft = setDraft {
                AddSetSheet(exercise: exercise, draft: draft, isEditing: editingSet != nil) { weight, reps, rest, rir in
                    if let editingSet {
                        try service.updateSet(editingSet, in: session, weightLbs: weight, reps: reps,
                                              restSeconds: rest, repsInReserve: rir)
                    } else {
                        _ = try service.logSet(in: session, exercise: exercise, weightLbs: weight,
                                               reps: reps, restSeconds: rest, repsInReserve: rir)
                    }
                    if editingSet == nil, let rest, rest > 0 {
                        restTimerEndsAt = Date().addingTimeInterval(TimeInterval(rest))
                    }
                }
            }
        }
    }

    private func sortedExercises(session: LiftSession) -> [LiftExercise] {
        (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// M4.2 followup: static mapping from the user's first matching
    /// optimization focus to a tactical lift hint. Same template numbers, but
    /// framed for what the user is actually trying to do. Returns nil when no
    /// strength-or-endurance focus is set.
    private func optimizationHint() -> (title: String, tactic: String)? {
        let focuses = [OptimizationFocus].fromCSV(profiles.first?.optimizationFocusesCSV ?? "")
        for focus in focuses {
            switch focus {
            case .strength:
                return ("Strength",
                        "4-6 reps, 3+ min rest, push to RPE 8. Last set is the hardest.")
            case .endurance:
                return ("Endurance",
                        "12-15 reps, 60-90s rest, RPE 7. Stay smooth, breathe between sets.")
            case .cardio:
                return ("Cardio support",
                        "Keep this short. 5 main lifts, 8-10 reps, 90s rest. Save legs for run/bike days.")
            case .mobility:
                return ("Mobility",
                        "Lighter weight, slower negatives. Full range over heavy. Pause at end positions.")
            case .nutrition:
                return ("Nutrition support",
                        "Protein within the hour after. Hydrate during. Track kcal in Health.")
            case .sleepQuality:
                return ("Sleep quality",
                        "Finish at least 3 hours before bed. Cool down properly to keep core temp low.")
            case .deepWork:
                return ("Deep work",
                        "Lift first, mental work after. The cognitive boost lasts 2-3 hours.")
            default:
                continue
            }
        }
        return nil
    }

    @ViewBuilder
    private func volumeSummaryFooter(session: LiftSession) -> some View {
        let summary = LiftVolumeSummary.from(session: session)
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's volume")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                volumeArc(value: summary.totalLbs, target: 12_000, label: "lb", color: .orange)
                volumeArc(value: Double(summary.setCount), target: 32, label: "sets", color: .blue)
                volumeArc(value: Double(summary.repCount), target: 250, label: "reps", color: .green)
            }
            if summary.totalLbs > 0 {
                Text(summary.completionLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .accessibilityLabel(summary.completionLine)
            }
        }
        .padding(.vertical, 4)
    }

    private func volumeArc(value: Double, target: Double, label: String, color: Color) -> some View {
        let progress = target > 0 ? min(value / target, 1.0) : 0
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 56, height: 56)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func addCustomExercise(service: LiftService, session: LiftSession) {
        let name = customExerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = try? service.addCustomExercise(in: session, name: name)  // MARK: try? justified - best-effort; failure logged inside the called function.
        customExerciseName = ""
    }

    private func formatRemaining(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - State transitions

    /// Loads the template and probes for an in-progress draft, but does NOT
    /// insert a `LiftSession`. The user gets a read-only preview until they
    /// explicitly tap Start (or Resume, when a draft exists).
    private func loadPreview() {
        do {
            let bundled = try LiftTemplatesLoader.load()
            let templates: LiftTemplatesFile
            if let resumeSession {
                let restored = LiftTemplate(name: resumeSession.template, focus: "Continue your saved workout.",
                    exercises: (resumeSession.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }.map {
                        LiftTemplateExercise(name: $0.name, orderIndex: $0.orderIndex,
                                             targetSets: $0.progressionSets, targetReps: $0.progressionLowerReps)
                    })
                templates = LiftTemplatesFile(version: bundled.version, templates: [restored])
                template = restored
            } else if let prescription {
                let plan = try SuggestedLiftPlan.read(prescription)
                let suggested = plan.template(title: templateName, rationale: prescription.rationale)
                templates = LiftTemplatesFile(version: bundled.version, templates: [suggested])
                template = suggested
            } else if isCustomTemplate {
                // MARK: try? justified - a missing bundled Lift B only means the custom seed starts empty.
                let seed = try? LiftTemplatesLoader.template(named: "Lift B", file: bundled)
                let dto = CustomLiftTemplateStore.loadOrSeed(profile: profiles.first, seed: seed)
                let custom = CustomLiftTemplateStore.asLiftTemplate(dto)
                templates = LiftTemplatesFile(version: bundled.version, templates: bundled.templates + [custom])
                template = custom
            } else {
                templates = bundled
                template = try LiftTemplatesLoader.template(named: templateName, file: templates)
            }
            service = LiftService(modelContext: modelContext, templatesFile: templates, healthKit: LiveHealthKitService.shared)
            hasResumableDraft = resumeSession != nil || prescription?.sessionUUID != nil
                || (prescription == nil && inProgressSession(for: templateName) != nil)
            if autoStart, session == nil, let service {
                promoteToActiveSession(service: service)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Promotes the preview to an active session: resumes an existing draft
    /// when one is present, otherwise inserts a fresh `LiftSession` row.
    private func promoteToActiveSession(service: LiftService) {
        if let resumed = resumeSession ?? (prescription == nil ? inProgressSession(for: templateName) : nil) {
            guard resumed.durationMinutes == 0 else { loadError = LiftServiceError.sessionFinished.localizedDescription; return }
            session = resumed
            startedAt = resumed.date
            beginLiveMetrics(from: resumed.date)
            Task {
                _ = await WorkoutLiveActivityController.start(workoutType: templateName, startDate: startedAt)
            }
            return
        }
        do {
            let s: LiftSession
            if let prescription, let template {
                s = try service.startSession(template: template, prescription: prescription)
            } else {
                s = try service.startSession(templateName: templateName)
            }
            guard s.durationMinutes == 0 else { throw LiftServiceError.sessionFinished }
            startedAt = s.date
            session = s
            beginLiveMetrics(from: startedAt)
            Task {
                _ = await WorkoutLiveActivityController.start(workoutType: templateName, startDate: startedAt)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func beginLiveMetrics(from start: Date) {
        WorkoutPresenceService.shared.start(type: templateName, at: start)
        let metrics = LiveWorkoutMetrics(
            healthKit: LiveHealthKitService.shared,
            sessionStart: start,
            activityType: .functionalStrengthTraining
        )
        metrics.begin()
        liveMetrics = metrics
    }

    /// Active LiftSession matching `templateName` from today (durationMinutes==0).
    /// Used to resume a workout the user navigated away from.
    private func inProgressSession(for templateName: String) -> LiftSession? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let descriptor = FetchDescriptor<LiftSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = modelContext.fetchOrEmpty(descriptor)
        return sessions.first {
            $0.template == templateName
                && $0.durationMinutes == 0
                && cal.isDate($0.date, inSameDayAs: today)
        }
    }

    private func endWorkout(service: LiftService, session: LiftSession) async {
        let durationMinutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        // HealthKit-measured energy (watch worn) wins; otherwise a MET
        // estimate from body weight so the Health workout isn't calorie-less.
        await liveMetrics?.refreshOnce()
        let kcal = liveMetrics?.closingKcal(
            met: WorkoutMetrics.met(for: .lift),
            weightLbs: profiles.first?.weightLbs,
            elapsedMinutes: Double(durationMinutes)
        )
        let avgHR = liveMetrics?.heartRateBPM.map { Int($0.rounded()) }
        do {
            try service.endSession(session, durationMinutes: durationMinutes, avgHR: avgHR, estimatedCalories: kcal)
            liveMetrics?.end()
            WorkoutPresenceService.shared.end()
            await WorkoutLiveActivityController.endAll()
            completionCount &+= 1
            LogFeedbackCenter.shared.confirm(IdentityCopy.workoutLogged)
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct AddSetSheet: View {
    let exercise: LiftExercise
    let onConfirm: (Double, Int, Int?, Int?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    let isEditing: Bool
    let source: String
    @State private var weight: Double
    @State private var reps: Int
    @State private var restSeconds: Int
    @State private var rir: Int
    @State private var saveError: String?

    init(exercise: LiftExercise, draft: LiftSetDraft, isEditing: Bool,
         onConfirm: @escaping (Double, Int, Int?, Int?) throws -> Void) {
        self.exercise = exercise
        self.isEditing = isEditing
        self.source = draft.source
        self.onConfirm = onConfirm
        _weight = State(initialValue: draft.weightLbs)
        _reps = State(initialValue: draft.reps)
        _restSeconds = State(initialValue: draft.restSeconds)
        _rir = State(initialValue: draft.repsInReserve ?? -1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
                Section("Weight (lb)") {
                    TextField("Weight (lb)", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("lift.setWeight")
                    Stepper("Adjust by 2.5 lb", value: $weight, in: 0...10_000, step: 2.5)
                }
                Section("Reps") {
                    TextField("Reps", value: $reps, format: .number)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("lift.setReps")
                    Stepper("\(reps) reps", value: $reps, in: 1...1_000)
                }
                Section("Effort") {
                    Picker("Reps in reserve", selection: $rir) {
                        Text("Not recorded").tag(-1)
                        ForEach(0...10, id: \.self) { Text("\($0) RIR").tag($0) }
                    }
                    Text("Good repetitions you could still do. Most working sets: 1–3 RIR; 0 means failure.")
                        .font(.caption)
                }
                Section("Rest") {
                    Stepper("\(restSeconds) sec", value: $restSeconds, in: 0...600, step: 15)
                }
                Section {
                    Button(isEditing ? "Save changes" : "Log set") {
                        do {
                            try onConfirm(weight, reps, restSeconds > 0 ? restSeconds : nil, rir < 0 ? nil : rir)
                            dismiss()
                        } catch { saveError = error.localizedDescription }
                    }
                    .accessibilityIdentifier("lift.confirmSet")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let saveError { ErrorBanner(message: saveError) { self.saveError = nil } }
            }
            .navigationTitle(exercise.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Explicit rep-range targets for double progression, including custom lifts.
private struct ExerciseProgressionView: View {
    @Bindable var exercise: LiftExercise
    @Environment(\.modelContext) private var context
    @State private var error: String?
    var body: some View {
        DisclosureGroup("Double progression") {
            Stepper("\(exercise.progressionSets) working sets", value: $exercise.progressionSets, in: 1...10)
            Stepper("Minimum \(exercise.progressionLowerReps) reps", value: $exercise.progressionLowerReps, in: 1...30)
            Stepper("Maximum \(exercise.progressionUpperReps) reps", value: $exercise.progressionUpperReps, in: 1...40)
            Button("Save progression targets") {
                exercise.progressionUpperReps = max(exercise.progressionLowerReps, exercise.progressionUpperReps)
                do { try context.save() } catch { self.error = error.localizedDescription }
            }
            if HypertrophyRules.shouldIncreaseWeight(reps: (exercise.sets ?? []).map(\.reps),
                                                     plannedSets: exercise.progressionSets,
                                                     upperReps: exercise.progressionUpperReps) {
                Text("Every working set reached the upper rep target. Consider the smallest available load increase next session if recovery and technique are good.")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Text("Keep the load until every planned working set reaches the top of the rep range with good technique.").font(.caption)
            }
            if let error { ErrorBanner(message: error) { self.error = nil } }
        }
    }
}
