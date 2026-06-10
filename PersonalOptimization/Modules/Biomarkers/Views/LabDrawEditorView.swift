import SwiftUI
import SwiftData
import os

/// Manual lab-draw entry, grouped by catalog category. Also the review screen
/// for PDF-parsed values: parsed markers arrive via `prefill` and are
/// highlighted so the user can verify before saving (parse → review → save,
/// per the reference flow).
struct LabDrawEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let prefill: ParsedLabReport?
    let sex: String

    @State private var date = Date()
    @State private var notes = ""
    @State private var entries: [String: String] = [:]
    @State private var saveError: String?

    /// Marker ids that arrived from the parser, for the highlight ring.
    private var prefilled: Set<String> {
        Set(prefill.map { Array($0.values.keys) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Draw date", selection: $date, displayedComponents: .date)
                    TextField("Notes (fasted, AM draw…)", text: $notes, axis: .vertical)
                } header: {
                    if let prefill, !prefill.values.isEmpty {
                        Text("\(prefill.values.count) values parsed\(prefill.usedOCR ? " via OCR" : "") — review before saving")
                    }
                }

                ForEach(BiomarkerCatalog.categoryOrder, id: \.self) { category in
                    let ids = BiomarkerCatalog.ids(inCategory: category, sex: sex)
                    if !ids.isEmpty {
                        Section(category) {
                            ForEach(ids, id: \.self) { id in
                                markerField(id: id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lab draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedValues.isEmpty)
                }
            }
            .onAppear(perform: applyPrefill)
            .alert("Save failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    @ViewBuilder
    private func markerField(id: String) -> some View {
        if let def = BiomarkerCatalog.all[id] {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name)
                        .font(.subheadline)
                    Text("optimal \(rangeLabel(def.optimal)) \(def.unit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("—", text: binding(for: id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(prefilled.contains(id) && entries[id]?.isEmpty == false
                                  ? Theme.kurenai.opacity(0.15)
                                  : Color.clear)
                    )
                    .accessibilityLabel("\(def.name) value in \(def.unit)")
            }
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { entries[id] ?? "" },
            set: { entries[id] = $0 }
        )
    }

    private func rangeLabel(_ range: [Double]) -> String {
        guard range.count == 2 else { return "" }
        func f(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
        return "\(f(range[0]))–\(f(range[1]))"
    }

    private var parsedValues: [String: Double] {
        entries.reduce(into: [:]) { out, pair in
            if let v = Double(pair.value.trimmingCharacters(in: .whitespaces)), v.isFinite {
                out[pair.key] = v
            }
        }
    }

    private func applyPrefill() {
        guard let prefill else { return }
        if let d = prefill.date { date = d }
        guard entries.isEmpty else { return }
        var filled: [String: String] = [:]
        for (key, v) in prefill.values {
            if v == v.rounded() {
                filled[key] = String(Int(v))
            } else {
                filled[key] = String(v)
            }
        }
        entries = filled
    }

    private func save() {
        do {
            try LabDrawStore.upsert(
                date: date,
                values: parsedValues,
                notes: notes,
                sourcePdfFilename: prefill?.sourceFilename,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            Logger.parser.error("Lab draw save failed: \(error.localizedDescription, privacy: .public)")
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    LabDrawEditorView(prefill: nil, sex: "male")
        .modelContainer(editorPreviewContainer)
}

@MainActor
private let editorPreviewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try! ModelContainer(for: schema, configurations: [config])
}()
