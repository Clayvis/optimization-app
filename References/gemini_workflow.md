# Gemini Web Workflow: Generate 8 Character PNGs

Step-by-step process to create the 8 mascot PNG assets for M6.5. Uses Gemini web interface (gemini.google.com). Free.

Total time: 30-90 minutes including iteration. Cost: $0.

## Prerequisites

1. Google account.
2. Browser, ideally Chrome or Safari.
3. Read `character_brief.md` first. Especially the aesthetic and the 8 state descriptions.
4. About 1 hour of focused time.
5. Wife in the room (or available via text) for approval feedback.

## Output

8 transparent PNG files at 1024x1024:
- MascotNeutral.png
- MascotThirsty.png
- MascotFasting.png
- MascotUrgent.png
- MascotProud.png
- MascotDisappointed.png
- MascotTired.png
- MascotAchievement.png

## Step 1: Open Gemini

Go to https://gemini.google.com.

Make sure you have access to image generation. As of mid-2025, Gemini 2.5 / Nano Banana / "Gemini 3 Pro Image" tiers all support image generation. If you only have access to Gemini Advanced subscription tier, that's fine; the free tier may have generation limits.

## Step 2: Generate the Master Character (Neutral State)

Paste this prompt:

```
Generate a 1024x1024 PNG with transparent background.

Subject: A cute kawaii Japanese ninja chibi mascot character.

Style:
- Vector illustration style, clean thick outlines.
- Chibi proportions: head is 1.5x the width of the body, large round head, small body, short limbs.
- Front-facing or 3/4 view.
- Premium mobile-game mascot quality. Think Line Friends or Naruto chibi merchandise.

Character details:
- Charcoal-black ninja gi with a bright red headband.
- Cream/peach skin tone (or shiba inu fur tone if you choose dog variant).
- Determined but friendly expression.
- Standing in a calm neutral pose, looking forward.
- Slight friendly smile.
- Hands at sides or one hand near a small ninja weapon at the hip.
- Androgynous, no specific gender presentation.

Background: fully transparent. No background elements. No text. No speech bubbles.

Composition: character centered, occupies about 80% of vertical space, 10% margin top and bottom.

Avoid: weapons drawn in attack pose, blood, oversized kawaii eyes, copyrighted character resemblance (no Naruto, no Greninja).

Output: PNG, 1024x1024, transparent background.
```

Generate. If the output is wrong (no transparency, wrong style, off-model), iterate. Common fixes:
- "Make the background fully transparent, not white."
- "Make the character cuter, more chibi proportions."
- "Add a red headband."
- "Less anime, more vector mascot style."

## Step 3: Wife Approval Gate

Show your wife. Get explicit yes before proceeding. If no, iterate Step 2 with her feedback. Common requests:
- Different animal (cat instead of human, fox instead of dog).
- Different accent color.
- More feminine vs more rugged feel.
- Specific mood (happier, more serious, more playful).

Do not proceed to Step 4 until wife says yes. The next 7 generations will reference this character.

## Step 4: Save the Master

Right-click the approved image, save as `MascotNeutral.png`.

Verify:
- Open in Preview.app on Mac. Check that background is transparent.
- File size should be 200KB-2MB. If smaller, resolution is too low.
- Use "Get Info" to confirm dimensions are 1024x1024 (or close, e.g. 1024x1080).

If background is not transparent, regenerate with stronger emphasis: "background must be fully transparent, alpha channel, no white pixels, no off-white."

## Step 5: Generate the Other 7 States

For each remaining state, upload `MascotNeutral.png` as a reference image, then prompt:

### Thirsty

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Tongue out slightly, fanning self with one hand, looking longingly at a small water cup or canteen held in the other hand. Mild distress, not catastrophic. Eyes show want.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotThirsty.png`.

### Fasting

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Sitting in lotus meditation pose, eyes peacefully closed, slight calm smile. Subtle aura or soft glow effect around the body suggesting inner strength. Hands resting on knees in meditation mudra.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotFasting.png`.

### Urgent

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Eyes wide with mild panic, hands raised in front. Pointing or gesturing toward an unseen schedule with one hand. "Hurry up" energy. Slight motion lines suggesting movement. Mouth open in a small "oh" shape.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotUrgent.png`.

### Proud

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Arms up in victory pose, big bright smile, eyes closed in joy. Small sparkle effects around the character. Holding a small flag or trophy in one raised hand.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotProud.png`.

### Disappointed

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Slumped shoulders, head slightly down, sad eyes, small pout. Holding a broken streak-fire icon (a fire icon split in half) or a torn calendar page. Visibly let down but not crying.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotDisappointed.png`.

### Tired

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Yawning with one hand covering mouth, eyes droopy and half-closed, holding a small pillow tucked under the other arm or a steaming coffee cup. Low energy, sleepy posture, slight slouch.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotTired.png`.

