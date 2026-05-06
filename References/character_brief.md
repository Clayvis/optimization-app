# Character Aesthetic Brief

Use this when generating PNGs via Gemini web (see `gemini_workflow.md`). Hand the entire document to a freelance illustrator if you ever decide to commission a custom version.

## Overall Aesthetic

- **Style**: Cute (kawaii) meets cool. Wife-approval factor matters. Should feel like a Japanese mobile game would ship as a premium mascot.
- **Theme**: Japanese ninja or shinobi. Open variants: ninja shiba inu, ninja cat, chibi human ninja, ninja kitsune (fox spirit).
- **Color palette**: Charcoal/black ninja outfit, cream or peach skin/fur, one bright accent color (red headband, teal eyes, or orange scarf).
- **Line work**: Clean vector outlines, slightly thick. Not pixel-art. Vector chibi proportions: large head 1.5x body width, small body, short limbs.
- **Personality**: Determined but cute. Capable but expressive. Naruto chibi-side-character energy. Line Friends quality.

## Inspiration References

For visual calibration:

- Naruto chibi merchandise (proportions and ninja styling)
- Line Friends Brown the bear (premium kawaii bar)
- Duolingo Duo the owl (emotional expressiveness range, NOT visual style)
- Pokémon Greninja (ninja aesthetic for Western audience)

## Technical Requirements (PNG path)

- **Format**: 8 PNG files, one per state.
- **Resolution**: 1024x1024 base, transparent background.
- **Aspect ratio**: square (1:1), full character visible.
- **Style consistency**: same character across all 8 states. Same outfit, colors, proportions.
- **Pose constraint**: front-facing or 3/4 view, never side or back. Watch complication crops to face.
- **Composition**: character centered, ~80% of vertical space. 10% margin top/bottom.

## 8 Required States (PNG version)

Each state must convey its emotion clearly enough that an outside observer can guess it without context. Test: show a friend the PNG in isolation, ask "what is this character feeling?" Their answer should match.

| State | Asset Name | Visual Direction |
|-------|------------|------------------|
| neutral | MascotNeutral | Standing, looking forward, calm pose, slight smile, neutral idle. Default state. |
| thirsty | MascotThirsty | Tongue out slightly, fanning self with one hand, looking longingly at a small water cup. Mild distress, not catastrophic. |
| fasting | MascotFasting | Meditating in lotus position, eyes closed peacefully, slight smile, subtle aura/glow effect. Inner strength. Combines fasting_calm and fasting_strong from earlier 14-state spec; intensity is read from text UI, not character. |
| urgent | MascotUrgent | Eyes wide, slight panic, gesturing toward an unseen schedule, "hurry up" energy. Hands raised. |
| proud | MascotProud | Arms up in victory pose, sparkles around, big smile, holding a small trophy or flag. |
| disappointed | MascotDisappointed | Slumped shoulders, sad eyes, pout, holding a broken streak fire icon or a torn calendar page. |
| tired | MascotTired | Yawning, eyes droopy, holding a small pillow or coffee. Low energy, sleepy. |
| achievement | MascotAchievement | Most energetic state. Backflip mid-air or victory leap, full sparkle effect, beaming smile, motion lines. PR celebration. |

## Style Consistency Rules

When generating with Gemini, lock the character via reference image upload after the first generation. Each subsequent state should reference the master image to maintain consistency.

Specific traits to lock:
- Outfit: charcoal/black ninja gi with one accent color
- Eyes: same shape and color across all states
- Skin/fur tone: identical across all states
- Proportions: same head-to-body ratio
- Accessories: headband, scarf, or weapon should be consistent (or absent in all)

## What to Avoid

- No graphic violence even though it's a ninja. No weapons drawn in attack pose, no blood, no shuriken in flight toward someone.
- No gendered presentation (character should read as androgynous so it doesn't feel limiting).
- No copyrighted character resemblance (not Naruto, not Greninja, not Master Splinter).
- No text or dialogue bubbles in the image. App UI handles text.
- No background art. Transparent only.
- No outline so thick it looks like a sticker.
- No cute-overload (oversized eyes, exaggerated kawaii signifiers). Aim for "cute but cool."

## Wife-Approval Checklist

Before saving the final 8 PNGs:

- [ ] Wife sees the character at first glance and reacts positively.
- [ ] All 8 states are visibly the same character.
- [ ] No state looks awkward, off-model, or has weird anatomy.
- [ ] Backgrounds are fully transparent (no white halo, no gray).
- [ ] Each state reads correctly without context (test with one friend).
- [ ] Achievement state is genuinely energetic and celebratory.
- [ ] Disappointed state is sad but not depressing.

## Future Path to Rive

These 8 PNGs serve v1.0. v1.5+ option: hire a Rive animator to take the 8 stills as reference and rig them into a single `.riv` file with state machine. The character design work is done; only the rigging is paid for. Estimated cost: $150-300.

If/when you commission Rive rigging, send the animator:
1. All 8 final PNGs.
2. This brief.
3. The 8-state catalog from `DATA_MODELS.md` (CharacterState enum and precedence rules).

The Swift code in `Modules/Character/CharacterView.swift` swaps from `Image(state.assetName)` to a Rive renderer; the rest of the architecture stays identical.
