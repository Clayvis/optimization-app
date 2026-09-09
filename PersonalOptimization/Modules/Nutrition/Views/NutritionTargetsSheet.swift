import SwiftUI
import SwiftData

/// Daily targets in grams (percent of calories is shown, never stored).
/// Prefilled from body weight on first use; nothing is saved until Save.
@MainActor
struct NutritionTargetsSheet: View {
    let service: NutritionService
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var values: NutritionTargetValues
    @State private var errorMessage: String?
    private let isFirstSetup: Bool

    init(service: NutritionService, date: Date, weightLbs: Double?) {
        self.service = service
        self.date = date
        let existing = service.targets(for: date)?.values
        isFirstSetup = existing == nil
        _values = State(initialValue: existing ?? NutritionTargetValues.prefill(weightLbs: weightLbs))
    }

    private var mismatch: Bool {
        values.calories > 0 && abs(values.caloriesFromMacros - values.calories) > max(50, values.calories * 0.1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    targetField("Calories", value: $values.calories, unit: "kcal", step: 50, identifier: "nutrition.targets.calories")
                    targetField("Protein", value: $values.proteinGrams, unit: "g", step: 5, identifier: "nutrition.targets.protein")
                    targetField("Carbs", value: $values.carbsGrams, unit: "g", step: 5, identifier: "nutrition.targets.carbs")
                    targetField("Fat", value: $values.fatGrams, unit: "g", step: 5, identifier: "nutrition.targets.fat")
                } header: {
                    Text("Daily targets")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Split: protein \(percent(values.proteinPercent)) · carbs \(percent(values.carbsPercent)) · fat \(percent(values.fatPercent)). Macros add up to \(NutritionFormat.kcal(values.caloriesFromMacros)).")
                        if mismatch {
                            Text("That differs from your calorie target by more than 10 percent. Either is fine; the day view tracks each number on its own.")
                                .foregroundStyle(.orange)
                        }
                        if isFirstSetup {
                            Text("Starting point: 0.8 g protein per pound of body weight when known, fat at 25 percent of calories, carbs fill the rest. Adjust freely.")
                        }
                    }
                }

                Section {
                    Toggle("Eat back exercise calories", isOn: $values.eatBackExerciseCalories)
                        .accessibilityIdentifier("nutrition.targets.eatBack")
                    if values.eatBackExerciseCalories {
                        Slider(value: $values.exerciseEatBackPercent, in: 0...1, step: 0.05) {
                            Text("Percent of burned calories")
                        }
                        .accessibilityValue("\(percent(values.exerciseEatBackPercent))")
                        Text("\(percent(values.exerciseEatBackPercent)) of Apple Health active energy is added to the day's calorie budget. Watch and phone estimates run high; 50 percent is a sane default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Exercise")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(isFirstSetup ? "Set targets" : "Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("nutrition.targets.save")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Applies from \(date.formatted(.dateTime.month(.abbreviated).day())) onward. Earlier days keep the targets they had.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func targetField(_ label: String, value: Binding<Double>, unit: String, step: Double, identifier: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Stepper("", value: value, in: 0...10_000, step: step)
                .labelsHidden()
                .accessibilityLabel("Adjust \(label)")
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(NutritionFormat.wholeNumber(fraction * 100))%"
    }

    private func save() {
        do {
            try service.setTargets(values, from: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