### Achievement

```
Same character as the reference image. Identical outfit, colors, proportions.

Change the pose and expression to: Most energetic state. Mid-air victory leap or backflip pose, beaming bright smile, eyes squinted with joy. Full sparkle and motion-line effects radiating outward. Both arms raised, fists pumped. Genuine PR-celebration energy.

Keep: same character, same outfit, transparent background, 1024x1024.

Output: PNG, transparent.
```

Save as `MascotAchievement.png`.

## Step 6: Verify Consistency

Open all 8 PNGs side by side in Preview.app or any image viewer.

Checklist:
- [ ] Same outfit across all 8 (charcoal gi, red headband or whatever you picked).
- [ ] Same skin/fur tone across all 8.
- [ ] Same proportions (head-to-body ratio) across all 8.
- [ ] Same eye shape and color across all 8.
- [ ] All have fully transparent backgrounds.
- [ ] All are 1024x1024 (or close).
- [ ] Each state is visually distinct from neutral.
- [ ] None look broken, off-model, or have weird anatomy.

If any fails, regenerate that one state with the master neutral as reference, emphasizing what's wrong.

## Step 7: Drop into Xcode Asset Catalog

Once all 8 are approved:

1. Open `PersonalOptimization.xcodeproj` in Xcode.
2. Navigate to `PersonalOptimization/Assets.xcassets/Mascot/`.
3. For each PNG, create a new Image Set:
   - Right-click → New Image Set.
   - Name: `MascotNeutral`, `MascotThirsty`, etc. (must match the names in `CharacterState.assetName` in DATA_MODELS.md).
4. Drag the PNG into the 1x slot.
5. (Optional) Generate 2x and 3x versions if you have Pixelmator/Photoshop to upscale. Otherwise leave just 1x.
6. Build the app and verify mascot renders.

## Step 8: Final Wife Approval

Show her the app running on simulator with all 8 states cycled through. Have her sign off before merging M6.5 PR.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Gemini generates white background instead of transparent | Use Preview.app → Tools → Magic Wand → select white → delete. Or regenerate with stronger transparency emphasis. |
| Character drifts off-model across states | Always upload MascotNeutral.png as reference for every subsequent state. Never generate from text alone. |
| State doesn't read correctly | Show the PNG to a friend without context. If they can't guess the emotion, regenerate with stronger emotional cues. |
| Image quality is low (pixelated, blurry) | Specify "high resolution, sharp lines, vector quality" in prompt. Some Gemini tiers have higher quality. |
| Gemini refuses to generate | Reword prompt to remove ambiguous content. Avoid "ninja attack" wording. Use "ninja chibi" instead. |
| Inconsistent skin tone across states | Add to prompt: "Cream-peach skin tone exactly matching the reference image, no variation." |
| Background has weird artifacts | Use a transparency cleanup tool (free: remove.bg or Preview Magic Wand). |

## If Gemini Won't Generate Quality PNGs

Fallback options:

1. **Vecteezy + Adobe Illustrator**: Buy a single chibi ninja from Vecteezy ($1-3 per asset, royalty-free), open in Illustrator, recolor and re-pose for 8 states. Better baseline quality, costs $25-50 total.

2. **Hire on Fiverr**: Search "chibi mascot illustration" on Fiverr. $30-100 total for 8 states with revisions. Send them this brief and the 8 state descriptions.

3. **AI Studio (Google)**: aistudio.google.com gives access to higher-quality image models with more control. Free tier exists.

4. **Midjourney**: $10/month, generally higher quality than Gemini for character art. Use `--ar 1:1 --no background` flags.

5. **DALL-E 3 via ChatGPT**: $20/month ChatGPT Plus, lower character consistency than Gemini but workable.

## Time Investment

Realistic time:

- Step 2 (master character generation + iteration): 15-30 min
- Step 3 (wife approval): 5-15 min
- Steps 5-6 (7 state generations): 20-40 min
- Step 7 (Xcode integration): 10-15 min
- Step 8 (final approval): 5-10 min

Total: 55-110 minutes.

## Future Upgrade Path

When ready to upgrade from static PNGs to Rive animations (v1.5+):

1. Find a Rive animator (Behance, Twitter, Fiverr, https://uianimation.com).
2. Send them: all 8 PNGs, this workflow doc, character_brief.md, the CharacterState spec from DATA_MODELS.md.
3. Budget: $150-300 for rigging the existing art into a state-machine `.riv` file.
4. Lead time: 1-2 weeks.
5. In code: replace `Image(state.assetName)` in `CharacterView.swift` with Rive renderer. The rest of the architecture stays identical.

This approach (PNG first, Rive later) is the cheapest, fastest, lowest-risk path. The mascot ships in v1.0, gets richer in v1.5 if desired.
