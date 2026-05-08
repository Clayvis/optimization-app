# 002 — Additive mascot variants (no rename)

Status: ACCEPTED. Implemented in M3.7a / M6.5 line.

## Context

Original M3.7 plan called for renaming `MascotNeutral.imageset` → `NinjaMale_Neutral.imageset` (× 8 states) so that variant naming would be consistent. This is high blast radius: every consumer of the mascot images would need updating, and the mascot is core UX. Rename ships nothing the user can perceive.

## Decision

Additive only. Existing male assets are stored under the new namespace from the start; new variants are added alongside without touching the existing ones.

Asset namespace convention (final):
- `NinjaMale_<State>.imageset` for ninja_male (the default)
- `NinjaFemale_<State>.imageset` for ninja_female

`CharacterState.assetName(for variant: String)` resolves the asset name based on `UserProfile.mascotVariant`. Default variant is `"ninja_male"`; new users pick during onboarding.

## Pre-flight fallback

If `userProfile.mascotVariant == "ninja_female"` and the female asset is missing or empty (e.g. shipped before art generation), the resolver falls back to `ninja_male` and logs a warning. This decouples variant infrastructure shipping from art delivery.

## Status note (recorded 2026-05-08)

Both `NinjaMale_*` and `NinjaFemale_*` imagesets exist in `PersonalOptimization/Assets.xcassets/Mascot/`. `MascotVariantPickerView` lets the user switch between them in Settings. No legacy `MascotNeutral.imageset`-style names remain in code paths.
