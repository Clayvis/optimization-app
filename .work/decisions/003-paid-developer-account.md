# 003 — Paid Apple Developer Program enrollment

Status: PENDING USER ACTION (Clay's enrollment).

## Context

PROJECT_BRIEF.md originally deferred paid Apple Developer Program enrollment to M7 (final shipping milestone). M3.7a pulls this decision forward: the 30-day Clay + wife test requires distribution onto a second device, and the only sensible way is TestFlight. Free personal team certs give 7-day signing → Clay would re-install on wife's phone every week, which breaks the test cleanly.

## Decision

Enroll in the paid Apple Developer Program now (was M7, now M3.7a).

## Cost

USD $99 / year. Recurs annually until cancelled.

## Benefits unlocked

- TestFlight internal + external testing distribution (90-day signed builds).
- HealthKit background delivery entitlement (planned for future milestones).
- Eventual App Store submission (M7 / v1.0 release).
- Push notifications via APNs if ever needed (currently local-only).

## Account ownership

Clay's personal Apple ID. Keep distribution certificates and provisioning profiles inside Xcode-managed signing; if a CSR is needed manually, store the private key in Keychain Access on Clay's primary Mac, do not export.

## Bundle / App Store Connect identifiers

- Bundle ID: `com.rawlins.PersonalOptimization` (already in entitlements + Info.plist).
- App name: "Optimization."
- Privacy nutrition label: "Data Not Collected", "No Tracking", "No Third-Party SDKs".

## Status (recorded 2026-05-08)

Claude Code halts at Task 13 (enrollment) until Clay completes it. Tasks 14-16 (App Store Connect record, TestFlight upload, wife device install) are also Clay actions and proceed sequentially after enrollment confirms.
