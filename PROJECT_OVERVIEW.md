# PersonalOptimization — Project Overview

A single-user iOS 18 + watchOS 11 personal optimization app. One user (Clay, 31, Marine veteran, ex-Amazon SDE, ERAU student in Okinawa). Zero servers. Zero accounts. Zero third-party Swift packages. Built to be the brain Clay carries on his wrist and in his pocket through the next chapter of his life.

This document is the consolidated mission, research foundation, decisions, and milestone-by-milestone state of the build. It exists so a fresh contributor (or a future Claude Code session) can pick up the work without re-deriving why it is the way it is.

---

## 1. Mission

Make daily protocol adherence **frictionless** and **honest** for one specific person, then prove the design holds for a second (Clay's wife — active duty Marine, three young children, very different equipment access and goals). The app must:

1. Replace the cognitive load of "what should I do today and did I do it" with one tap on a phone or wrist.
2. Persist a year-plus of activity history so a coach (the AI, the user himself, his wife) can reason from real patterns instead of recall.
3. Reward consistency without faking it. Streaks bend for sick days and travel, never break for honest effort.
4. Stay offline-first and privacy-respecting. SwiftData + CloudKit private database. No analytics. No ads. No third-party dependencies.

**Definition of v1 done:** all 8 milestones (M1, M2, M3, M3.5, M3.6, M3.7, M3.8, M4) close. App runs on iPhone 16 Pro and Apple Watch Ultra 2 hardware. 7-day end-to-end usability test passes.

---

## 2. User Profile

The single source of truth design constraint.

| Attribute | Value |
|---|---|
| Age | 31 |
| Height / Weight | 6'2" / 205 lbs |
| Background | Marine veteran (2012-2021), former Amazon SDE (2021-2024) |
| Current | BS Technical Management at Embry-Riddle Worldwide (~90 credits, graduating April 2027) |
| Location | Uruma City, Okinawa, JST (UTC+9) |
| Family | Wife (active duty USMC E-6), three young children |
| Daily anchor | Kid drop-off 0900, pickup 1700, Mon-Fri |
| Physical constraints | Achilles tendonosis (no running) |
| Tech background | Java, Python, React, Spring, AWS, CI/CD. Early in Swift but systems-thinking wired |

Every design decision is filtered through this profile. The app does not ask "what if you have a treadmill?" because Clay has Achilles tendonosis and explicitly cannot run.

---

## 3. Research Foundation — The Seven Design Principles

Source: 2024-2025 systematic reviews on habit formation app design (cited in `PIVOT_SPEC.md`, locked into `CLAUDE.md` as load-bearing from M3.5 onward). These are not aesthetic preferences. They are the rails the codebase rides on. When two design ideas conflict, the principle wins.

### 3.1 Implementation intentions over reminders

**Research:** Gollwitzer's implementation-intention literature (1999 onward, replicated through 2024 systematic reviews) finds that "if-then" trigger anchoring more than doubles habit formation rates compared with time-based reminders. People act on context cues (after coffee, after dinner, on block start), not on clocks.

**In the code:** Notification text and prompts are anchored to events ("after morning coffee", "on block start"), not raw times. M4 will deliver the full Implementation Intention model; the engagement engine in M3.5 already uses block-start cues for adaptive notification timing.

### 3.2 Streaks need mercy

**Research:** Duolingo's 2022 internal study (later corroborated by behavioral-design reviews in 2024) found that streak freezes and forgiveness mechanics increase 90-day retention by ~30%. Brittle streaks induce abandonment after a single miss because the user-perceived "ruined" state extinguishes motivation.

**In the code:** `StreakService` ships with monthly freeze inventory (2/month), Sick Day grace, Travel Mode (multi-day), and a `FreezeApplication` ledger. Streaks are recomputed from history, never just incremented. Honest data > inflated streaks (see HydrationService.deleteEntry — recomputes the streak after a deletion drops the day below target).

### 3.3 Notification minimum effective dose

**Research:** Push notification studies converge on a J-shaped engagement curve. Past 1 nudge per behavior per day, marginal engagement turns negative. App Store reviews of habit apps show "too many notifications" as the #1 deletion reason.

**In the code:** `AdaptiveNotificationTiming` learns the user's natural log time over 14 days and sends one nudge per behavior per day max. Suppress if already logged. Notification bundling toggle in Settings for the "morning summary instead of individual alerts" preference.

### 3.4 Identity framing over task framing

**Research:** James Clear's *Atomic Habits* synthesizes work by Wood, Lally, and Neal: identity-based habits ("I am the kind of person who shows up") form 2-3x faster than outcome-based goals ("I want to lose 10 lbs"). This is now standard prescription in behavioral psychology.

**In the code:** `IdentityCopy` enum centralizes identity-framed strings. Schedule editor copy: "Your schedule. Your protocol." Lift completion: "12,400 lb moved. That's the work." Coach prescription title: "Today's prescription for you." Custom activity start: framed as expressing identity, never compliance.

### 3.5 Friction reduction first

**Research:** BJ Fogg's Behavior Model (Behavior = Motivation × Ability × Prompt) identifies *ability* (low friction) as the highest-leverage variable. Apps that reduce log time below ~5 seconds see 3-5x daily engagement.

**In the code:** Hydration quick-pick presets (one tap), creative-named workout prescription (one tap accept), wrist quick logs (M3.8), inline custom-exercise add (no nested menus), schedule template chooser (single confirmation). Sensory feedback on log to make every micro-success feel real (`sensoryFeedback(.increase)` on hydration log, M3.7 polish).

### 3.6 One master metric

**Research:** Behavioral-economics research on cognitive load (Sweller, then 2010s+ application) finds that single-number focus drives action. Multiple competing dashboards produce decision paralysis. Apple Activity rings work because "close all three" is the only goal.

**In the code:** `DailySummaryService` produces "X/Y of today's protocol complete" — one number, foregrounded on the Today tab. All sub-metrics are one tap away. Daily progress bars (M3.7 polish round 2) show three discrete signals (Move, Hydration, Learning) but the top-level metric stays singular.

### 3.7 Mascot reflects state, never theater

**Research:** Trust erodes when feedback is performative. Tamagotchi-style fake-emotion mascots get ignored within 7-10 days because users learn the response is decoration. Mascots that respond to *real signals* (Apple's "Apple Pay confirmed" haptic, gameification with skin in the game) sustain engagement.

**In the code:** `CharacterStateService` recomputes mascot state from real signals (HRV, sleep, hydration ratio, streak status). Sad mascot only if there's a real miss. Achievement state is rare and earned (lift PR, weekly review hit all 7 targets). Variants: ninja_male, ninja_female (M3.7), variant-aware asset resolution.

---

## 4. Tech Stack — Chosen, Not Inherited

Every choice has a justification rooted in either the mission or the seven principles.

| Layer | Choice | Why |
|---|---|---|
| UI | SwiftUI (iOS + watchOS) | Single source of truth across phone + wrist. Native, low-overhead. |
| Persistence | SwiftData with `@Model` macro | Native, schema-versioned, integrates with CloudKit out of the box. No ORM dependency. |
| Sync | CloudKit private database | Apple-managed, end-to-end encrypted, no servers to run. |
| Cross-device | WatchConnectivity (M3.8) | Real-time phone↔watch handoff. CloudKit alone is eventually consistent (tens of seconds). |
| Health | HealthKit (`HKWorkoutSession` + `HKLiveWorkoutBuilder` on watch) | Apple's optimized power profile for live workouts. |
| Notifications | UserNotifications local only | No APNs, no servers. |
| Live Activities | ActivityKit | Lock-screen + Dynamic Island for fasting timer + workout sessions. |
| Widgets | WidgetKit (M6 deferred) | Future. |
| Secrets | Keychain via `KeychainService` | Anthropic API key lives only on-device. Never synced. Never in source. |
| AI | Anthropic API direct (Sonnet 4.6 default, Haiku for cheap calls, Opus for design-time) | No vendor lock-in beyond Anthropic. Direct calls, no proxy. Opt-in only — app works fully without an API key. |
| Charts | Swift Charts | Native. |
| PDF parsing | PDFKit + Vision OCR (M5 deferred) | Native. |
| Mascot art | Static PNG in Asset Catalog | No Rive runtime cost; mascots are 8 states × 2 variants × ~30KB each. Variant-aware via `CharacterState.assetName(for variant:)`. |

**Forbidden:** any third-party Swift package, any backend service, any analytics SDK, any ads, any subscription gateway. Adding any of these requires writing `.work/decisions/<id>-<topic>.md` with explicit user approval first.

---

## 5. Architecture Decisions

Recorded inline below in the order they bind the codebase.

### 5.1 SwiftData is authoritative for "is this happening?"

M3.6 introduced this as load-bearing. The bug that drove the decision: HealthKit's `HKWorkoutBuilder` could enter an error state mid-session ("Failed to update target construction state: Error(7)"), and the UI was observing HK state, so end-session buttons appeared to do nothing while SwiftData had already recorded completion. Users tapped repeatedly, gave up, abandoned the session.

**Resolution:** SwiftData writes are the source of truth. HealthKit is a best-effort secondary write. `SessionLifecycleService` runs HK writes through a detached task with bounded retry (3 attempts, exponential backoff). Failures persist a `HealthKitWriteFailure` row that the Diagnostics view surfaces. The user's UI never blocks on HK.

### 5.2 Permanent retention; no auto-delete code

Documented in `CLAUDE.md` from M3.7 onward. The TrendAnalyticsService and Coach v2 require a year-plus of context. Deletes only happen on explicit user action (4 sites: schedule swipe, schedule reset-to-default, JSON import wipe, Keychain key removal). Watch any future code that calls `modelContext.delete(model:)` from a service or BG task — it violates retention.

### 5.3 Schema versioning is incremental and additive

`SchemaV1` (M1) → `V2` (M3.5) → `V3` (M3.6) → `V4` (M3.7) → `V5` (M3.7 polish). All migrations are lightweight. All new fields have defaults. CloudKit forbids `@Attribute(.unique)` on cloud-backed entities, so logical uniqueness is enforced in service-layer upsert (`ActivityArchive` per day, `WeeklyProgram` per Monday).

### 5.4 Coach v2 routes through one context builder

Every Claude API call goes through `CoachService.gatherFullContext(profile:)` which composes:
- M3.6 today snapshot (`CoachContext`)
- `TrendAnalyticsService.summaryForCoach()` historical block (~500 tokens)
- User goals, equipment, restrictions, time-available

Locked system prompts in `CoachPrompts.swift` per generation mode (`dailyInsight`, `prescribeWorkout`, `suggestSchedule`, `weeklyProgram`, `dailyQuote`). No call bypasses this. Tuning happens in one file.

### 5.5 Cost guardrails on AI calls

- Daily insight: Sonnet 4.6, cached 24h. Manual refresh increments `refreshCount`.
- Workout prescription: Sonnet 4.6, only on training days (~5/wk).
- Schedule suggestions: skipped entirely when no patterns clear 0.5 confidence.
- Weekly programming: Sundays only.
- Daily quote: curated DB free always; Haiku optional, opt-in via `aiQuotesEnabled`.

Estimated user cost: $1.50-3/month average, $4/month heavy. Stays in personal-app territory.

### 5.6 Identity-anchored copy is not a bag of strings

`IdentityCopy` enum holds the canonical messages. Schedule editor uses "Your schedule. Your protocol." TrainView prescription header is "TODAY'S PRESCRIPTION FOR YOU" not "Generated workout." Lift completion line is `"\(volume) lb moved. That's the work."` Daily insight prompt enforces identity framing in the rules section.

### 5.7 Sessions resume; never orphan

M3.7 polish round 1 fix: leaving a Lift/Basketball/Swim/Custom session view mid-workout used to start a fresh session row on return. Now each view checks for an in-progress session on appear and resumes it. TrainingHubView surfaces an "In progress — tap to resume" section so the user can leave the workout, log water, and come back.

### 5.8 The mascot is a real signal, never theater

`CharacterStateService` derives state from data:
- `urgent`: next training block in <5 min
- `achievement`: lift PR or swim distance PR set today
- `proud`: streak hit milestone (7/30/100 days)
- `disappointed`: streak broke last 24h, OR Achilles pain ≥6 reported, OR <50% hydration past 18:00
- `tired`: sleep <6h or HRV down 20% vs 7-day avg
- `thirsty`: water ratio <0.6 of expected pace
- `fasting`: in fast window
- `neutral`: fallback

Travel/Sick day suppress urgent + disappointed; the mascot doesn't nag while you're offline.

### 5.9 Watch app exists; M3.8 brings parity

The watch target compiles today with shared models, services, and 5 watch views (Schedule, Hydration, Training, Lift, Basketball, Swim) plus 3 complications (CurrentBlock, FastCountdown, Mascot). What's missing — and is the M3.8 charter — is `HKWorkoutSession`, WatchConnectivity, variant-aware mascot rendering, and quick-log glances. Battery is a hard constraint: no polling, complications event-driven, anchored HK queries.

---

## 6. Milestone-by-Milestone State

### M1 — Scaffold + Schedule Engine + Watch Complication ✅ (`m1-complete`)

Bootstrapped Xcode project, SwiftData model container, schedule JSON seed, RootView tab structure, ScheduleService, watch complication scaffold. Foundation. Nothing user-facing beyond a working schedule view.

### M2 — Fasting + Hydration + Live Activities ✅ (`m2-complete`)

`FastingService` with phase-aware windows (weeks 1-2 training-day fast, weeks 3+ daily 16:8). `HydrationService` with day-type-aware targets (rest/lift/basketball/swim). FastingLiveActivity for lock-screen countdown. Hydration logging + electrolyte tracking. DailyLog as the cross-pillar canonical row.

### M3 — Training (Lift, Basketball, Swim) + Learning (Japanese, Guitar) ✅ (`m3-complete`)

LiftService with templates, sets, volume aggregation (12 tests). BasketballService with HR zone tracking (14 tests). SwimService with configurable pool length (8 tests). LearningService with 13 tests. Watch counterpart views for each. WorkoutLiveActivity for lock-screen during sessions. Action Button App Intent for one-press session start.

### M3.5 — Engagement Engine ✅ (`m3.5-complete`)

The pivot to behavioral-engineering principles. `PIVOT_SPEC.md` codified the 7 principles. Built:
- `StreakService` with freezes + travel + sick day grace
- `WorkoutEvent`, `CompletionHistory`, `FreezeApplication` ledgers
- `CharacterStateService` (8 states, precedence resolver, real-signal driven)
- `CharacterView` with breathing animation + alert pulse + reduce-motion honored
- `IdentityCopy` enum centralizing identity-framed strings
- `DailySummaryService` for the master metric
- `AdaptiveNotificationTiming` (learns log time over 14 days)
- Mascot → TodayView header + Watch CircularComplication
- Sick Day + Travel Mode + Mascot toggle in Settings

### M3.6 — Bug Fixes + Personalization Foundation + Coach Mode ✅ (`m3.6-complete`)

Triggered by Clay running M3.5 on iPhone 17 Pro simulator and surfacing critical end-session bugs. Built:
- `SessionLifecycleService` refactor (SwiftData authoritative; HK best-effort)
- `HealthKitWriteFailure` persistence
- Live Activity dismissal driven by SwiftData state
- Schedule editor (in-app CRUD on `ScheduleBlock`, isCustom preservation)
- `default_schedule_blank.json` for M4 onboarding
- Hydration granularity (CSV-configurable presets, custom oz/mL, beverage type with hydration coefficient)
- Hydration streak wired into StreakService domain
- Streak chips on TodayView
- Lift inline custom-exercise add
- Lift volume aggregator UI (3 concentric arcs + identity completion line)
- Achilles check-in toggle
- Coach Mode v1: daily insight via Sonnet, daily quote via curated DB or Haiku
- `ClaudeAPIClient` (Anthropic Messages API, Keychain-backed)
- `CoachInsightCard` on TodayView
- Diagnostics view (HK auth + recent failures + API key + token usage)

240 tests passing at close.

### M3.7 — Coach v2 + Long-Term Log + Multi-Mascot ✅ (`m3.7-complete`)

The brain expansion. Built:
- `ActivityArchive` daily rollup + `BGAppRefreshTask` scheduler
- `TrendAnalyticsService` (dailyAdherence, volumeProgression, patternsDetected, summaryForCoach)
- 6 detection rules (scheduleDrift, volumeDecline, hydrationCorrelation, sleepImpact, fastingConsistency, learningStreakDecay)
- 5 new @Models (ActivityArchive, DetectedPattern, PrescribedWorkout, ScheduleSuggestion, WeeklyProgram)
- `CoachPrompts.swift` (locked prompts per mode)
- `CoachContextV2` (today + historical + goals + equipment + minutes-available)
- `CoachService.prescribeTodaysWorkout` (with creative title in polish round 2)
- `CoachService.suggestScheduleOptimizations` (skips API on no patterns — cost guardrail)
- `CoachService.generateWeeklyProgrammingPass` (Sundays)
- `PrescribedWorkoutCard`, `ScheduleSuggestionInbox`, `WeeklyProgramCard` on TodayView
- Multi-mascot: rename Mascot* imagesets to NinjaMale_*, add NinjaFemale_* (8 states)
- `CharacterState.assetName(for variant:)` helper
- `MascotVariantPickerView` with preflight asset-presence check
- Goals capture in Settings (primaryGoal, secondaryGoals, equipmentAccess, weeklyTrainingTargetSessions, restrictions)
- Schedule template chooser (balanced, gym, language, fasting, blank)
- JSON export/import bumped to v2 covering all new entities + round-trip test

### M3.7 — Polish round 1 (post-test feedback) ✅

User played with M3.7 build, surfaced issues. Built:
- Mascot "default" trigger reason hidden
- Coach card API key entry removed (Settings-only)
- DEBUG dev-secrets bootstrap (gitignored `.dev-secrets/anthropic_key.txt` → Keychain on launch)
- Manual fast start/stop with cross-midnight handling
- Hydration entry edit + delete with streak recompute
- Coach card button layout fixed (icon-stacked-over-one-word; rationale not truncated)
- Lift/Swim/Basketball session resume (no orphan rows)
- TrainingHub "In progress — tap to resume" section
- Basketball water intake → HydrationService bridge

### M3.7 — Polish round 2 (UI flavor + custom activities) ✅

Second round of feedback drove flavor + flexibility:
- Creative workout titles ("Quadzilla", "Sanity Session", "Goblin Squats")
- Coach voice rewrite (3-beat structure: motivate → educate with body data → optimize)
- Custom activity types (`CustomActivityTemplate`, `CustomActivitySession`, full management UI)
- Streak card (labeled, flame glyph on active streaks, "3d Workout" framing)
- Apple-Watch-style daily progress bars (Move kcal, Hydration oz, Learning min)
- `sensoryFeedback(.increase)` on hydration log (research-backed micro-celebration)
- Empty state copy: identity framing instead of flat ("Open day. You write the plan.")

302 tests passing.

### M3.8 — Apple Watch Parity 🚧 (in progress)

Inserted before M4. Charter:
- Live workout tracking via `HKWorkoutSession` + `HKLiveWorkoutBuilder` for Lift/Basketball/Swim/Custom
- Phone↔watch real-time sync via `WCSession`
- Watch idle home: mascot + master metric + quick-log row
- Variant-aware mascot complication
- Hydration + fast-countdown complications
- Battery balance: no polling, event-driven complications, anchored HK queries

### M4 — Notifications + Onboarding + Implementation Intentions + Weekly Reflection + Ship 📋

Will deliver:
- ImplementationIntention model (anchor habits to triggers)
- WeeklyReflection model
- Full first-launch onboarding (variant pick, goals, equipment, schedule template)
- Notification authorization + adaptive scheduler
- App icon + final polish
- TestFlight / sideload deployment
- v1.0 tag

---

## 7. Quality Bar

Every milestone closes when ALL of these pass:

1. `xcodebuild -scheme PersonalOptimization build` clean, zero warnings.
2. `xcodebuild test -scheme PersonalOptimization` all green.
3. `xcodebuild -scheme PersonalOptimizationWatch build` clean.
4. Performance benchmarks per `PERFORMANCE.md` met.
5. New code has unit tests; coverage stays >70% on Models/Services.
6. Privacy manifest (`PrivacyInfo.xcprivacy`) updated when new HK/CloudKit/Network usage lands.
7. Git tag `m<id>-complete` pushed.

Test count over time:
- M3 close: ~190 tests
- M3.5 close: 216 tests
- M3.6 close: 240 tests
- M3.7 close: 285 tests
- M3.7 polish round 1: 296 tests
- M3.7 polish round 2: 302 tests
- M3.8 target: 320+ tests (live workout state machine + WC payload encoding)

---

## 8. Carryover Notes for M4

These thread through from M3.7 polish to whoever does M4:

- `CustomActivityService.seedDefaultsIfNeeded()` is built for first-launch onboarding. M4 just needs to call it from the variant selection step.
- `CoachContextV2.minutesAvailableToday` and `equipmentAccess` are wired into prompts but the user has no UI to fill `equipmentAccess` outside Settings. M4 onboarding is the natural place.
- The progress-bar denominator for "Move" hardcodes 500 kcal. M4 onboarding can ask the user for their real daily target and persist it on UserProfile.
- Notification adaptive scheduling (`AdaptiveNotificationTiming`) is in place but doesn't have a UI for granting/revoking authorization. M4 owns that flow.
- The character variant onboarding stub assumes the 8 NinjaFemale assets exist. The `MascotVariantPreflight` check halts cleanly when they don't.

---

## 9. Reference Files

- `CLAUDE.md` — operating contract for any agent touching the codebase
- `PROJECT_BRIEF.md` — original mission spec
- `ARCHITECTURE.md` — locked technical decisions
- `DATA_MODELS.md` — every `@Model` definition (locked)
- `MILESTONES.md` — phased build plan with DoD per milestone
- `PERFORMANCE.md` — performance benchmarks
- `TESTING.md` — test strategy
- `SECURITY.md` — privacy + data handling
- `PIVOT_SPEC.md` — the engagement-engine pivot rationale + the 7 principles' citations
- `M3.6_SPEC.md`, `M3.7_SPEC.md` — milestone-specific specs preserved as artifacts
- `.work/state.json` — current active milestone + status
- `.work/milestones/M*/close.md` — per-milestone close notes

---

## 10. The North Star

This app exists to put one human (then his wife) in command of their day with the lowest possible friction and the highest possible honesty. Every feature either reduces friction, raises honesty, or supports the seven principles. If a feature does none of those, it should not ship.

Single user. Two devices. Permanent history. Identity-anchored. Honest streaks. Mascot as signal. Coach as brain. Wrist as remote.

That's the whole thing.
