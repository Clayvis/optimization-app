# 021: InBody coach, active status and Move delivery

Date: 2026-09-26. User-authorized feature and behavior change.

- Add SchemaV12 InBodyScan to the shared Models source and AppSchema. Defaults/optionals support CloudKit. RIR and progression targets are additive Lift model fields.
- Use deterministic comparison and training rules; existing Coach context explains their output, alongside existing nutrition and recovery. No new model, API provider or dependency.
- Treat ECW thresholds and indirect forearm weighting as transparent planning heuristics. Missing hydration/effort data stays unknown. Whole-leg/arm scans do not identify calf/forearm growth.
- Use an explicit opt-in profile focus; no hardcoded baseline in the distributed application. The user's supplied records live in a git-excluded local import file.
- Replace production habit-reminder requests with the daily Live Activity. The user explicitly selected Lock Screen/Dynamic Island status. This supersedes notification-based practice reminders. Cancel pending habit requests when the app upgrades.
- Acknowledge HealthKit observer deliveries only after persistence, and remove the activity throttle that discarded the final update. A small three-metric query path replaces the full-day pipeline for frequent activity events.
- Completion pass (Claude, same day): the status text is composed from the user's own schedule and logged practice instead of fixed Japanese/music targets; content goes stale at the next schedule transition as well as after one hour or at midnight; Live Activity refreshes are serialized so concurrent launch/foreground/log/Health triggers cannot request two activities; only ended or dismissed activities release today's slot (pending and unknown future states still hold it), and a frozen ended card is dismissed before a replacement starts. The dashboard gains a deterministic coach-analysis verdict with ±0.5 lb / ±0.5 point stable bands, the focus toggle saves immediately, and the Coach context receives rounded figures plus the rule verdict.
- Preserve existing nutrition and companion work. No external dependencies or schema target drift.

Validation and physical-device checklist: docs/planning/INBODY_PROGRESS_COACH.md.
