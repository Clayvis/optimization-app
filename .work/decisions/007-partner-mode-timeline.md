# 007 — Partner mode timeline (deferred to v1.1)

Status: DEFERRED to v1.1. Recorded against HANDOFF_CLAUDE_CODE.md P3-2.

## Context

V1_OPPORTUNITIES.md item 1 is "Partner Mode" — Clay's wife joins the app, the two share progress, cheer each other, see complementary streaks. CloudKit private database doesn't share natively; the implementation cost is a CloudKit shared zone + UI for pairing, scoped sharing, and revocation.

UserProfile already has scaffolding fields: `partnerPairingCode`, `partnerPairingCodeExpiresAt`, `partnerRecordID`, `partnerOptedIntoSharing`. The actual CloudKit shared zone wiring is multi-week.

## Decision

Ship the P0/P1 hardening pass (record 005) plus the M4.1/M4.2 work to TestFlight with Clay solo. Validate the basics (no crashes, no CloudKit corruption, mascot reacts correctly, late-arriving HK samples retro-update, Persona inference produces useful proposals). Add Clay's wife as a second TestFlight tester WITHOUT partner mode — she gets her own private database, same UX. Two-user validation of the foundations comes first.

Partner mode goes into v1.1 once:

1. TestFlight v1.0 has been stable for at least 4 weeks with both users.
2. CloudKit shared zone permissions story has been spiked (`CKShare`, `CKShareMetadata` participant model).
3. Per-domain sharing UI is designed (Clay may want to share workout streak but not biomarkers).

## Counter-argument considered

Wife as second user is the primary retention lever. Shipping v1.0 without partner mode loses that lever.

Mitigation: she can still see Clay's app, react in person, share screenshots. The retention research case is about *seeing partner progress in your own app*, which we get cheaply via screenshots until v1.1 lands the real implementation.

## Pre-conditions for revisiting (before v1.1 plan)

- 30-day TestFlight stability metrics for v1.0 (Clay + wife).
- Confirmed mascot variant system is the right framing for partner UI (his ninja, her ninja, side-by-side card).
- CloudKit zone-sharing spike confirmed feasible on free Apple Developer account.


## Addendum 2026-06-12: weekly challenge built against the seam

Clay requested an Apple-Fitness-style weekly challenge with his wife and
confirmed the paid developer account is enrolled. Scope agreed: build the
full challenge feature NOW against the existing `PartnerSharedZone` seam
(scoring, standing logic, TodayView card), keep the live CloudKit shared
zone deferred per this decision. Scoring is protocol points (one point per
closed domain per day, master-metric rules), not move calories, to avoid
duplicating Apple's own Activity competitions.

The card is hidden until `partnerRecordID` is set and renders "waiting"
copy until a same-week partner snapshot syncs, so production behavior is
unchanged until the CloudKit zone PR lands. `PartnerSharedRecord` gained
optional `challengeWeekStart` / `challengeWeekPoints` fields (additive,
old payloads still decode). Note: this intentionally adds a competitive
frame alongside the cooperative joint-streak card; the joint streak stays
the primary partner surface.
