# Decision 018: protocol streak adopts the 4-domain tally definition

Date: 2026-06-11
Status: implemented
Source: AUDIT_2026-06-10.md (High finding #2 theme; Open Question "streak vs tally")

## Context

Two definitions of "a complete day" coexisted and were both presented to the
user as "the master metric":

- `StreakService` protocolAdherence streak = fasting AND hydration only, with a
  stale `// for now` comment deferring to a DailySummaryService that had since
  landed.
- `DailySummaryService.todayProtocol` (and `ProtocolGoalSnapshot`) scored four
  scheduled-aware domains: fasting, hydration, learning, and workout on
  training weekdays.

Consequence: the headline streak could advance while the day's tally read 2/4.
The two numbers sat next to each other on TodayView.

## Decision

The streak adopts the stricter 4-domain definition. `StreakService`'s
`protocolAdherence` case now requires fasting AND hydration AND learning AND
(workout on scheduled training weekdays, auto-rest days bridge), via the shared
`ProtocolRules`. Grace (travel/sick/freeze) still completes a day as before.

Chose stricter over keeping fasting+hydration because:
- The tally is the more visible, more recently designed surface; aligning the
  streak to it removes the contradiction the user actually sees.
- "Protocol adherence" honestly means the whole protocol, not two of four parts.
- All domain rules now live in one place (`ProtocolRules`), so the streak,
  tally, snapshot, trends, and registries cannot drift again.

## Consequence for existing data

`StreakCounter` rows recompute from `DailyLog` history on next launch
(`recompute` walks 730 days), so the change is retroactive: a historical day
that logged only fasting+hydration no longer counts toward the protocol streak.
Existing protocol-streak numbers may DROP for users whose past days were not
4-domain-complete. This is correct (the prior number over-counted) but visible.
Per-domain streaks (workout/hydration/learning) are unchanged.

## Alternatives rejected

- Keep fasting+hydration and relabel the tally: weaker, keeps "protocol" lying
  about scope, and the tally is the better-designed surface.
- Add a 5th "everything" streak: more numbers, more confusion, opposite of the
  build sheet's "one master metric" principle.
