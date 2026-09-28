# Nutrition Phase 3: barcode scanning and food database lookup

Date: 2026-09-28. Base: aa10de2 on main. Lands in one commit with the Train suggestions completion, since the two share files (fixtures, UI tests, project, docs).
Checkout: /Users/phantom/Developer/optimization-app. Do not work in the empty Desktop `optimization-app 2` directory.
Spec: docs/planning/NUTRITION_MODULE_HANDOFF.md sections 7 and 8.

## Scope

- Scan a packaged-food barcode with VisionKit DataScannerViewController (EAN-13, EAN-8, UPC-E, Code 128), with a typed-barcode fallback where the scanner is unsupported (simulator, older devices, camera denied).
- Lookup order: local FoodItem by barcode, then Open Food Facts (no key). FatSecret needs developer keys the user has not provided yet; it sits behind the same provider protocol and stays off until keys exist. Never commit keys.
- Cache every external hit as a FoodItem with `source` and `externalID`; never re-fetch a barcode already stored locally.
- On a hit: serving picker defaulting to one serving, log on confirm (two taps after the scan). On a miss: "Create custom food" prefilled with the barcode.
- Attribute Open Food Facts in the food detail per its terms (ODbL).
- No schema change expected: FoodItem already has barcode, source, externalID and servingsPerContainer (SchemaV11).
- Camera usage string is required in Info.plist and project.yml before shipping any scanner code.

## Status

Implemented and verified on the simulator 2026-09-28 by Claude (see Results). No schema change for this phase. Not yet observed on a real iPhone (see Device-only checks).

## Implementation

