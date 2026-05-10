import SwiftUI
import SwiftData

struct LiftSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let templateName: String

    @State private var template: LiftTemplate?
    @State private var session: LiftSession?
    @State private var service: LiftService?
    @State private var hasResumableDraft = false
    @State private var loadError: String?
    @State private var startedAt = Date()
    @State private var restTimerEndsAt: Date?
    @State private var showingAddSet = false
    @State private var addSetExercise: LiftExercise?
    @State private var customExerciseName: String = ""
    @State private var completionCount: Int = 0

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
        .task { loadPreview() }
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
            } header: {
                Text("Focus")
            } footer: {
                Text("Tap Start to begin tracking. You can leave and come back without losing progress.")
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
            }
        }
    }

    // MARK: - Active state (session inserted, set logging UI)

    @ViewBuilder
    private func activeContent(session: LiftSession, service: LiftService) -> some View {
        List {
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
                    ForEach(sets, id: \.persistentModelID) { set in
                        HStack {
                            Text("Set \(set.orderIndex + 1)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(set.weightLbs)) lbs × \(set.reps)")
                                .font(.body.weight(.medium))
                        }
                    }
                    Button {
                        addSetExercise = exercise
                        showingAddSet = true
                    } label: {
                        Label("Add set", systemImage: "plus.circle")
                    }
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
        .sheet(isPresented: $showingAddSet, onDismiss: {
            addSetExercise = nil
        }) {
            if let exercise = addSetExercise {
                AddSetSheet(exercise: exercise) { weight, reps, rest in
                    // try? justified: SwiftData write to local container; failures
                    // surface via Logger and the user simply re-taps.
                    _ = try? service.logSet(in: session, exerciseName: exercise.name, weightLbs: weight, reps: reps, restSeconds: rest)
                    if let rest, rest > 0 {
                        restTimerEndsAt = Date().addingTimeInterval(TimeInterval(rest))
                    }
                }
            }
        }
    }

    private func sortedExercises(session: LiftSession) -> [LiftExercise] {
        (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
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
        _ = try? service.addCustomExercise(in: session, name: name)
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
            let templates = try LiftTemplatesLoader.load()
            template = try LiftTemplatesLoader.template(named: templateName, file: templates)
            service = LiftService(modelContext: modelContext, templatesFile: templates, healthKit: LiveHealthKitService.shared)
            hasResumableDraft = inProgressSession(for: templateName) != nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Promotes the preview to an active session: resumes an existing draft
    /// when one is present, otherwise inserts a fresh `LiftSession` row.
    private func promoteToActiveSession(service: LiftService) {
        if let resumed = inProgressSession(for: templateName) {
            session = resumed
            startedAt = resumed.date
            Task {
                _ = await WorkoutLiveActivityController.start(workoutType: templateName, startDate: startedAt)
            }
            return
        }
        do {
            let s = try service.startSession(templateName: templateName)
            startedAt = Date()
            session = s
            Task {
                _ = await WorkoutLiveActivityController.start(workoutType: templateName, startDate: startedAt)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Active LiftSession matching `templateName` from today (durationMinutes==0).
    /// Used to resume a workout the user navigated away from.
    private func inProgressSession(for templateName: String) -> LiftSession? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let today = cal.startOfDay(for: Date())
        let descriptor = FetchDescriptor<LiftSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first {
            $0.template == templateName
                && $0.durationMinutes == 0
                && cal.isDate($0.date, inSameDayAs: today)
        }
    }

    private func endWorkout(service: LiftService, session: LiftSession) async {
        let durationMinutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session, durationMinutes: durationMinutes)
            await WorkoutLiveActivityController.endAll()
            completionCount &+= 1
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct AddSetSheet: View {
    let exercise: LiftExercise
    let onConfirm: (Double, Int, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double = 135
    @State private var reps: Int = 5
    @State private var restSeconds: Int = 120

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    Stepper("\(Int(weight)) lbs", value: $weight, in: 45...700, step: 5)
                }
                Section("Reps") {
                    Stepper("\(reps) reps", value: $reps, in: 1...30)
                }
                Section("Rest") {
                    Stepper("\(restSeconds) sec", value: $restSeconds, in: 0...600, step: 15)
                }
                Section {
                    Button("Log set") {
                        onConfirm(weight, reps, restSeconds > 0 ? restSeconds : nil)
                        dismiss()
                    }
                }
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
