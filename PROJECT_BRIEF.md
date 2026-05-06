# PROJECT_BRIEF.md

Scope, success criteria, constraints. Read at bootstrap. Re-read at every milestone transition.

## Problem

Daily optimization across schoolwork, training (lift, basketball, swim), language learning (Japanese), guitar practice, intermittent fasting, hydration, and biomarker health requires manual scheduling, logging, and cross-referencing across 8+ apps. No existing app combines schedule + execution + biometrics + emotional reinforcement in one watch-first surface.

## Goal

Single iOS + watchOS app that:

1. Renders today's schedule on a watch complication, glanceable in <1 second.
2. Logs activity completion and biometric outcomes per pillar.
3. Surfaces patterns across data sources a user would otherwise miss (glucose drift correlated with sleep, Achilles pain trending up post-basketball).
4. Auto-generates Sunday weekly review.
5. Parses lab PDFs and tracks ~80 biomarkers with longevity-tight reference ranges, computes biological age (Levine PhenoAge 2018).
6. Provides emotional reinforcement via state-driven mascot character (Duolingo-style retention loop).

## Non-Goals

1. Multi-user or accounts.
2. Server backend.
3. Replacing Pimsleur, native Apple Workouts, or Apple Health. The app integrates with these.
4. Replacing medical providers. Biomarker analysis is informational.
5. Cross-platform. iOS + watchOS only.

## Success Criteria for v1.0

| Metric | Target |
|--------|--------|
| Daily app open rate | 7/7 |
| Schedule blocks logged | 80% adherence |
| Hydration daily target | 5/7 days/week |
| Fast adherence | 6/7 days/week |
| Training sessions logged | 4-5/week |
| Japanese streak maintained | yes |
| Guitar streak maintained | yes |
| Lab PDF parse end-to-end | <30 seconds on DOD format |
| PhenoAge computes when 9 markers present | yes |
| Weekly review auto-generates | every Sunday |
| Watch complication current block render | <50ms |
| Watch battery impact | <5%/12hr normal use |

## Constraints

1. Native Swift only. SwiftUI for both targets. ZERO third-party Swift packages.
2. Anthropic API key user-supplied, stored in Keychain. AI calls opt-in only.
3. CloudKit private database for sync. No custom backend.
4. Apple Watch Ultra is the primary surface.
5. JSON export and import for backup from M1.
6. Privacy manifest from day one (iOS 17+ requirement).

## Bootstrap Validation Questions

The agent confirms these answers before creating Xcode project:

1. Apple Developer Team ID for `<YOUR-TEAM>` placeholder replacement (e.g., "com.clayrawlins").
2. Paid Apple Developer Program account or free personal team?
3. Test devices: iPhone model, watchOS version, Apple Watch Ultra hardware?

## Reference Logic

The biomarker module logic is prototyped and validated in `References/biomarker-tracker.html`:

- ~80 biomarker definitions across 11 categories with optimal and normal reference ranges.
- ~170 lab-name-to-key alias mappings.
- DOD MTF format auto-detection in PDF parser.
- Generic format fallback for Quest, LabCorp.
- PhenoAge (Levine 2018) calculation.
- 12 clinical pattern detection rules.
- Anthropic API integration for live analysis and PDF extraction.

The web prototype's parser was validated against `References/sample_lab_dod.json` (October 2025 DOD panel) at 25 of 25 tracked biomarkers extracted correctly.

## Schedule Seed Data

`References/default_schedule.json` contains 39 blocks across the weekly grid:
- Mon-Fri: 6-8 blocks each
- Sat, Sun: 2 blocks each (Japanese morning, Guitar evening)

Seed at first launch. Allow per-day overrides via Settings without breaking the template.

## Phased Rollout

| ID | Module | Effort | Daily-usable after |
|----|--------|--------|--------------------|
| M1 | Scaffold + Schedule + Watch Complication | 8-12h | yes |
| M2 | Fasting + Hydration + Live Activities | 12-16h | yes |
| M3 | Training + Learning + Pomodoro | 16-20h | yes |
| M4 | Coursework + Admin | 8-10h | yes |
| M5 | Biomarkers + Lab Parser | 20-28h | yes |
| M6 | Analytics + Weekly Review + Widgets | 10-14h | yes |
| M6.5 | Mascot System (PNG-based) | 8-12h | yes |
| M7 | Notifications + Edge Cases + Onboarding | 14-18h | yes (v1.0) |

Total: 96-130 hours of agent execution. Daily usable from M1 onward.
