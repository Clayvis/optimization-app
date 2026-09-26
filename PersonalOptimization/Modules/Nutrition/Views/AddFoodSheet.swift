import SwiftUI
import SwiftData

/// Recent is the default. Whole-meal repeat and saved-meal logging keep the
/// original nutrition and portions; My foods and New food retain manual entry.
@MainActor
struct AddFoodSheet: View {
    @State var slot: MealSlot
    let loggedAt: Date
    let service: NutritionService

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .recent
    @State private var recentMeals: [RecentNutritionMeal] = []
    @State private var savedMeals: [SavedMeal] = []
    @State private var didLog = false
    @State private var query = ""
    @State private var foods: [FoodItem] = []
    @State private var selected: FoodItem?
    @State private var servings: Double = 1
    @State private var draft = FoodDraft()
    @State private var draftServings: Double = 1
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case frequent = "Frequent"
        case saved = "Saved meals"
        case myFoods = "My foods"
        case newFood = "New food"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases) { Text($0.displayName).tag($0) }
                }.padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Mode.allCases) { option in
                            Button(option.rawValue) { mode = option }
                                .buttonStyle(.bordered)
                                .tint(mode == option ? Theme.matcha : .secondary)
                                .accessibilityAddTraits(mode == option ? .isSelected : [])
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Theme.Space.s)
                .accessibilityIdentifier("nutrition.add.mode")

                switch mode {
                case .recent, .frequent, .myFoods: myFoodsList
                case .saved: savedMealsList
                case .newFood: newFoodForm
                }
            }
            .navigationTitle("Add to \(slot.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                        .padding(.horizontal)
                }
            }
            .task {
                reload()
                // A first-time user has nothing to pick from yet.
                if service.foods().isEmpty && savedMeals.isEmpty { mode = .newFood }
            }
            .onChange(of: query) { _, _ in reload() }
            .onChange(of: mode) { _, _ in selected = nil; reload() }
            .disabled(didLog)
        }
    }

    // MARK: - My foods

    private var myFoodsList: some View {
        List {
            if mode == .recent && query.isEmpty && !recentMeals.isEmpty {
                Section("Repeat a meal · last 14 days") {
                    ForEach(recentMeals) { meal in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(meal.slot.displayName).font(.headline)
                                Text(meal.date, style: .date).font(.caption)
                                Text(meal.entries.map(\.name).joined(separator: ", "))
                                    .font(.caption).lineLimit(2)
                                Text(NutritionFormat.kcal(meal.totals.calories)).font(.caption)
                            }
                            Spacer()
                            Button("Log") { logRecent(meal) }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.matcha)
                                .accessibilityLabel("Repeat \(meal.slot.displayName)")
                                .accessibilityIdentifier("nutrition.repeatMeal")
                        }
                    }
                }
            }
            if foods.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No foods in this list" : "No matches",
                    systemImage: "fork.knife",
                    description: Text(query.isEmpty
                                      ? "Choose My foods or New food. Logged foods appear here next time."
                                      : "Try another word, or create it under New food.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(foods) { food in
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name)
                            .font(.body.weight(.medium))
                        Text([food.brand, food.servingLabel, NutritionFormat.kcal(food.calories),
                              "P \(NutritionFormat.wholeNumber(food.protein))"].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Log") { log(food, servings: 1) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.matcha)
                        .accessibilityLabel("Log one serving of \(food.name)")
                        .accessibilityIdentifier("nutrition.logOne.\(food.id.uuidString)")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selected = food
                    servings = 1
                }
                .listRowBackground(selected?.id == food.id ? Theme.matcha.opacity(0.12) : nil)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search my foods")
        .safeAreaInset(edge: .bottom) {
            if let selected {
                servingsBar(for: selected)
            }
        }
    }

    private func servingsBar(for food: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(food.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack {
                Stepper(value: $servings, in: 0.25...50, step: 0.25) {
                    Text("\(NutritionFormat.number(servings)) × \(food.servingLabel)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("nutrition.servings")
                Button {
                    log(food, servings: servings)
                } label: {
                    Text("Log \(NutritionFormat.kcal(food.calories * servings))")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.matcha)
                .accessibilityIdentifier("nutrition.logSelected")
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - New food

    private var newFoodForm: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $draft.name)
                    .accessibilityIdentifier("nutrition.newFood.name")
                TextField("Brand (optional)", text: $draft.brand)
            }
            Section("Serving") {
                HStack {
                    TextField("Size", value: $draft.servingSize, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("nutrition.newFood.servingSize")
                    TextField("Unit (g, ml, cup, slice)", text: $draft.servingUnit)
                        .accessibilityIdentifier("nutrition.newFood.servingUnit")
                }
            }
            Section {
                macroField("Calories", value: $draft.calories, unit: "kcal", identifier: "nutrition.newFood.calories")
                macroField("Protein", value: $draft.protein, unit: "g", identifier: "nutrition.newFood.protein")
                macroField("Carbs", value: $draft.carbs, unit: "g", identifier: "nutrition.newFood.carbs")
                macroField("Fat", value: $draft.fat, unit: "g", identifier: "nutrition.newFood.fat")
                optionalField("Fiber (optional)", value: $draft.fiber, unit: "g")
                optionalField("Sugar (optional)", value: $draft.sugar, unit: "g")
                if draft.showsCalorieMismatch {
                    Text("The macros add up to \(NutritionFormat.kcal(draft.macros.caloriesFromMacros)). Double-check the label.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Per serving")
            }
            Section("Log now") {
                Stepper(value: $draftServings, in: 0.25...50, step: 0.25) {
                    Text("\(NutritionFormat.number(draftServings)) servings")
                        .monospacedDigit()
                }
            }
            Section {
                Button {
                    createAndLog()
                } label: {
                    Label("Log \(draft.trimmedName.isEmpty ? "food" : draft.trimmedName)", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.matcha)
                .disabled(draft.trimmedName.isEmpty)
                .accessibilityIdentifier("nutrition.newFood.log")
            } footer: {
                Text("Saved to My foods so next time it's one tap.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// A zero shows as an empty field with a "0" placeholder, so typing a
    /// label value never has to start by deleting a digit.
    private func macroField(_ label: String, value: Binding<Double>, unit: String, identifier: String) -> some View {
        let display = Binding<Double?>(
            get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
            set: { value.wrappedValue = $0 ?? 0 }
        )
        return HStack {
            Text(label)
            Spacer()
            TextField("0", value: display, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func optionalField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityLabel(label)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            recentMeals = try service.recentMeals()
            savedMeals = try service.savedMeals()
            switch mode {
            case .recent: foods = try service.recentFoods()
            case .frequent: foods = try service.frequentFoods()
            default: foods = service.foods(matching: query)
            }
            if !query.isEmpty && mode != .myFoods {
                foods = foods.filter { $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.brand?.localizedCaseInsensitiveContains(query) ?? false) }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private var savedMealsList: some View {
        List {
            if savedMeals.isEmpty {
                ContentUnavailableView("No saved meals", systemImage: "bookmark",
                    description: Text("Open a logged day's meal menu and choose Save meal."))
            }
            ForEach(savedMeals) { meal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(meal.name).font(.headline)
                        Text("\(meal.orderedItems.count) \(meal.orderedItems.count == 1 ? "food" : "foods") · \(NutritionFormat.kcal(meal.totals.calories))")
                            .font(.caption)
                    }
                    Spacer()
                    Button("Log") {
                        complete { _ = try service.logSavedMeal(meal, to: slot, at: loggedAt) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.matcha)
                    .accessibilityLabel("Log saved meal \(meal.name)")
                    .accessibilityIdentifier("nutrition.logSavedMeal")
                }
            }
        }
    }

    private func logRecent(_ meal: RecentNutritionMeal) {
        complete { _ = try service.copyEntries(meal.entries, to: loggedAt, meal: slot) }
    }

    private func complete(_ action: () throws -> Void) {
        guard !didLog else { return }
        do {
            try action()
            didLog = true
            LogFeedbackCenter.shared.confirm(IdentityCopy.mealLogged)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func log(_ food: FoodItem, servings: Double) {
        guard !didLog else { return }
        do {
            try service.logEntry(food: food, servings: servings, meal: slot, at: loggedAt)
            didLog = true
            LogFeedbackCenter.shared.confirm(IdentityCopy.mealLogged)
            dismiss()
        } catch {
            errorMessage = "Couldn't log that. \(error.localizedDescription)"
        }
    }

    private func createAndLog() {
        guard !didLog else { return }
        do {
            let food = try service.createFood(name: draft.name,
                                              brand: draft.brand,
                                              servingSize: draft.servingSize,
                                              servingUnit: draft.servingUnit,
                                              macros: draft.macros)
            try service.logEntry(food: food, servings: draftServings, meal: slot, at: loggedAt)
            didLog = true
            LogFeedbackCenter.shared.confirm(IdentityCopy.mealLogged)
            dismiss()
        } catch {
            errorMessage = "Couldn't save that food. \(error.localizedDescription)"
        }
    }
}

/// Editable manual-entry fields. Per serving.
struct FoodDraft: Equatable {
    var name = ""
    var brand = ""
    var servingSize: Double = 1
    var servingUnit = "serving"
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double?
    var sugar: Double?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var macros: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar)
    }

    /// A label whose stated calories sit far from what the macros imply is
    /// usually a typo. Tolerance: 20 percent or 50 kcal, whichever is larger.
    var showsCalorieMismatch: Bool {
        guard calories > 0, macros.caloriesFromMacros > 0 else { return false }
        return abs(macros.caloriesFromMacros - calories) > max(50, calories * 0.2)
    }
}
