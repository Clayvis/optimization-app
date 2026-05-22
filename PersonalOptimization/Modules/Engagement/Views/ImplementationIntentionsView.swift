import SwiftUI
import SwiftData

/// Implementation Intentions builder. Settings → Implementation Intentions.
/// Lets the user create "When X, I will Y" plans grounded in research-backed
/// trigger types. Identity-framed copy throughout.
@MainActor
struct ImplementationIntentionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ImplementationIntention.createdAt, order: .forward)])
    private var intentions: [ImplementationIntention]

    @State private var showingAdd = false
    @State private var editing: ImplementationIntention?

    private var visible: [ImplementationIntention] {
        intentions.filter { $0.active }
    }

    var body: some View {
        List {
            Section {
                Text("If-then plans turn good intentions into actions. Anchor each plan to a real cue you'll notice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Your plans") {
                if visible.isEmpty {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add your first plan", systemImage: "plus.circle.fill")
                    }
                } else {
                    ForEach(visible, id: \.persistentModelID) { intention in
                        Button {
                            editing = intention
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: intention.triggerType.systemImage)
                                        .foregroundStyle(.tint)
                                    Text("When \(intention.trigger.lowercased())")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text("I will \(intention.action.lowercased())")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let last = intention.lastCompletedAt {
                                    Text("Last done \(last.formatted(.relative(presentation: .named)))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                archive(intention)
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
                Text("Adds 5 evidence-backed starters anchored to your morning routine, training, and learning blocks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Implementation Intentions")
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
            IntentionEditSheet(intention: nil) { trigger, type, action, time in
                _ = try? ImplementationIntentionService(modelContext: modelContext)  // MARK: try? justified - best-effort; failure logged inside the called function.
                    .add(trigger: trigger, triggerType: type, action: action, triggerTimeMinutes: time)
            }
        }
        .sheet(item: $editing) { intention in
            IntentionEditSheet(intention: intention) { trigger, type, action, time in
                _ = try? ImplementationIntentionService(modelContext: modelContext)  // MARK: try? justified - best-effort; failure logged inside the called function.
                    .update(intention, trigger: trigger, triggerType: type, action: action, triggerTimeMinutes: time)
            }
        }
    }

    private func archive(_ intention: ImplementationIntention) {
        _ = try? ImplementationIntentionService(modelContext: modelContext).archive(intention)  // MARK: try? justified - best-effort; failure logged inside the called function.
    }

    private func seedStarters() {
        _ = try? ImplementationIntentionService(modelContext: modelContext).seedStartersIfNeeded()  // MARK: try? justified - best-effort; failure logged inside the called function.
    }
}

private struct IntentionEditSheet: View {
    let intention: ImplementationIntention?
    let onSave: (String, TriggerType, String, Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var trigger: String
    @State private var triggerType: TriggerType
    @State private var action: String
    @State private var triggerHour: Int
    @State private var triggerMinute: Int

    init(intention: ImplementationIntention?, onSave: @escaping (String, TriggerType, String, Int?) -> Void) {
        self.intention = intention
        self.onSave = onSave
        _trigger = State(initialValue: intention?.trigger ?? "")
        _triggerType = State(initialValue: intention?.triggerType ?? .afterEvent)
        _action = State(initialValue: intention?.action ?? "")
        let mins = intention?.triggerTimeMinutes ?? (9 * 60)
        _triggerHour = State(initialValue: mins / 60)
        _triggerMinute = State(initialValue: mins % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trigger type") {
                    Picker("Type", selection: $triggerType) {
                        ForEach(TriggerType.allCases, id: \.rawValue) { t in
                            Label(t.displayName, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("When") {
                    TextField("e.g. \"After morning coffee\"", text: $trigger, axis: .vertical)
                        .lineLimit(1...3)
                    if triggerType == .time {
                        HStack {
                            Picker("Hour", selection: $triggerHour) {
                                ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            .labelsHidden()
                            Text(":")
                            Picker("Minute", selection: $triggerMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }
                Section("I will") {
                    TextField("Drink 16 oz of water", text: $action, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    Text("This is your plan. The cue triggers the action. No willpower required — just notice the cue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(intention == nil ? "New plan" : "Edit plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let timeMinutes: Int? = triggerType == .time
                            ? (triggerHour * 60 + triggerMinute)
                            : nil
                        onSave(trigger, triggerType, action, timeMinutes)
                        dismiss()
                    }
                    .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || action.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
