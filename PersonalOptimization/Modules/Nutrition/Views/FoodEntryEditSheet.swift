import SwiftUI
import SwiftData

/// Edit servings or meal for a logged entry, or delete it. Saving rewrites
/// the entry's HealthKit samples; deleting removes them.
@MainActor
struct FoodEntryEditSheet: View {
    let entry: FoodEntry
    let service: NutritionService

    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double
    @State private var meal: MealSlot
    @State private var errorMessage: String?

    init(entry: FoodEntry, service: NutritionService) {
        self.entry = entry
        self.service = service
        _servings = State(initialValue: entry.servings)
        _meal = State(initialValue: entry.mealSlot)
    }

    private var servingLabel: String {
        NutritionFormat.serving(size: entry.servingSize, unit: entry.servingUnit)
    }

    private var totals: MacroTotals { entry.perServing.scaled(by: servings) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.headline)
                        if let brand = entry.brand {
                            Text(brand).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Per \(servingLabel): \(NutritionFormat.kcal(entry.calories)) · P \(Int(entry.protein.rounded())) · C \(Int(entry.carbs.rounded())) · F \(Int(entry.fat.rounded()))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Servings") {
                    HStack {
                        TextField("Servings", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("nutrition.edit.servings")
                        Text("× \(servingLabel)").foregroundStyle(.secondary)
                    }
                    Stepper("Adjust by a quarter", value: $servings, in: 0.25...50, step: 0.25)
                        .labelsHidden()
                }
                Section("Meal") {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealSlot.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section("This entry") {
                    LabeledContent("Calories", value: NutritionFormat.kcal(totals.calories))
                    LabeledContent("Protein", value: NutritionFormat.grams(totals.protein))
                    LabeledContent("Carbs", value: NutritionFormat.grams(totals.carbs))
                    LabeledContent("Fat", value: NutritionFormat.grams(totals.fat))
                    if let fiber = totals.fiber {
                        LabeledContent("Fiber", value: NutritionFormat.grams(fiber))
                    }
                    if let sugar = totals.sugar {
                        LabeledContent("Sugar", value: NutritionFormat.grams(sugar))
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                    .accessibilityIdentifier("nutrition.edit.delete")
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(servings <= 0)
                        .accessibilityIdentifier("nutrition.edit.save")
                }
            }
        }
    }

    private func save() {
        do {
            try service.updateEntry(entry, servings: servings, meal: meal)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try service.deleteEntry(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
