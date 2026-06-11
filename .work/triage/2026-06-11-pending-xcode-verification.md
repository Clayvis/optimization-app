# Pending Xcode verification: Training + Learning tab revamps

Branch: `claude/training-tab-redesign-tnqr3y`
Authored in a remote Linux container (no Xcode). Symbols and initializers were
verified against the codebase by inspection; nothing on this branch has been
compiled or run.

## Changed files

- `PersonalOptimization/Modules/Training/Views/TrainingHubView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/Views/LearningHubView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/Views/LearningTimerView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/LearningModule.swift` (added `iconName`)
- `PersonalOptimization/Components/DojoComponents.swift` (added `DojoPressStyle`)

## Verify at the workstation

1. `xcodebuild -scheme PersonalOptimization build` with zero warnings (Swift 6
   strict concurrency; the new views are all view-layer, no new actors).
2. `xcodebuild test -scheme PersonalOptimizationTests`.
3. Open the four `#Preview`s (TrainingHubView, LearningHubView,
   LearningTimerView, DojoComponents) and confirm they render with seeded data.
4. Simulator pass, both color schemes:
   - Training: week dot strip marks today, tiles navigate, resume banner
     appears when a lift is left with `durationMinutes == 0`, custom activity
     sessions appear in Today's log.
   - Learning: hero ring percent matches per-module capped math, live ring
     advances while the stopwatch runs, quick-log chips write through
     `LearningService.logMinutes`, Pimsleur deep link still opens.

## Known behavior notes (intentional, not regressions)

- Learning stopwatch state (`startedAt`) is still view-local `@State`; leaving
  the screen mid-session drops the running timer, same as before the revamp.
- Week-at-a-glance counts completed sessions only (lift `durationMinutes > 0`,
  basketball `endTime > startTime`, swim `durationMinutes > 0`). No targets
  invented; dots show days with at least one completed session.
- Training "Today" card now excludes in-progress lifts (the old list counted a
  zero-duration lift as a completed session).
