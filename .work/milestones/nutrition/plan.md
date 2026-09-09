# Nutrition module plan (spec: docs/planning/NUTRITION_MODULE_HANDOFF.md)

Ship each phase to main on its own (CI + Xcode Cloud → TestFlight).

## Phase 1 (this pass)
- Models: FoodItem, FoodEntry, SavedMeal, SavedMealItem, NutritionTargets; SchemaV11; AppSchema bump; migration stage.
- NutritionMath (pure): day totals, remaining, eat-back, target prefill, macro percent.
- NutritionService (@MainActor): targets history, create food, log/update/delete entry, day summary, use counters, HK dispatch.
- HealthKit: protocol methods (nutrition auth, save food correlation, delete by entry), Live impl, fake updates.
- UI: NutritionDayView (day header, per-slot sections, add/edit sheets, targets sheet), AddFoodSheet (manual entry + my foods), NutritionTodayCard on Today, Dojo tile.
- Info.plist usage strings (iOS + watch + project.yml).
- Tests: math, day boundary JST, targets history, snapshot, HK delete-then-rewrite, use counters.
- Gates: xcodegen generate, schema parity, Debug sim tests, Release device build zero warnings, commit, push.

## Phase 2
Recent / Frequent / Saved meals tabs, copy yesterday, copy meal from date, save this meal.

## Later
3 barcode + OFF/FatSecret, 4 search/custom/recipes, 5 exercise eat-back UI, 6 photo estimate, 7 weight trend, 8 watch.
