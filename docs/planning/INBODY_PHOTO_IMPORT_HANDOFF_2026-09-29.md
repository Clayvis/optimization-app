# InBody scan from a photo

Date: 2026-09-29. Base: c2d2d66 on main. Checkout: /Users/phantom/Developer/optimization-app.

## Request

User: "the inbody scan would most likely be a picture taken from the phone, so either open a photo selecter or picture taker". Today a scan is typed field by field (InBody Coach, + menu, Add scan) or imported as JSON.

## Scope

- + menu on InBody Coach: take a photo of the result sheet (system camera, when the device has one) or choose a photo or screenshot (PhotosPicker, no library permission needed). Typing and JSON import stay. The document scanner was planned and dropped; see the design decisions.
- Read the sheet on the device with Vision text recognition. Nothing is uploaded and the photo is not saved.
- Map printed labels to InBodyValues: date, height, weight, skeletal muscle mass, lean body mass (fat-free mass), body-fat mass, percent body fat, total body water, ECW/TBW, visceral fat area, BMR, segmental lean mass (arms, trunk, legs; never the segmental fat rows). English and Japanese labels; kg sheets convert to lb, cm heights to inches.
- The editor opens prefilled and marks which values came from the photo. The user checks them against the sheet and saves; nothing saves without that step. Unread or implausible values stay blank. Existing validation and duplicate-day rules apply.
- No schema change. Camera usage text updated to cover result sheets.

## Status

Implemented 2026-09-29 by Claude; pushed as 38deb3a with GitHub CI green. Not yet observed on a real iPhone.

## Implementation