- `Modules/Nutrition/FoodDatabase/Barcode.swift`: digits-only parsing, GTIN check digit (EAN-8, UPC-A, EAN-13, GTIN-14), UPC-E to UPC-A expansion, and `lookupKeys` (every equivalent spelling, canonical EAN-13 first). A Code 128 label or a bad check digit yields no keys and no network call.
- `FoodDatabase.swift`: `ExternalFood` (macros nil when the database lacks facts), `FoodDatabaseProvider` protocol, `FoodLookupError`, `FoodDatabaseProviders.current()` (UI tests get none, so they never touch the network), and `OpenFoodFactsProvider` (API v2 over URLSession, 8 s timeout, identifying User-Agent without personal data, 404 = not found). Parser: per-serving label values win, else per-100 g scaled to the serving quantity, else per 100 g; kJ-only energy converts at 4.184; numeric strings accepted; Japanese name fallback; servings per container when units match; missing energy or name means incomplete, never guessed.
- `BarcodeFoodLookup.swift`: local catalog first (any equivalent spelling, most used first), then providers (canonical and UPC-A spellings); a complete hit is saved as a FoodItem with source, externalID, canonical barcode and servings per container; incomplete hits are not saved.
- `Views/BarcodeScanPanel.swift`: VisionKit DataScannerViewController (EAN-13, EAN-8, UPC-E, Code 128) when supported and permitted, typed-barcode fallback otherwise (simulator, older devices, camera denied, with a Settings link). Camera permission is requested on first use of Scan, not at launch. Found: name, brand, per-serving facts, Open Food Facts attribution, servings stepper and one-tap Log. Miss or incomplete: New food prefilled and carrying the barcode.
- `AddFoodSheet.swift`: Scan tab (after Saved meals) plus a barcode toolbar button; New food shows the note and barcode and saves the barcode on the food.
- `FoodEntryEditSheet.swift`: a logged entry whose linked food came from Open Food Facts shows the ODbL credit under its facts (the entry snapshots facts, not source, so the sheet reads the linked food once on appear; a deleted food shows no credit).
- `Info.plist` + `project.yml`: NSCameraUsageDescription. The Watch target excludes `FoodDatabase/**` (network lookup is phone-only).
- Tests: `BarcodeLookupTests.swift` (normalization, parser, transport via URLProtocol stub, lookup order/caching); UI `test_scannedBarcodeLogsTheFoundFood` (scan, credit, one-tap log, then the logged entry's credit), `test_unknownBarcodeBecomesAFoodTheNextScanFinds` with fixture `--ui-testing-barcode-food`.

## Not done yet

- FatSecret provider: needs the user's developer keys through Xcode Cloud environment variables (never committed). Add `FatSecretProvider: FoodDatabaseProvider` (OAuth 2 client credentials, token cached in memory), append it after Open Food Facts in `FoodDatabaseProviders.current()` only when keys are present, and extend `BarcodeLookupTests` with a stub transport. With a second provider, decide whether a network failure in one falls through to the next: today a provider error ends `BarcodeFoodLookup.lookup` (correct with a single provider).
- Text search against the food database (Phase 4 in the module spec).
- App Store privacy label: Open Food Facts receives product barcodes only (no user identifiers, no tracking). Review the label wording before the next submission.

## Results

Verified 2026-09-28 with Xcode 26.6 (17F113) on the iPhone 17 Pro simulator (iOS 26.5). The Train completion and this phase landed in one verification pass because they share files. Logs and result bundles are in the session scratchpad; commands are below.

| Check | Result |
|---|---|
| Unit suite (`final-unit`) | 900 passed, 0 failed, 0 non-exempt warnings |
| New barcode suites | BarcodeTests 4, OpenFoodFactsParserTests 7, OpenFoodFactsProviderTests 2, BarcodeFoodLookupTests 6: all passed |
| Released-store upgrades | V10, V11 and released V12 stores to V13: all 3 passed |
| LiftServiceTests stress | 20 iterations of 21 tests (420 runs), 0 failures |
| Coach regression test | passed; with the new sort removed it fails 4 assertions (finished plan returned as today's, started plan replaced, extra network call, extra row), so it guards the fix |
| UI suite (`final-ui-4`, clean simulator install) | 15 passed, 0 failed, 0 non-exempt warnings, including both barcode flows (scan and credit, then the logged entry's credit; unknown code to New food to a local hit) and both suggested-workout flows |
| Release archive (`PO4.xcarchive`, unsigned, generic iOS) | ARCHIVE SUCCEEDED, 0 non-exempt warnings; camera usage string shipped; Watch app and Live Activity embedded; private scan file not bundled |
| Guards | schema parity, asset guard, `git diff --check`, no new hardcoded time zones: all passed |

The archive was built after the last app-code change; later edits touched only UI tests and docs.

Commands (fresh result/archive paths per rerun; see TESTING.md for the simulator flakes):

```sh
xcrun simctl uninstall <udid> com.rawlins.PersonalOptimization.uitests.xctrunner
xcrun simctl uninstall <udid> com.rawlins.PersonalOptimization
xcrun simctl shutdown <udid>; xcrun simctl boot <udid>; xcrun simctl bootstatus <udid> -b
bash scripts/check_schema_parity.sh && bash scripts/check_assets.sh
xcodebuild test -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/po-dd -resultBundlePath /tmp/po-unit.xcresult -only-testing:PersonalOptimizationTests -parallel-testing-enabled NO -jobs 3 COMPILER_INDEX_STORE_ENABLE=NO
xcodebuild test -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/po-dd -resultBundlePath /tmp/po-ui.xcresult -only-testing:PersonalOptimizationUITests -parallel-testing-enabled NO -jobs 3 COMPILER_INDEX_STORE_ENABLE=NO
xcodebuild archive -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/po.xcarchive -derivedDataPath /tmp/po-release CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO -jobs 3
```

### Verification history (failures seen and resolved)

- `combined-full-1`: all 15 UI tests passed; the unit host hung before connecting (documented simulator flake).
- `combined-unit-2`: 899 tests, 1 failure in the order-dependent LiftServiceTests assertion. Fixed (see the Train handoff).
- `combined-unit-3`: 42 failures, all bundled JSON "no such file" under a `containermanagerd/Dead` path. The simulator retired the installed bundle mid-run after back-to-back installs; the built app held every file. Environmental; documented in TESTING.md.
- `final-ui`: `testNutritionFirstFoodLogsFromTodayWithoutSetup` tapped Log while it sat under the number pad (reported hittable). New helper `tapClearOfKeyboard` scrolls until the control exists and clears the keyboard; used for both New food Log taps. With it, the first-food test passed 5 of 5 runs and the unknown-barcode test 2 of 2 that reached it.
- `final-ui-2`, `keyboard-iter-2`, `final-ui-3`: the first test of each run failed at its first wait. App logs show that launch ran without `--ui-testing` (CloudKit, notification authorization, background task submission). In each case the simulator had relaunched the app in the background without arguments 20 to 30 s before the first test; runs with no leftover instance passed. Every other test passed. Removing the app and UI test runner from the simulator and booting fully cleared it (`final-ui-4`: 15 of 15). Documented in TESTING.md.
- Coach mutation check: two runs hung before connecting (unit-host launch flake); the third, after a full boot, ran and failed as expected.
- GitHub CI for 9893f16 (Xcode 26.4.1, iOS 26.4.1 simulator, run 36397466214): 1 failure. `test_scannedBarcodeLogsTheFoundFood` found no Scan barcode button right after tapping Quick add; the unknown-barcode test tapped the same button in that run, so the tap outran the sheet on the slower runner. Both barcode tests now go through `openBarcodeScan`, which waits until Quick add and then Scan are tappable, and Look up waits the same way. Job logs and artifacts need repository admin rights; this came from the public check-run annotation (`/repos/Clayvis/optimization-app/check-runs/<job id>/annotations`). Fixed in c15f887; CI run 36401524862 passed.

## Next steps

1. Done: pushed 9893f16 and the UI-test fix c15f887. GitHub CI passed on c15f887 (run 36401524862): guards, checked-in Release build, unit and UI tests, zero-warning policy. Xcode Cloud builds TestFlight from main; both commits carry the same app code.
2. Device checks below, installing over the existing app (never delete or reinstall).
3. FatSecret once keys are available (see "Not done yet").

## Device-only checks

- Camera permission prompt and live scanning on a real iPhone; scan-to-logged under five seconds on a real product.
- Japanese products off base (Open Food Facts coverage), US products on base.
- Camera denied: Scan shows the typed-barcode field and the Settings link; allowing access in Settings brings the live scanner back.
