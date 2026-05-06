import SwiftUI
import SwiftData

struct LiftSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let templateName: String

    @State private var session: LiftSession?
    @State private var service: LiftService?
    @State private var loadError: String?
    @State private var startedAt = Date()
    @State private var restTimerEndsAt: Date?
    @State private var showingAddSet = false
    @State private var addSetExercise: LiftExercise?

    var body: some View {
        Group {
            if let error = loadError {
                ContentUnavailableView("Could not load template", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(templateName)
        .task { await loadAndStart() }
    }

    @ViewBuilder
    private func content(session: LiftSession, service: LiftService) -> some View {
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
                Section(exercise.name) {
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

    private func formatRemaining(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func loadAndStart() async {
        do {
            let templates = try LiftTemplatesLoader.load()
            let svc = LiftService(modelContext: modelContext, templatesFile: templates, healthKit: LiveHealthKitService.shared)
            let s = try svc.startSession(templateName: templateName)
            startedAt = Date()
            session = s
            service = svc
            _ = await WorkoutLiveActivityController.start(workoutType: templateName, startDate: startedAt)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func endWorkout(service: LiftService, session: LiftSession) async {
        let durationMinutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session, durationMinutes: durationMinutes)
            await WorkoutLiveActivityController.endAll()
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