- `Modules/BodyComposition/InBodySheetParser.swift` (pure): `RecognizedTextLine`, `InBodyField`, `InBodyPhotoReading` (values, which fields were read, kilogram flag, `uncertain` alternatives), and the parser. Text is normalized ("201. 3" to 201.3, a letter O inside a number to 0, full-width digits). Rows are compared along the page's text angle. A value is taken beside its label, centered under a column header (height, test date, water, lean mass, weight), or inside a chart as a decimal (visceral fat area). Sections are assigned by the nearest header above in the same column; the control, segmental fat, history, impedance, reactance and phase-angle sections are skipped. Segment rows use the "(lb)" and "(%)" markers to keep the pound value and drop the percent-of-normal value. Split decimals ("22." + "84") are rejoined. Graph scales (three or more numbers), whole numbers where a decimal is printed, ranges in parentheses, signed numbers and implausible values are rejected. Kilogram sheets convert to pounds; centimeter heights to inches. English and Japanese labels.
- `InBodySheetParser.consensus` and `checkArithmetic`: two passes are combined per field (majority, ties to the sharper first pass) and disagreements are kept as alternatives. The sheet's own arithmetic (weight = lean + fat mass; percent fat = fat mass / weight) settles a split read and flags values that still don't add up. Nothing is derived to fill a blank.
- `InBodySheetRecognizer.swift`: decodes with the photo's orientation, runs Vision accurate text recognition (no language correction, small minimum text height) at two sizes (3024 and 2000 px long edge), and retries with Japanese only when English finds under four fields. Throws `unreadableImage` or `noValuesFound`.
- `InBodyCameraPicker.swift`: the system camera (not the document scanner) plus an upright JPEG helper.
- `InBodyProgressView.swift`: + menu now offers Take photo of results (when a camera exists; camera permission handled, with a Settings hint when denied), Choose photo (PhotosPicker, no library permission), Type values (was Add scan), Import JSON file. A "Reading your scan…" overlay while Vision runs off the main actor. The editor opens as "Check scan" with a summary (values read, what to check, what wasn't found, kilogram note), a mark on every value read from the photo, an orange warning on doubtful ones, and one-tap alternatives. Save uses the existing validation and duplicate-day rules.
- `InBodySampleSheet.swift` (Debug builds only): synthetic 770-style sheet with made-up values and every trap above; parser fixture, rendered image for the Vision test, and the `--ui-testing-inbody-photo` hook.
- `Info.plist`/`project.yml`: camera text now covers photographing result sheets. `InBodyValues` doc comment: values are printed results (typed, imported, or read from a photo and confirmed), never estimated from weight or a body photo.

## Design decisions from testing on the user's reference photo

The user supplied a photo of a real InBody 770 sheet (`~/Downloads/IMG_3499.heic`). It was used only locally, through a Mac command-line harness in the session scratchpad; no image or value from it is in the repository (public).

- A perspective-corrected copy (Core Image) misread printer digits ("4" as "1") and a homography from Vision's document outline skewed rows because the paper curls. Recognition therefore runs on the photo as taken.
- Digit recognition varies with image scale for this printer font, and Vision reported confidence 1.00 on wrong reads, so confidence cannot flag errors. Two sizes plus the sheet's arithmetic catch most of it.
- The document scanner flattens and enhances, which is the same resampling that blurred digits, so Take photo uses the plain camera.
- Result on the reference photo after these changes: all 16 fields read; 14 exactly right; 2 flagged for review with the correct value among the shown readings (one prefilled correctly, one prefilled with a misread). Reading time about 3.5 s on this Mac for both passes.

## Plan (done)

1. Parser (`InBodySheetParser`, pure) with unit tests on recognized-line fixtures: English lb sheet with ranges and graph scales, Japanese kg sheet, segmental lean vs fat sections, dates, heights, thousands separators, implausible values.
2. Recognizer (`InBodySheetRecognizer`, Vision) with an end-to-end test on a rendered synthetic sheet.
3. UI: menu entries, camera picker, PhotosPicker, reading state, prefilled editor with review banner.
4. UI test through a Debug-only synthetic-sheet hook (`--ui-testing-inbody-photo`), then full unit and UI suites, Release archive, commit, push, CI.

## Results

Verified 2026-09-29/30 with Xcode 26.6 on the iPhone 17 Pro simulator (iOS 26.5), shared with the Train and Dojo change (same commit).

| Check | Result |
|---|---|
| Unit suite | 919 passed, 0 failed (900 before, plus 5 lift and 14 photo-reader tests) |
| Photo reader suites | InBodySheetParserTests 11 and InBodySheetRecognizerTests 3 (Vision end to end on the rendered sample): all passed, rerun after the fixture values were made synthetic |
| UI suite (clean simulator install) | 17 passed, 0 failed, 0 non-exempt warnings, including `testInBodyPhotoPrefillsValuesForReview` (reads the sample, prefills, saves with the sheet's date) |
| Release archive (unsigned, generic iOS) | ARCHIVE SUCCEEDED, 0 non-exempt warnings; new camera text shipped; sample sheet absent from the Release binary; private scan file not bundled; Watch app and Live Activity embedded |
| Guards | schema parity, asset guard, `git diff --check`, no new hardcoded time zones |
| Reference photo (local harness only) | 16 of 16 fields read; 14 exact; 2 flagged with the correct reading shown |

Failures seen on the way, all resolved:

- The synthetic sheet rendered badly at first (headers merged, a scale tick overlapping a value, a monospaced slashed zero read as 8). The sample's layout and font were fixed; the parser was not changed for them.
- The saved-scan row is exposed to accessibility as one combined label ("Estimated skeletal muscle, 88.2 lb"); the UI test asserts that.
- Full UI run 1: `test_saveMealAndCopyPreviewCancelThenConfirm` lost a Back tap while the copy sheet was still closing under load. The test now waits until Back is tappable and retries once; it then passed 3 of 3 and in full UI run 2.
- The simulator launch flakes from TESTING.md (host hung before connecting; first launch without arguments) appeared twice and cleared after removing the app from the simulator.
- Real values from the reference photo had crept into comments and test inputs while debugging; all were replaced with synthetic values before commit, and the pending diff was searched for every value on the sheet.

## Next steps

1. Done: committed and pushed 38deb3a; GitHub CI passed (run 36598987796: guards, Release build, unit and UI tests, zero-warning policy). Xcode Cloud builds TestFlight from main.
2. Device checks below. If the camera reads worse than a library photo, compare with the same sheet photographed in the Camera app and chosen from the library.
3. Consider a third recognition pass or a cropped re-read for flagged chart values if device testing shows frequent disagreement.

## Device-only checks

- Document camera on a real printed InBody sheet; photo of the sheet from the library; a screenshot from the InBody app if used.
- Compare every prefilled value with the sheet before saving.
