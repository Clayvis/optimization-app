import SwiftUI

struct NutritionMealAction: Identifiable {
    enum Kind { case save, copy }
    let kind: Kind
    let slot: MealSlot?
    var id: String { "\(kind)-\(slot?.rawValue ?? "day")" }
}

/// Review a copy before appending it. Cancel has no persistence side effects.
struct NutritionMealActionsSheet: View {
    let action: NutritionMealAction
    let destination: Date
    let service: NutritionService
    @Environment(\.dismiss) private var dismiss
    @State private var sourceDate: Date
    @State private var name = ""
    @State private var error: String?
    @State private var completed = false

    init(action: NutritionMealAction, destination: Date, service: NutritionService) {
        self.action = action; self.destination = destination; self.service = service
        _sourceDate = State(initialValue: action.kind == .save ? destination
            : Calendar.current.date(byAdding: .day, value: -1, to: destination) ?? destination)
    }

    private var rows: [FoodEntry] {
        service.entries(for: sourceDate).filter { action.slot == nil || $0.mealSlot == action.slot }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { ErrorBanner(message: error) { self.error = nil } }
                if action.kind == .copy {
                    DatePicker("Copy from", selection: $sourceDate, in: ...Date(), displayedComponents: .date)
                    Text("Add to \(destination.formatted(date: .abbreviated, time: .omitted)). Existing entries stay in place.")
                        .font(.caption)
                } else {
                    TextField("Meal name", text: $name).accessibilityIdentifier("nutrition.savedMeal.name")
                }
                Section("\(rows.count) \(rows.count == 1 ? "food" : "foods") · \(NutritionFormat.kcal(MacroTotals.sum(rows.map(\.totals)).calories))") {
                    if rows.isEmpty { Text("No foods logged for this selection.") }
                    ForEach(rows) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text("\(entry.mealSlot.displayName) · \(entry.portionLabel)").font(.caption)
                        }
                    }
                }
                Button(action.kind == .save ? "Save meal" : "Copy \(rows.count) \(rows.count == 1 ? "food" : "foods")") { confirm() }
                    .disabled(rows.isEmpty || completed || (action.kind == .save && name.trimmingCharacters(in: .whitespaces).isEmpty))
                    .accessibilityIdentifier("nutrition.mealAction.confirm")
            }
            .navigationTitle(action.kind == .save ? "Save meal" : "Copy \(action.slot?.displayName ?? "day")")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func confirm() {
        guard !completed else { return }
        do {
            if action.kind == .save {
                try service.saveMeal(name: name, entries: rows)
                LogFeedbackCenter.shared.confirm("Meal saved for next time.")
            } else {
                let target = Calendar.current.isDateInToday(destination) ? Date() : destination
                try service.copyEntries(rows, to: target, meal: action.slot)
                LogFeedbackCenter.shared.confirm(IdentityCopy.mealLogged)
            }
            completed = true
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
