# HANDOFF: Nutrition Module for PersonalOptimization

**App:** PersonalOptimization (com.rawlins.PersonalOptimization, Team ID 3CJVG5DM62)
**Stack:** SwiftUI, SwiftData, CloudKit, HealthKit, Anthropic API, watchOS, Live Activities
**Author:** Clay Rawlins
**Date:** 2026-09-09
**Status:** New feature spec. Read HANDOFF_CLAUDE_CODE.md first for existing architecture and conventions.

Implementation notes live in `.work/decisions/020-nutrition-module-data-model.md` (local) and in the source comments. Phase 1 landed 2026-09-09.

---

## 1. Goal

Add a calorie and macro tracking module that replaces MyFitnessPal for a daily user. The primary user is my wife, Amber, who already tracks calories every day for fitness goals. She is the second TestFlight tester.

The bar is not "has the same features as MFP." The bar is "logging a meal is as fast or faster than MFP, and the data she cares about is one glance away."

Success criteria:
- A repeat meal (something eaten in the last 14 days) can be logged in 3 taps or fewer from the app's home screen.
- Barcode scan to logged item in under 5 seconds on a real product.
- Daily remaining protein and calories visible without scrolling on iPhone and on the watch complication.
- All logged nutrition writes to HealthKit so Apple Health and any other app see it.

## 2. Non-goals

- No MyFitnessPal API integration. MFP's API is private and approval-only. Interop happens through HealthKit only.
- No social features, no streaks beyond what the existing engagement architecture already defines, no meal plans, no recipe discovery.
- No micronutrient tracking in v1 (vitamins, minerals). Fiber and sugar are the only sub-macros in v1.
- No Android.

## 3. Prerequisites from the existing P0 list

These existing blockers directly affect this module. Resolve them before or alongside it:

1. **DailyLog date uniqueness constraint.** Nutrition entries hang off DailyLog. Without a unique-per-day constraint, meals will split across duplicate day records.
2. **Hardcoded timezone references (76 known).** Meal timestamps and "today" boundaries must use the user's current time zone. We live in Okinawa (JST, UTC+9). Any UTC-midnight assumption will put late dinners on the wrong day.
3. **CloudKit schema mismatch across targets.** New models below must be added to all three targets' schemas in the same commit.
4. **HealthKit background delivery.** Needed so exercise energy from the watch updates the daily budget without opening the app.

## 4. Feature priority

Build in this order. Each phase should ship to TestFlight on its own.

| Phase | Feature | Why this order |
|---|---|---|
| 1 | Data model, daily targets, manual entry, HealthKit write | Foundation. Usable on day one even without a database. |
| 2 | Recent / frequent / saved meals, copy previous day | This is 80% of daily use and the main reason people stay with MFP. |
| 3 | Barcode scan + food database lookup | Packaged foods. Second most used MFP feature. |
| 4 | Text search against food database, custom foods, recipes | Covers everything barcode misses. |
| 5 | Exercise calorie adjustment from HealthKit | Ties into watch data already in the app. |
| 6 | Photo estimate via Anthropic API | Fallback for restaurant and mixed plates. Novel, but lowest daily frequency. |
| 7 | Weight trend (7-day moving average) | Small, reads from HealthKit, closes the loop on the fitness goal. |
| 8 | watchOS logging + complication | Only after phone flow is stable. |

## 5. Data model (SwiftData)

All models sync via CloudKit. Follow existing naming conventions in the codebase.

