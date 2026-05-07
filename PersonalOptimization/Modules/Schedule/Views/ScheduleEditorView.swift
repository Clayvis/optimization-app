import SwiftUI
import SwiftData

/// In-app CRUD on ScheduleBlock. Custom blocks (`isCustom == true`) are preserved
/// across re-seeds. Identity-framed copy reinforces ownership: "Your schedule. Your protocol."
struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ScheduleBlock.dayOfWeek), SortDescriptor(\ScheduleBlock.startTime)])
    private var allBlocks: [ScheduleBlock]

    @State private var editing: ScheduleBlock?
    @State private var addingForDay: Int?
    @State private var showingResetConfirm = false

    var body: some View {
        List {
            Section {
                Text("Your schedule. Your protocol.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(1...7, id: \.self) { day in
                let blocks = blocksForDay(day)
                Section(header: Text(weekdayName(day))) {
                    ForEach(blocks) { block in
                        Button {
                            editing = block
                        } label: {
                            blockRow(block: block)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(block: block)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        addingForDay = day
                    } label: {
                        Label("Add block", systemImage: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Reset to default", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Removes seeded blocks and reseeds from the bundled default. Your custom blocks survive.")
            }
        }
        .navigationTitle("Schedule")
        .sheet(item: $editing) { block in
            ScheduleBlockEditSheet(block: block, modelContext: modelContext)
        }
        .sheet(item: Binding(
            get: { addingForDay.map { DayAddIntent(day: $0) } },
            set: { addingForDay = $0?.day }
        )) { intent in
            ScheduleBlockEditSheet(block: nil,
                                   defaultDayOfWeek: intent.day,
                                   modelContext: modelContext)
        }
        .confirmationDialog("Reset to default?",
                            isPresented: $showingResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset (keep my custom blocks)", role: .destructive) {
                resetSeededOnly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Seeded blocks will be replaced by the bundled default schedule. Blocks you added (marked custom) are preserved.")
        }
    }

    @ViewBuilder
    private func blockRow(block: ScheduleBlock) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(block.activity)
                        .font(.body.weight(.medium))
                    if block.isCustom {
                        Text("CUSTOM")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
                Text("\(block.startTime) – \(block.endTime) · \(block.type.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func blocksForDay(_ day: Int) -> [ScheduleBlock] {
        allBlocks.filter { $0.dayOfWeek == day && $0.isOverride == false }
    }

    private func delete(block: ScheduleBlock) {
        modelContext.delete(block)
        try? modelContext.save()
    }

    private func resetSeededOnly() {
        try? ScheduleSeed.resetToDefault(modelContext: modelContext)
    }

    private func weekdayName(_ iso: Int) -> String {
        switch iso {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        case 7: return "Sunday"
        default: return "Day \(iso)"
        }
    }
}

private struct DayAddIntent: Identifiable {
    let day: Int
    var id: Int { day }
}

/// Single sheet that handles both create and edit. `block == nil` triggers create-mode.
struct ScheduleBlockEditSheet: View {
    let modelContext: ModelContext
    let isEditing: Bool
    let editingBlock: ScheduleBlock?

    @Environment(\.dismiss) private var dismiss

    @State private var dayOfWeek: Int
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var activity: String
    @State private var typeRaw: String
    @State private var module: String

    init(block: ScheduleBlock?,
         defaultDayOfWeek: Int = 1,
         modelContext: ModelContext) {
        self.modelContext = modelContext
        self.isEditing = block != nil
        self.editingBlock = block

        if let block {
            self._dayOfWeek = State(initialValue: block.dayOfWeek)
            let (sh, sm) = Self.parseTime(block.startTime)
            let (eh, em) = Self.parseTime(block.endTime)
            self._startHour = State(initialValue: sh)
            self._startMinute = State(initialValue: sm)
            self._endHour = State(initialValue: eh)
            self._endMinute = State(initialValue: em)
            self._activity = State(initialValue: block.activity)
            self._typeRaw = State(initialValue: block.typeRaw)
            self._module = State(initialValue: block.module ?? "")
        } else {
            self._dayOfWeek = State(initialValue: defaultDayOfWeek)
            self._startHour = State(initialValue: 9)
            self._startMinute = State(initialValue: 0)
            self._endHour = State(initialValue: 10)
            self._endMinute = State(initialValue: 0)
            self._activity = State(initialValue: "")
            self._typeRaw = State(initialValue: BlockType.other.rawValue)
            self._module = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    TextField("Activity", text: $activity)
                    Picker("Type", selection: $typeRaw) {
                        ForEach(BlockType.allCases, id: \.rawValue) { t in
                            Text(t.rawValue.capitalized).tag(t.rawValue)
                        }
                    }
                    TextField("Module tag (optional)", text: $module)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                }

                Section("When") {
                    Picker("Day", selection: $dayOfWeek) {
                        ForEach(1...7, id: \.self) { d in
                            Text(weekday(d)).tag(d)
                        }
                    }
                    HStack {
                        Text("Start")
                        Spacer()
                        Picker("Start hour", selection: $startHour) {
                            ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden()
                        Picker("Start min", selection: $startMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        Picker("End hour", selection: $endHour) {
                            ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden()
                        Picker("End min", selection: $endMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                }

                if !timeRangeValid {
                    Section {
                        Label("End must be after start.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit block" : "Add block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var timeRangeValid: Bool {
        startHour * 60 + startMinute < endHour * 60 + endMinute
    }

    private var canSave: Bool {
        timeRangeValid && !activity.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedActivity = activity.trimmingCharacters(in: .whitespaces)
        let trimmedModule = module.trimmingCharacters(in: .whitespaces)
        let moduleValue = trimmedModule.isEmpty ? nil : trimmedModule
        let startStr = String(format: "%02d:%02d", startHour, startMinute)
        let endStr = String(format: "%02d:%02d", endHour, endMinute)
        let type = BlockType(rawValue: typeRaw) ?? .other

        if let editingBlock {
            editingBlock.dayOfWeek = dayOfWeek
            editingBlock.startTime = startStr
            editingBlock.endTime = endStr
            editingBlock.activity = trimmedActivity
            editingBlock.typeRaw = type.rawValue
            editingBlock.module = moduleValue
            // Edited seeded blocks become custom so a re-seed does not overwrite them.
            editingBlock.isCustom = true
        } else {
            let block = ScheduleBlock(
                dayOfWeek: dayOfWeek,
                startTime: startStr,
                endTime: endStr,
                activity: trimmedActivity,
                type: type,
                module: moduleValue
            )
            block.isCustom = true
            modelContext.insert(block)
        }
        try? modelContext.save()
        dismiss()
    }

    private func weekday(_ iso: Int) -> String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][safe: iso - 1] ?? "Day \(iso)"
    }

    private static func parseTime(_ s: String) -> (Int, Int) {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return (9, 0) }
        return (h, m)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Editor") {
    let schema = Schema(versionedSchema: SchemaV5.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return NavigationStack { ScheduleEditorView() }.modelContainer(container)
}
