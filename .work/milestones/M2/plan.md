# M2 Plan: Fasting + Hydration + Live Activities

## Goal

User sees fast countdown on watch complication, logs water from watch quick-tap, receives hydration reminders, has Live Activity for active fast on Lock Screen and Dynamic Island.

## Phases (each with build + tests + atomic commit)

### Phase 1: Fasting service + state machine
- Load `fastingDefaults` from `default_schedule.json` (already bundled).
- `FastingService` with: `currentWindow(for: Date) -> FastWindow?`, `state(at: Date) -> .fasting | .eating | .transition`, `elapsedFasting(at: Date) -> TimeInterval`, `remainingInFast(at: Date) -> TimeInterval?`.
- Phased rollout: weeks 1-2 vs 3+. Read from `UserProfile.rolloutPhase`.
- Phase 1 has training-day fast (start 21:00, end 09:00) on days {1,2,4,5} and other-days fast (22:00-10:00). Phase 2 all-days 22:00-10:00.
- Early-break logger: writes `DailyLog.fastBrokeEarly = true`, `DailyLog.fastBreakReason = ...`.
- Tests: state at boundaries, transition windows, phase-1 vs phase-2, early-break logging, midnight rollover.

### Phase 2: Hydration service
- Load `hydrationTargetsOz` from JSON.
- `HydrationService.targetForDayType(date:profile:) -> ClosedRange<Double>`.
- `HydrationService.logBottle(oz: Double, date:)` upserts today's `DailyLog`, increments `waterOz`.
- `HydrationService.logElectrolyte(date:)` increments `DailyLog.electrolyteSessions`.
- `HydrationService.intakeForToday(date:) -> Double`.
- Tests: per-day-type targets (rest=110-130, lift=140-160, basketball=160-190, swim=120-140), upsert behavior, bottle log accumulates correctly.

### Phase 3: NotificationService
- Local-only via `UserNotifications`.
- `register()` requests authorization (sound, badge, alert), idempotent.
- `scheduleFastStart(at:)`, `scheduleFastEnd(at:)`, `scheduleHydrationReminder(at:cadence:)`.
- Categories registered with action identifiers (e.g., "log_8oz", "log_16oz", "skip").
- Suppression filter (in service, before scheduling): skip during sleep window 22:00-07:00, skip during active workout (M3 hook), skip pre-1000 if morning intake logged.
- Tests: window suppression rules, schedule lookup, idempotent registration.

### Phase 4: Phone Fasting view
- Phone tab: live elapsed/remaining countdown using SwiftUI `TimelineView`.
- Visual ring filling against the fast window.
- Early-break button with reason picker, writes to DailyLog.

### Phase 5: Phone Hydration view
- Phone tab: hourly breakdown vs daily target band.
- Bottle log buttons (8/16/24/32 oz).
- Electrolyte log button.
- Day-type label ("today is a basketball day").

### Phase 6: Watch quick-log hydration
- Watch view with 4 large tap targets (8/16/24/32 oz), electrolyte toggle.
- Haptic confirmation on tap.
- Posts via `WatchConnectivity` (best effort) and direct SwiftData write fallback (so it works without phone).

### Phase 7: Watch complication alternate face: fast countdown
- Add a second Widget kind to existing `PersonalOptimizationWatchComplications` extension.
- Families: accessoryRectangular, accessoryCircular (ring), accessoryInline.
- Renders fast state + remaining time.

### Phase 8: PersonalOptimizationLiveActivity extension target
- New target via xcodegen. Bundle ID: `com.rawlins.PersonalOptimization.liveactivity`.
- ActivityKit framework. ActivityAttributes with start/end dates so the OS computes progress without app updates.
- Lock screen view + Dynamic Island compact, expanded, minimal.

### Phase 9: FastingLiveActivity wiring
- `FastingService.startActivity(window:)`, `endActivity()`.
- Triggered when fast starts (manually or auto at window boundary).

### Phase 10: M2 close
- Run all tests.
- Build all schemes clean.
- Commit any final adjustments.
- Push to GitHub.
- Tag `m2-complete`.
- Update `.work/state.json`.

## Surfaced unknowns (resolving with spec-aligned defaults)

1. **Notification authorization timing**: request on first scheduling attempt, not at app launch. Avoids permission prompts during onboarding. ARCHITECTURE.md is silent; this matches Apple HIG.
2. **Auto-start fast at window boundary**: not specified explicitly. Default to manual start (user taps "Start fast"). Auto-start can be a notification action button instead.
3. **Live Activity dismissal policy**: dismiss `.atEnd` of fast window. ActivityKit best practice.
4. **Watch quick-log offline behavior**: write directly to SwiftData on watch (already syncs via CloudKit per Phase 1 wiring); WatchConnectivity is opportunistic for low-latency phone update only.
5. **Hydration cutoff**: per JSON `hydrationCutoffTime: 21:00`, no hydration nudges after 21:00 JST.

## Estimated work

12-16 hours per MILESTONES.md.

## Authority

Per user's autonomous-execution preference (saved to memory), I will not stop for confirmation on ambiguous-but-reversible calls. Decision records get written for any spec deviation.
