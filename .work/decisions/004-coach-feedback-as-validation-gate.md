# 004 — Coach feedback as the M3.7b validation gate

Status: ACCEPTED. Threshold rules locked.

## Context

M3.7 originally proposed building prescriptive Coach output (workout prescription, schedule optimization suggestions, weekly programming pass) on the assumption that the M3.6 daily insight is being read and acted upon. The assumption is unvalidated. Building prescriptive output before validating commentary risks shipping more features the user ignores.

## Decision

Defer all M3.7b prescriptive features until 30-day usage data passes a hard threshold. Capture the data via the lightest possible instrumentation: a `userInteraction` enum on `CoachInsight`, exposed as thumbs-up / thumbs-down buttons on the Today coach card, plus an auto-mark "viewed" when the card sits on screen >1.5s.

## userInteraction states

- `ignored` (default — card never confirmed visible)
- `viewed` (≥1.5s on screen, no other action)
- `dismissed` (user closed the detail sheet or swiped away)
- `acted_on` (reserved; not currently surfaced — no UI button — placeholder for future M3.7b/c work that records "user did the thing the insight suggested")
- `marked_helpful` (thumbs-up tapped)
- `marked_unhelpful` (thumbs-down tapped)

Stronger signals overwrite weaker ones in priority order: `marked_*` > `acted_on` > `dismissed` > `viewed` > `ignored`. The auto-mark "viewed" path checks `currentValue == .ignored` before writing, so it never demotes a real signal.

## Validation thresholds (the gate)

At day 30, query all `CoachInsight` rows with `generatedAt >= installDate + 7` (skip the first week as user-onboarding noise):

- **Build M3.7b** if BOTH:
  - Interaction rate ≥ 40% (any of `viewed | dismissed | marked_helpful | marked_unhelpful` divided by total insights generated).
  - Helpful : unhelpful ratio ≥ 3 : 1 among `marked_*` rows.
- **Do NOT build M3.7b otherwise.** Design M3.7c, a different reinforcement mechanism, instead. Most likely candidates:
  - Streak-recovery prompt
  - Weekend reflection nudge
  - Goal-progress dashboard
  - Whichever the feedback emails surface as the missing thing.

## Why these thresholds

- 40% interaction means "the card is at least breaking through the user's ignore reflex." Below that, the underlying feature isn't earning attention regardless of what's in the card; rebuilding the card is wasted work.
- 3:1 helpful ratio means "when users do react, they react positively." Below that, the content quality is the problem, not the form factor; M3.7b prescriptive output would inherit the same content-quality issue.

## What gets recorded

`.work/reviews/m3.7a-day30-review.md` containing:
- Interaction rate per user (Clay, wife)
- Helpful : unhelpful ratio per user
- Top quotes from feedback emails
- Cost per user-month
- Crash + hang counts
- Decision: M3.7b or M3.7c
