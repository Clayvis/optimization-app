# InBody Progress Coach and active status

Delivered scope: additive SchemaV12 scans; scan entry/edit/JSON import; scan comparison and history chart; profile controlled-hypertrophy focus; weekly set/RIR evidence; double-progression targets; optional existing Coach explanations. Train and Dojo both open InBody Coach.

## Interpretation

- Skeletal-muscle mass is a device estimate. Lean-mass change is never labeled muscle gain.
- ECW/TBW comparability is a product heuristic: absolute difference ≤0.003 high, ≤0.007 moderate, otherwise low. Missing values are unknown, never assumed moderate. Boundary comparisons tolerate floating-point error.
- Ratios do not establish measurement accuracy. The preparation context is still important. InBody describes skeletal muscle as a separately derived component of lean mass: https://inbodyusa.zendesk.com/hc/en-us/articles/32679229855636-How-is-Skeletal-Muscle-Mass-calculated . Preparation guidance: https://inbodyusa.com/wp-content/uploads/Preparatory-Steps-Flyer_v1.2_no-bleed.pdf .
- Body-fat percentage differences are **percentage points**, not percent changes.
- Scan intervals use local calendar days; same-day or reverse comparisons are rejected.
- Segmental measurements cannot isolate forearms or calves. No stalled calf/forearm growth is inferred from an arm/leg measurement.
- Weekly gain targets are user-selected planning targets, not universal medical thresholds. No automatic calorie changes.
- The dashboard's coach analysis is a deterministic verdict (`BodyCompositionAssessment`). Muscle, fat mass and body-fat percentage read as rising, stable or falling; a change within ±0.5 lb (muscle, fat mass) or ±0.5 percentage points reads as stable, because back-to-back BIA scans can differ that much from hydration and timing alone. The headline (for example "Productive muscle-gaining phase"), gain-rate status and recommendations derive from those trends, the selected weekly range, the training focus and hydration comparability. The bands are shown on screen and are product heuristics.

## Training

Activate the thighs/calves/forearms focus in the feature. The optional existing Coach receives deterministic observations alongside its existing nutrition/recovery context. Its explanation must preserve the rules. The dashboard works without an API key.

Only completed lift sessions enter the evidence window. Exercise names map conservatively to muscle groups. Unrecognized names remain unclassified. Forearm volume counts pulling as 0.5 effective set (a transparent planning approximation). Unrecorded RIR is unknown. Recovery limitations and Achilles restrictions prevent adding volume. High volume or low RIR with declining matched-exercise performance leads to fatigue review. Reallocation is capped at two weekly sets from a non-priority muscle; total planned volume stays stable.

RIR is optional per set and preserved in backup/restore. Double progression requires all planned working sets to reach the chosen upper rep target; an empty/incomplete session never qualifies. The app suggests a load increase; it does not silently change logged weights. No scan data is shared between profiles or seeded into other testers' stores.

## HealthKit investigation and repair

The observer acknowledged background delivery before its async persistence job finished, and a 60-second throttle discarded later Move updates. The callback now awaits the refresh before acknowledging. Every activity delivery fetches only active calories, exercise minutes and steps. Apple's callback contract: https://developer.apple.com/documentation/healthkit/hkobserverquery .

The Today legend distinguishes Exercise (minutes) from Move (active kcal), and displays the Health refresh age. iOS controls background delivery timing; this is not a continuous Apple Watch telemetry stream. Hardware verification remains required.

## Live status

Practice, hydration and fasting reminder requests are suppressed by the production notification service; pending habit reminders are removed on upgrade. The existing daily Live Activity shows the schedule block happening now (or the next one) and logged progress on Lock Screen and Dynamic Island. Practice lines come from the user's own schedule plus anything already logged that day, so a tester without Japanese or guitar blocks never sees those targets. It updates on foreground, confirmed logs and Health updates. The content turns stale at the earliest of one hour, the next schedule transition, or midnight, so it never shows a block that has ended; a stale status asks the user to reopen the app. A stale date is not automatic dismissal. Reopening reconciles yesterday's activities and starts/adopts today's. iOS ends any Live Activity after eight hours and a person can dismiss it; an ended or dismissed activity no longer counts as today's, the next foreground starts a replacement, and a frozen ended card is dismissed first (best effort). Refreshes run one at a time so simultaneous launch, foreground, log and Health triggers cannot start two activities. iOS limits Live Activity lifetime and background opportunities; no promise of automatic scheduled launches while suspended.

## Phone acceptance

1. Train → InBody Coach → + → Import scans. Select the locally supplied JSON file. Reimporting it must not duplicate records.
2. Verify the two dates and values, the coach analysis (expected with the supplied scans: productive muscle-gaining phase, muscle rising, fat mass rising, body-fat percentage stable, gain above the 0.25–0.5 lb/week range, moderate comparability), separate skeletal-muscle/lean/water changes, segment changes and weekly rate. Edit a scan and check recalculation.
3. Enable the training focus, log working sets with RIR, finish the session, and verify the seven-day evidence. Check that missing effort/pain constraints do not prompt more volume.
4. Open the app then lock the phone: active status should be visible if Live Activities are enabled. Previously scheduled practice reminders should no longer interrupt. Wait past the current or next schedule block boundary without opening the app: the card should ask you to reopen rather than show an outdated block. Swipe the card away, reopen the app, and confirm one new card appears.
5. Record activity with the Watch, allow it to sync to Apple Health, and compare Move kcal with the app. Check the displayed refresh age and foreground refresh. Repeat with the phone locked and note iOS background latency.
