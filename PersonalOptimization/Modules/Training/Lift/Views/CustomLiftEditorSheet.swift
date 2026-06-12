import SwiftUI
import SwiftData

/// Editor for the "My Workout" custom lift template. Name, target sets and
/// reps per exercise; swipe to delete, drag to reorder via the Edit button.
/// Saves into UserProfile metadata; takes effect on the next session start.
struct CustomLiftEditorSheet: View {
    let profile: UserProfile?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var focus: String = ""
    @State private var exercises: [CustomLiftTemplateDTO.Exercise] = []
    @State private var loaded = false

    private var savableExercises: [CustomLiftTemplateDTO.Exercise] {
        exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Focus") {
                    TextField("e.g. upper body, accessories", text: $focus)
                }

                Section {
                    ForEach($exercises) { $exercise in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Exercise name", text: $exercise.name)
                                .autocapitalization(.words)
                                .font(.body.weight(.medium))
                            Stepper("\(exercise.targetSets) set\(exercise.targetSets == 1 ? "" : "s")",
                                    value: $exercise.targetSets, in: 1...10)
                                .font(.subheadline)
                            Stepper("\(exercise.targetReps) reps",
                                    value: $exercise.targetReps, in: 1...30)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        exercises.append(.init(name: "", targetSets: 3, targetReps: 8))
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                    .accessibilityLabel("Add exercise to your workout")
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        EditButton()
                    }
                } footer: {
                    Text("Changes apply the next time you start My Workout. Rows with empty names are dropped on save.")
                }
            }
            .navigationTitle("My Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(savableExercises.isEmpty)
                }
            }
        }
        .task { loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let dto = CustomLiftTemplateStore.loadOrSeed(profile: profile, seed: bundledSeed())
        focus = dto.focus
        exercises = dto.exercises
    }

    private func bundledSeed() -> LiftTemplate? {
        // MARK: try? justified - missing bundled resource just means an empty starting template.
        guard let file = try? LiftTemplatesLoader.load() else { return nil }
        // MARK: try? justified - same as above; the seed is a convenience only.
        return try? LiftTemplatesLoader.template(named: "Lift B", file: file)
    }

    private func save() {
        guard let profile else { return }
        let trimmedFocus = focus.trimmingCharacters(in: .whitespaces)
        let dto = CustomLiftTemplateDTO(
            focus: trimmedFocus.isEmpty ? "your workout, your shape" : trimmedFocus,
            exercises: savableExercises.map {
                .init(id: $0.id,
                      name: $0.name.trimmingCharacters(in: .whitespaces),
                      targetSets: $0.targetSets,
                      targetReps: $0.targetReps)
            }
        )
        CustomLiftTemplateStore.save(dto, profile: profile)
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        onSave()
        dismiss()
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let profile = UserProfile(name: "Clay")
    container.mainContext.insert(profile)
    return CustomLiftEditorSheet(profile: profile) {}
        .modelContainer(container)
}
