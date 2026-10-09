# Life Off Desk — brand and interface guide

## Direction

Product promise: **Your personal world, stored on your phone.**

Positioning: **There is more to life than your screen.**

Calm, curious and inviting. Encourage a small outing without guilt or competition. The map is the primary visual. The cat is a companion, with sparse appearances in empty states and recaps.

## Color tokens

| Token | Hex | Use |
| --- | --- | --- |
| canvas | #F8F6EF | Warm ivory canvas and unexplored fog |
| ink | #283A31 | Main text, strong icons |
| primary | #46785B | Primary buttons and selected controls |
| secondaryInk | #69776D | Secondary text on ivory |
| surface | #FFFFFF | Cards/sheets where separation is necessary |
| border | #D9DED4 | Subtle separators; proposed extension |
| danger | #A13D36 | Destructive labels with explicit text; proposed extension |

The first four colors reflect the approved direction. Border/danger are proposed functional additions. Validate actual composited contrast, including disabled controls, photos and map labels. Do not communicate status through color alone. Ivory labels on primary green and both text colors on ivory should be checked in the implementation.

## Native iPhone presentation

- System typography / SF family; use semantic Dynamic Type styles rather than rasterized text.
- Suggested base: 17-point body, 15-point secondary, 22-point section title; scale with accessibility settings.
- Spacing tokens: 4, 8, 12, 16, 24, 32 points. Use a 16-point content inset as a starting value.
- Rounded cards/buttons: 18–24 points. Minimum interactive target: 44 × 44 points.
- Respect safe areas, keyboard, classic iPhone 12 notch and home indicator. The reference board is visual guidance rather than exact pixel coordinates.
- Keep bottom controls reachable. Founder decision 2026-10-09: a five-page intro (dotted routes drawing themselves, one bold line, one quiet line) shows once on first launch, is skippable on every page and can be reopened from Settings. It never gates the map behind an account, permission or download. Use sheets for planner/results; use a recap view after Finish.
- Respect Reduce Motion and VoiceOver; accessible labels describe the action and state. Provide text equivalents for meaningful map status.
- Start with one polished light theme; postpone a complete dark theme. Use SF Symbols for interface actions and keep icon sizing consistent.

## Core copy

| Moment | Proposed copy |
| --- | --- |
| Initial map | “A little walk can open up your world.” |
| Main action | “Start walking” |
| Secondary action | “Help me choose somewhere” |
| First GPS fix pending | “Finding your location…” |
| Paused | “Walk paused” / “Resume walking” |
| Planner placeholder | “A quiet place for a 30-minute break” |
| No local matches | “No matching places in this area. Try a wider area or another activity.” |
| Model failure | “I couldn't understand that request. Try again or choose filters.” |
| Recap | “You made room for a little adventure.” |

Do not promise venues are open, paths are safe, or exact travel time without supporting data. Keep technical runtime details in build evidence rather than the ordinary user flow.

## Canonical mascot

Male cream-and-chocolate bicolor cat based on the founder's personal cat: white nose blaze/muzzle/paws, dark ears and tail, green jacket and olive backpack. Name undecided. Preserve markings and the established drawn style.

Use `assets/mascot/life-off-desk-cat-stickers-male.png` as the canonical sheet. Its 12 poses are arranged in 3 columns × 4 rows: welcome/walking/thinking; planning/discovering/fog peek; taking photos/saving memories/café break; resting/celebrating/encouragement. It has transparency and a sticker outline. On 2026-10-09 it was cut mechanically (by its own alpha outlines, no redrawing) into 12 imagesets in `LifeOffDesk/Resources/Assets.xcassets` (`mascot-welcome`, `-walking`, `-thinking`, `-planning`, `-discovering`, `-fog-peek`, `-taking-photos`, `-saving-memories`, `-cafe-break`, `-resting`, `-celebrating`, `-encouragement`). The concept portrait is secondary; the app icon is a square crop of it (no redraw). Do not regenerate a different cat when implementing.

Prefer small welcome/fog-peek/celebration accents. Avoid a permanent large mascot over the map, gender stereotypes, invented accessories or excessive animation. Personal photo memories and pre-drawn mascot stickers are separate asset types.

## Reference status

`design/life-off-desk-ui-reference.png` is the latest static Open/Walk/Keep board. Its geometry, text and statistics are illustrative. The existing Figma journey has not received the map-first revision; `design/figma-map-first-update.js` is unapplied and runtime-untested. Feature behavior in MVP-FEATURES.md takes precedence over decorative reference details.

## Taglish update

Planner accepts natural Taglish and returns short Taglish guidance grounded in the catalog. Use familiar English action labels where clearer. Suggested prompt: “May 30 minutes ako, gusto ko ng quiet na park.” Suggested empty state: “Walang matching place sa area na ito. Try natin ibang activity?” Test clarity with the founder; Taglish model quality is not assumed.

## In-app branding (implemented 2026-10-09)

- **App icon:** square crop of the concept portrait (waving cat with map), opaque 1024 px, iOS derives other sizes. **Launch screen:** BrandCanvas ivory with the welcome pose. **Accent colour:** primary #46785B.
- **Mascot placements (small, decorative, VoiceOver-hidden; text carries meaning):** one pose per intro page (welcome, fog peek, thinking, encouragement, taking photos) and the wordmark on page 1; recap header (celebrating); planner idle (thinking); empty Adventures (walking); no search matches (discovering); empty photo spots (taking photos); Me avatar and Settings About (welcome); shareable card badge (welcome).
- Intro copy updated to adventures on foot or riding, offline Taglish AI and on-device privacy.
