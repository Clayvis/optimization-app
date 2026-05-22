import SwiftUI
import SwiftData

/// Settings → Activities. Lets the user add their own activity types so the
/// hardcoded Lift/Basketball/Swim are not the only training entry points.
@MainActor
struct CustomActivitiesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CustomActivityTemplate.createdAt, order: .forward)])
    private var templates: [CustomActivityTemplate]

    @State private var showingAdd = false
    @State private var editing: CustomActivityTemplate?

    private var visibleTemplates: [CustomActivityTemplate] {
        templates.filter { !$0.archived }
    }

    var body: some View {
        List {
            Section {
                Text("Add the activities you actually do. They show up on the Train tab as start-a-session entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Your activities") {
                if visibleTemplates.isEmpty {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add your first activity", systemImage: "plus.circle.fill")
                    }
                } else {
                    ForEach(visibleTemplates, id: \.persistentModelID) { template in
                        Button {
                            editing = template
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.systemImageName)
                                    .frame(width: 28)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.body.weight(.medium))
                                    Text("\(template.defaultDurationMinutes) min default\(template.trackDistance ? " · tracks distance" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                archive(template)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    seedStarters()
                } label: {
                    Label("Seed starter set", systemImage: "sparkles")
                }
                Text("Adds Running, Walking, HIIT, Yoga, Cycling, Hiking. Skips any that already exist.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            CustomActivityEditSheet(template: nil) { name, glyph, duration, distance, notes in
                addTemplate(name: name, glyph: glyph, duration: duration, distance: distance, notes: notes)
            }
        }
        .sheet(item: $editing) { template in
            CustomActivityEditSheet(template: template) { name, glyph, duration, distance, notes in
                update(template, name: name, glyph: glyph, duration: duration, distance: distance, notes: notes)
            }
        }
    }

    private func addTemplate(name: String, glyph: String, duration: Int, distance: Bool, notes: String?) {
        let svc = CustomActivityService(modelContext: modelContext)
        _ = try? svc.addTemplate(name: name,  // MARK: try? justified - best-effort; failure logged inside the called function.
                                 systemImageName: glyph,
                                 defaultDurationMinutes: duration,
                                 trackDistance: distance,
                                 notes: notes)
    }

    private func update(_ template: CustomActivityTemplate,
                        name: String, glyph: String, duration: Int, distance: Bool, notes: String?) {
        let svc = CustomActivityService(modelContext: modelContext)
        _ = try? svc.updateTemplate(template,  // MARK: try? justified - best-effort; failure logged inside the called function.
                                    name: name,
                                    systemImageName: glyph,
                                    defaultDurationMinutes: duration,
                                    trackDistance: distance,
                                    notes: notes)
    }

    private func archive(_ template: CustomActivityTemplate) {
        let svc = CustomActivityService(modelContext: modelContext)
        _ = try? svc.archiveTemplate(template)  // MARK: try? justified - best-effort; failure logged inside the called function.
    }

    private func seedStarters() {
        let svc = CustomActivityService(modelContext: modelContext)
        _ = try? svc.seedDefaultsIfNeeded()  // MARK: try? justified - best-effort; failure logged inside the called function.
    }
}

private struct CustomActivityEditSheet: View {
    let template: CustomActivityTemplate?
    let onSave: (String, String, Int, Bool, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var glyph: String
    @State private var duration: Int
    @State private var distance: Bool
    @State private var notes: String

    /// Curated SF Symbols that correspond to common activity types so the user
    /// gets a meaningful glyph without typing an SF Symbol name.
    private static let glyphChoices: [String] = [
        "figure.run", "figure.walk", "figure.hiking",
        "figure.outdoor.cycle", "figure.indoor.cycle",
        "figure.highintensity.intervaltraining", "figure.cooldown",
        "figure.yoga", "figure.pilates", "figure.dance",
        "figure.boxing", "figure.martial.arts",
        "figure.pool.swim", "figure.surfing", "figure.skiing.downhill",
        "figure.strengthtraining.functional", "figure.core.training",
        "figure.archery", "figure.outdoor.cycle", "figure.tennis",
        "figure.basketball", "figure.soccer"
    ]

    init(template: CustomActivityTemplate?, onSave: @escaping (String, String, Int, Bool, String?) -> Void) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template?.name ?? "")
        _glyph = State(initialValue: template?.systemImageName ?? "figure.run")
        _duration = State(initialValue: template?.defaultDurationMinutes ?? 30)
        _distance = State(initialValue: template?.trackDistance ?? false)
        _notes = State(initialValue: template?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Running, Yoga, HIIT…", text: $name)
                }
                Section("Glyph") {
                    Picker("Symbol", selection: $glyph) {
                        ForEach(Self.glyphChoices, id: \.self) { name in
                            Label(name, systemImage: name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Spacer()
                        Image(systemName: glyph).font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Spacer()
                    }
                }
                Section("Defaults") {
                    Stepper("\(duration) min default", value: $duration, in: 5...180, step: 5)
                    Toggle("Tracks distance (running, walking, biking)", isOn: $distance)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(template == nil ? "New activity" : "Edit activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
                        onSave(trimmed,
                               glyph,
                               duration,
                               distance,
                               trimmedNotes.isEmpty ? nil : trimmedNotes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
