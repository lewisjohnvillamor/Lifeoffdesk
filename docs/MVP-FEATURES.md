# Life Off Desk — MVP feature list

Decision version: 2026-10-09, Asia/Manila. This is a build specification, not a claim that features have been implemented.

## Product and first user

Help a desk-bound person in Luzon take a short outing, find somewhere worthwhile, and grow a private map through actual movement. The initial customer hypothesis is workers, developers and freelancers who want low-effort 15–60 minute breaks. Demand is unvalidated. The first test user is the founder on an iPhone 12 Pro Max.

The opening screen is a warm ivory map with **Start walking** as its main action and **Help me choose somewhere** as a secondary action. Chat is optional for the user but **required in the MVP**. Both walking and genuine on-device AI suggestions are P0 because the event theme is Local AI.

## P0 — required for a complete demo

| ID | Feature | Minimum behavior | Acceptance evidence |
| --- | --- | --- | --- |
| P0-01 | Map-first entry | Open the personal map immediately; no account or download gate (a one-time skippable intro is allowed, founder decision 2026-10-09) | Fresh install opens the map; clear Start walking and suggestion actions |
| P0-02 | Explicit walk session | Start, pause, resume, finish; ask for location when needed | Real phone session changes state correctly; paused movement adds no trail |
| P0-03 | Real GPS tracking | Accept reasonable fixes, reject stale/inaccurate jumps, break gaps | Short outdoor walk follows actual movement; denied permission shows a useful next step |
| P0-04 | Fog of war | Reveal only a narrow traveled corridor; keep unexplored detail covered | New movement reveals local geometry; stationary GPS drift does not reveal a large area |
| P0-05 | Local persistence | Save trail, cumulative exploration and completed recaps | Relaunch preserves exploration; interrupted session offers recovery without silently resuming tracking |
| P0-06 | On-device AI chat | Turn a short Taglish request into validated outing preferences; return concise Taglish guidance | iPhone model inference succeeds with airplane mode on and Wi-Fi off; Mac disconnected |
| P0-07 | Grounded local suggestions | Filter/rank a bundled catalog; show up to three actual places | Every result maps to a source record; unsupported price/hours/quietness are not invented |
| P0-08 | Choose a destination | Selected suggestion appears as a destination marker and Start walking action | Label straight-line distance explicitly; no fabricated walking route or ETA |
| P0-09 | Honest recap | Show tracked distance, active duration and a small route preview | Values come from accepted samples; save/reopen completed walk |
| P0-10 | Offline starter area | Bundle a small verified place catalog and simple vector context for one walkable area | AI, catalog, reveal and recap work without a network; show coverage limits outside the area |
| P0-11 | Essential errors/privacy | Handle permissions, no GPS, no matches, model missing/loading/failure; local erase control | Input survives AI failure; walking remains usable; erase clears personal walks and exploration |

Update 2026-10-09: Metro Manila is the initial map people can record walks on (main-road context across NCR; trails record anywhere). Makati CBD (primary) and Muntinlupa have street/footpath detail and place catalogs. The original note follows. The confirmed starter city is Makati. Begin with a proposed Makati CBD subset; its exact walking boundary still needs outdoor validation. Luzon is the initial product market, not a promise to ship detailed coverage of all Luzon in eight hours.

## P1 — add after both required loops pass

- Attach one ordinary photo to a walk and show it in the recap. Use a photo picker first; camera capture is a later convenience.
- Produce a subject cutout with a restrained sticker border if real-device image processing works. Preserve ordinary photo fallback.
- Place one approved cat pose on the empty map or recap after the canonical sheet is prepared for individual assets.
- Show storage usage by app/model/map/photos and offer local export/backup.
- Additional languages and broader conversational support beyond the required Taglish outing prompts.

## Deferred

Full Luzon downloads, offline road routing, social feeds, accounts, payments, streaks, badges, animated mascot, Android, cloud sync, continuous all-day tracking and generative photo redrawing. These are roadmap candidates, not obligations of this demo.

## Two required user paths

1. Open → Start walking → permission if needed → accepted movement reveals corridor → pause/resume → finish → persisted recap.
2. Open → Help me choose somewhere → type request → real local inference → sourced suggestions → select destination → Start walking → persisted recap.

Success means the founder can complete both paths offline on the real phone. If phone inference fails, the Local AI MVP is incomplete; do not silently remove AI from the acceptance criteria.