```swift
@Model final class FoodItem {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?              // UPC/EAN, indexed
    var source: FoodSource            // .userCreated, .openFoodFacts, .fatSecret, .nutritionix, .photoEstimate
    var externalID: String?           // ID in the source database, for refresh
    var servingSize: Double
    var servingUnit: String           // "g", "ml", "cup", "slice", etc.
    var servingsPerContainer: Double?
    var calories: Double              // per serving
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var isFavorite: Bool
    var lastUsed: Date?
    var useCount: Int
    var createdAt: Date
}

@Model final class FoodEntry {
    var id: UUID
    var dailyLog: DailyLog            // existing model, relationship
    var food: FoodItem
    var meal: MealSlot                // .breakfast, .lunch, .dinner, .snack
    var servings: Double              // multiplier on FoodItem serving
    var loggedAt: Date
    var healthKitSampleIDs: [UUID]    // for delete/edit sync back to HealthKit
}

@Model final class SavedMeal {
    var id: UUID
    var name: String                  // "Usual breakfast"
    var items: [SavedMealItem]
    var lastUsed: Date?
    var useCount: Int
}

@Model final class SavedMealItem {
    var food: FoodItem
    var servings: Double
}

@Model final class Recipe {
    var id: UUID
    var name: String
    var ingredients: [SavedMealItem]
    var totalServings: Double
    // computed per-serving macros; expose as a FoodItem for logging
}

@Model final class NutritionTargets {
    var id: UUID
    var effectiveFrom: Date           // targets change over time; keep history
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var eatBackExerciseCalories: Bool // default false
    var exerciseEatBackPercent: Double // 0.0 to 1.0, default 0.5 when enabled
}
```

Notes:
- Targets are stored in grams, not percentages. UI can display either. Percent-of-calories drifts when calories change; grams are what people actually hit.
- Keep a history of NutritionTargets so past days are evaluated against the targets that applied then.
- `useCount` and `lastUsed` on FoodItem and SavedMeal drive the Recent and Frequent lists. Do not compute these from FoodEntry at query time; it gets slow.

## 6. HealthKit integration

**Write on every FoodEntry create/edit/delete:**
- `HKQuantityTypeIdentifier.dietaryEnergyConsumed` (kcal)
- `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal` (g)
- `.dietaryFiber`, `.dietarySugar` when present

Group samples for one entry with `HKCorrelationType.food` so Apple Health shows them as a single meal. Store returned sample UUIDs on the FoodEntry so edits and deletes can remove the old samples first.

**Read:**
- `.activeEnergyBurned` for the day, summed, for the exercise adjustment. Use `HKStatisticsQuery` with `.cumulativeSum`, not raw samples.
- `.bodyMass` for weight trend.
- Dietary types written by other apps (MFP, Lose It, etc.) so if she double-logs elsewhere the app can show it. Display these as "logged in other apps" and do not import them into FoodEntry; that creates duplicates.

**Authorization:** request nutrition read/write on first open of the nutrition tab, not at app launch. Add the required `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` strings.

## 7. Food database strategy

Search order for barcode and text lookup:

1. **Local SwiftData** (user's own FoodItems, favorites, recents). Always first, always offline.
2. **Open Food Facts** (free, open license, no key required). Good for barcodes, decent for Japanese products since we shop off-base. `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
3. **FatSecret Platform API** (free tier: 5,000 calls/day). Better US brand coverage. OAuth 2 client credentials flow. Requires a developer account; I will provide keys via Xcode Cloud environment variables, never committed.
4. **Nutritionix** (optional, freemium). Best for US restaurant chains. Add only if FatSecret coverage proves insufficient in testing.

Rules:
- Cache every external result as a FoodItem with `source` and `externalID` set. Never re-fetch something already local.
- Rate limit and debounce text search (300 ms after last keystroke, cancel in-flight).
- If all sources miss, offer "Create custom food" prefilled with whatever was typed or scanned.
- Attribute sources in the item detail view per each service's terms.

## 8. Barcode scanning

Use `VisionKit.DataScannerViewController` with `recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])]`. Requires iOS 16+, which the app already targets. No third-party scanning library.

Flow: scan → local lookup → Open Food Facts → FatSecret → "not found, create custom." Show a serving-size picker on hit, default to 1 serving, log on confirm. Two taps after scan.

## 9. Photo estimate (Anthropic API)

Use the existing Anthropic API client in the app. Send the image as base64 with the prompt below. Force JSON output. Parse into a temporary list the user can edit before anything is saved.

**System prompt (draft, tune in testing):**

```
You estimate the nutritional content of food from a photo. Respond with JSON only, no prose, no markdown fences.

Return this schema:
{
  "items": [
    {
      "name": string,
      "estimated_portion": string,   // e.g. "1 cup", "6 oz", "2 slices"
      "portion_grams": number,
      "calories": number,
      "protein_g": number,
      "carbs_g": number,
      "fat_g": number,
      "confidence": "low" | "medium" | "high"
    }
  ],
  "notes": string   // one sentence on what was uncertain
}

Assume a standard 10-inch dinner plate unless something in the image gives a better scale reference. If the image is not food, return {"items": [], "notes": "No food detected."}. Prefer under-estimating portion size over over-estimating when unsure.
```

Rules:
- Model: use whatever the app already uses for other calls; do not hardcode a new one.
- Downscale images to max 1024 px on the long edge before upload. Saves cost and latency.
- Every item shows its confidence in the review UI. Low confidence items get a visible "check this" hint.
- Nothing is saved until the user taps Confirm. Edited values win over model values.
- Items saved from photo get `source = .photoEstimate` so they are excluded from the Frequent list (a photo guess should not become a permanent database entry by accident). The user can promote one to a custom food.
- Handle offline: queue the photo and show "Will estimate when online."

## 10. Daily view and targets

Home nutrition card (also the watch complication):
- Protein remaining is the headline number, then calories remaining, then carbs and fat. This is a fitness user, not a weight-loss-only user. Protein first.
- Rings or bars; reuse the existing engagement ring component if one exists.
- "Remaining" = target minus logged, plus (exercise calories × eatBackPercent) when `eatBackExerciseCalories` is true.
- Tapping the card opens the day, grouped by MealSlot, each slot with an inline "+" that opens the add sheet already filtered to that slot.

Add sheet tabs: **Recent**, **Frequent**, **Saved Meals**, **Search**, **Scan**, **Photo**. Recent is the default tab.

Day actions: "Copy yesterday," "Copy [meal] from [date]," "Save this meal."

## 11. Exercise adjustment

- Read `activeEnergyBurned` sum for today via HealthKit background delivery.
- Setting: Eat back exercise calories (off by default). When on, a percent slider, default 50%. Watch and phone calorie estimates run high; 50% is the sane default.
- Show the adjustment as its own line in the day view so the math is transparent.

## 12. Weight trend

- Read `bodyMass` from HealthKit; do not build a separate weight entry unless HealthKit has no data source.
- Chart the 7-day moving average as the primary line, raw points faded behind it.
- No goal-weight countdown in v1.

## 13. watchOS (Phase 8)

- Complication: protein remaining / calories remaining.
- Watch app: Recent and Saved Meals lists only. Tap to log with a servings stepper. No search, no scan, no photo on the watch.
- Use the existing WatchConnectivity or CloudKit path the app already uses for DailyLog.

## 14. Testing

- Unit tests for target math, exercise eat-back math, and day boundary in JST. Include a test where a meal is logged at 23:45 JST and confirm it lands on that date, not the next UTC date.
- Unit test for HealthKit sample delete-then-rewrite on entry edit.
- Manual test plan for Amber: log one full day using only Recent/Saved, one day using barcode for every packaged item, one restaurant meal by photo. Collect where each flow took longer than MFP.

## 15. Open questions for me

1. Do we want per-meal calorie targets (e.g., breakfast 25%) or only daily? Default to daily only unless Amber asks.
2. Should custom foods sync across our two accounts (shared family database) or stay per-user? Default per-user for v1.
3. FatSecret vs Nutritionix: decide after Phase 3 testing on real products we actually buy.

## 16. Definition of done for v1 (Phases 1 through 6)

- Amber can log a full day without opening MyFitnessPal.
- All entries appear in Apple Health under Nutrition.
- No duplicate DailyLog records after a week of use.
- Photo flow never saves without user confirmation.
- No new hardcoded time zones introduced (grep for `TimeZone(identifier:` and `TimeZone(secondsFromGMT:` in the diff).
