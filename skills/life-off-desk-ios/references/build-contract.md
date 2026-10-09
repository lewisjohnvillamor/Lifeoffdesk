# Portable build contract

Updated 2026-10-09. Repository docs are canonical. Makati and Taglish are confirmed.

# Life Off Desk — MVP feature list

Decision version: 2026-10-09, Asia/Manila. This is a build specification, not a claim that features have been implemented.

## Product and first user

Help a desk-bound person in Luzon take a short outing, find somewhere worthwhile, and grow a private map through actual movement. The initial customer hypothesis is workers, developers and freelancers who want low-effort 15–60 minute breaks. Demand is unvalidated. The first test user is the founder on an iPhone 12 Pro Max.

The opening screen is a warm ivory map with **Start walking** as its main action and **Help me choose somewhere** as a secondary action. Chat is optional for the user but **required in the MVP**. Both walking and genuine on-device AI suggestions are P0 because the event theme is Local AI.

## P0 — required for a complete demo

| ID | Feature | Minimum behavior | Acceptance evidence |
| --- | --- | --- | --- |
| P0-01 | Map-first entry | Open the personal map immediately; no account or download gate | Fresh install opens the map; clear Start walking and suggestion actions |
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

The confirmed starter city is Makati. Begin with a proposed Makati CBD subset; its exact walking boundary still needs outdoor validation. Luzon is the initial product market, not a promise to ship detailed coverage of all Luzon in eight hours.

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


# Life Off Desk — implementation plan

## Confirmed build context

Apple silicon Mac with Xcode; first device iPhone 12 Pro Max. Native iPhone app. Walk/reveal and AI suggestions are both required. AI must execute on the phone. Eight hours is a planning budget, not a delivery guarantee. Actual remaining time, judging rubric and submission cutoff have not been supplied.

## First checks on the Mac

1. Read repository instructions and preserve existing work. Open or create the Xcode app project after inspecting the current checkout.
2. Record Xcode version, iPhone iOS version, signing team and deployment target. Propose iOS 17+ only if the device supports the APIs selected; do not silently require a newer phone.
3. Install a minimal app on the real phone. Confirm Developer Mode/signing as needed and prove that launch works before UI polish.
4. Pin runtime release/commit, model artifact and checksums. Download dependencies/model before the offline demonstration; initial provisioning needs connectivity.
5. Confirm the organizer's actual Local AI eligibility and submission requirements. The theme alone does not establish the full rules.

## Eight-hour spending caps

These are elapsed work allocations from the actual start, not measured implementation estimates. Update them after the first evidence.

| Elapsed budget | Work | Exit condition |
| --- | --- | --- |
| 0:00–0:30 | Device launch, scope and demo contract | Signed app launches on target phone; rules/deadline recorded |
| 0:30–1:45 | Hard dependency: local AI | Model returns validated preferences from a real prompt entirely on phone with network off |
| 1:45–3:15 | Tracking and durable sessions | Real GPS, pause/resume/finish and interrupted-session recovery work |
| 3:15–4:15 | Fog and starter geometry | Actual trail reveals local detail and persists across relaunch |
| 4:15–5:15 | Catalog and AI result UI | User request leads to actual source-backed suggestions and destination selection |
| 5:15–6:25 | Recap, errors and visual integration | Both complete paths pass; no placeholders masquerade as features |
| 6:25–8:00 | Freeze, outdoor/offline checks, demo and submission buffer | Repeatable phone demo and recorded backup; unresolved limitations documented |

At 80% of the time budget, stop adding features. P1 photos/cutouts only fit if both P0 paths are already proven. Before switching artifacts, check file path and checksum, model/runtime compatibility, correct chat template, available memory, signed-device logs and context allocation. Record the actual error without exposing private data. If the model gate exceeds its cap, try one smaller compatible artifact or shorter context and retest. Report the blocker if genuine phone inference is still unavailable. A Mac server or hardcoded answer does not satisfy the user's phone-only requirement.

## Dependency order

Runtime/model proof → typed AI output → validated preference schema → catalog filtering → suggestion UI.

Device launch → location permission → accepted sample pipeline → local persistence → fog mask → recap.

Keep those services separate so model failure cannot erase or block a walk. Integrate the two paths through selected destination state.

## Proposed project organization

```text
LifeOffDesk/
  App/                 app lifecycle and composition
  Features/Map/        map canvas, fog, walk controls
  Features/Planner/    chat input, suggestions, destination
  Features/Recap/      history and computed recap
  Services/Location/   permission, session updates, filtering
  Services/AI/         local runtime adapter, output validation
  Services/Places/     local catalog, deterministic search
  Persistence/         versioned local records and recovery
  Resources/           brand assets, starter data, notices
  Tests/               meaningful filtering/state/AI validation tests
```

Use SwiftUI for screens, Core Location for real fixes, a local vector canvas for the small offline starter map, and an isolated local inference adapter. Start with versioned atomic Codable files for sessions/catalog; move to SQLite/SwiftData only when data scale or existing repo conventions justify it. Persist incrementally; do not wait until Finish.

## Build evidence to record

Maintain `docs/BUILD-STATUS.md` with commit, target device/iOS, actual runtime/model/hash, artifact bytes, load time, cold/warm response latency, peak memory if measurable, JSON validation results, offline test and GPS observations. Keep personal coordinates/photos out of public evidence. Linux planning work cannot establish Xcode or iPhone performance.

## Definition of ready to build

Known demo location and data sources; installed phone app; actual model artifact obtainable; explicit starter boundary; confirmed organizer deadline. Missing decisions are tracked in IDEATION-QUESTIONS.md rather than guessed as approved facts.


# Life Off Desk — architecture and data contracts

## Offline architecture

SwiftUI views call a walk coordinator, local store, local catalog and local AI adapter. Location updates and AI run through separate tasks. Inference runs only after a user request, away from the UI thread; cancel it when the user leaves or requests cancellation. Bound model work and avoid loading it continuously during a walk.

For the starter slice, render bundled road/path GeoJSON and POIs in a simple projected canvas. Mask underlying detail with the accumulated explored corridor. A trail can still be recorded outside bundled coverage, with “Map detail unavailable here.” Do not rely on a warmed online map cache as proof of offline maps. Adopt a full offline map SDK only after the small required demo works.

## Session lifecycle

Idle → requesting permission → acquiring GPS → walking ↔ paused → finished.

Denied permission returns to an actionable idle state. No valid fix means no fabricated live marker. Finish is idempotent. A crash or app termination leaves a recoverable paused session; never silently resume collection. Tracking begins explicitly and stops on Finish. Test the actual chosen background-location configuration on the phone rather than claiming continuous tracking from simulator behavior.

## Records

| Record | Minimum fields |
| --- | --- |
| WalkSession | UUID, schemaVersion, state, startedAt, endedAt?, activeDuration, accepted samples, segment boundaries, destinationPlaceID? |
| TrackSample | latitude, longitude, timestamp, horizontalAccuracy; optional measured speed |
| Exploration | schemaVersion, accepted segmented paths or derived mask, revealWidthMeters, source session IDs |
| Place | stable ID, name, coordinates, category, tags, source URL/ID, retrievedAt, verification status; optional supported cost/hours facts |
| Suggestion | source place ID, matched preferences, computed straight-line distance, uncertainty labels |
| Memory (P1) | UUID, sessionID, local file path, timestamp, optional opt-in location, optional cutout file |
| RegionManifest | ID, version, bounds, source/attribution, actual byte count, file checksums |

Keep exploration independent of map-data versions so replacing a starter map does not erase progress. Rebuild render caches from saved paths. Save atomic snapshots incrementally; retain recoverable prior state if decoding fails. Large model artifacts are provisioned separately; do not casually commit them to Git.

## GPS and reveal policy — starting values to test

These values are provisional tuning defaults, not empirically validated safety thresholds:

- Reject negative horizontal accuracy, samples older than 10 seconds and accuracy worse than 30 meters. Reject future timestamps above a provisional 2-second clock tolerance and non-increasing timestamps. Apply freshness at receipt; previously accepted historical samples remain valid history.
- Break the segment across an update gap above 15 seconds; never fill a long missing section with a revealed line.
- Reject implausible pedestrian jumps above roughly 4 m/s after considering time and accuracy. Treat vehicle mode as deferred.
- Use a small movement hysteresis (start at 5 meters) plus accuracy-aware stationary handling. A few meters of GPS drift must not steadily expand the map.
- Start with a 25-meter total corridor width. Render in projected meter coordinates; retain original accepted geographic samples.
- Distance sums accepted segments only. Active duration excludes pause. Revisited paths preserve the same explored area; do not award duplicate area.

Tune during an outdoor walk and keep replay fixtures for stale fixes, large jumps, pause gaps, long update gaps and stationary jitter. Do not assert percent of Luzon explored until an area denominator and coverage method exist.

## AI contract

The model extracts intent. App code finds actual places. Begin with one short turn and this proposed schema:

```json
{"durationMinutes":30,"budgetPHP":null,"categories":["park"],"moodTags":["quiet"],"travelMode":"walk","needsClarification":false}
```

Proposed initial bounds: duration 5–120 minutes or null; budget 0–10000 PHP or null; travelMode must be walk; categories allow park/cafe/museum/library/scenic/other, at most three; moodTags allow quiet/nature/curious/relax/active, at most three. Use a proposed 2 km initial straight-line search radius, adjustable explicitly up to 5 km. These are product defaults to confirm, not model capability claims. Validate bounds, enums, array sizes and types. Treat null as unknown. If needsClarification is true or the request cannot be interpreted, ask one short clarification before searching rather than fabricate preferences. Reject malformed output; one bounded repair attempt is permissible, then a clear retry/manual-filter state. Manual filters keep the app usable but are not proof of Local AI.

Use a constrained output grammar if supported by the pinned runtime, short context (initial trial 1024–2048 tokens) and bounded output (initial trial 128–192 tokens). Those are trial settings; compare quality and memory on the actual phone. Apply the model's correct chat template. Treat catalog/user text as data, not executable instructions.

Rank deterministically using supported categories, selected maximum radius and verified tags. Unknown price does not satisfy a strict price ceiling. Unknown quietness/hours remain unknown. If duration implies a reachable limit, do not equate straight-line distance with route distance; show it as approximate and avoid hard promises. A transparent suggestion card can say “Matches your park preference; 0.8 km straight-line; opening hours unverified.” That number is illustrative, not a seeded venue fact.

## Starter content and storage

Gather 15–30 real nearby places for one chosen area. Record provenance and retrieval date for every record. Missing matches must produce a useful empty state. Prepare small road/path data separately. If using OpenStreetMap-derived content, preserve source attribution and required license notices; verify dataset distribution terms. Do not scrape public map tiles for an offline pack.

Track app binary, runtime, model, map/catalog and personal photos as separate byte counts. The Qwen publisher's Qwen3-0.6B GGUF Q8 listing shows approximately 639 MB; that is model storage, not peak RAM or total app size. Prefer a smaller compatible quantization only after provenance, license and quality testing. No full Luzon storage estimate is justified until boundaries, detail level and sources are chosen.

Privacy intent: no account, analytics upload or cloud inference in this slice. No cloud-sync capability added by default. Describe OS backup behavior honestly; do not promise that device data can never enter a user's backups. Erase personal data without accidentally deleting reusable model/map assets. Provide export before wider use as a P1 protection against device loss.

## Makati and Taglish implementation update

Use config/regions.json for the proposed Makati CBD subset. scripts/prepare_makati.py retrieves source records and starter road geometry once during provisioning; review places before bundling. Raw OSM records are source-backed, not independently verified open/accessible venues. Treat Taglish requests as required AI inputs; see eval/taglish-cases.json. Display Taglish guidance through localized templates built from validated matches, with model intent extraction actually running on the phone. Localized templates do not replace the model inference requirement.


# Life Off Desk — acceptance and demo

## Required verification

| Check | Evidence to collect |
| --- | --- |
| Real device | Installed build on iPhone 12 Pro Max; exact iOS/build recorded |
| True offline | Airplane mode, Wi-Fi off, Mac disconnected; catalog/model already provisioned |
| AI engine | Actual runtime/model/hash, one changed prompt, real output and elapsed response time |
| AI quality | 10 representative prompts: straightforward, ambiguous, no-match, invalid budget, unsupported facts and prompt injection; record results, not production accuracy claims |
| Grounding | All suggested IDs exist in catalog; names/facts use records; no fabricated route, price, quietness or hours |
| Tracking | Outdoor accepted samples form a plausible trail; no reveal before valid fix |
| GPS edge cases | Stationary drift, stale samples, teleport, pause/resume and long gaps do not over-reveal |
| Recovery | Relaunch retains finished walks and exploration; interrupted session is recoverable and paused |
| Permission denial | No fake location; useful explanation/settings action; browse prior history still possible |
| Model failure | Walk remains usable; entered prompt preserved; clear retry/manual choice |
| UI | Safe area, keyboard, large text, touch targets, contrast and no clipped primary controls |
| Privacy | No required account/network; clear stop behavior; erase works |

Proposed AI usability target: warm response within 10 seconds for a short request, 9/10 valid-schema cases, zero invented venue facts. These are targets to evaluate, not observed results or event rules. A schema-valid response can still misunderstand intent; record those failures separately. Measure cold model loading too.

## Three-minute demo script

1. Show the real phone with airplane mode on, Wi-Fi off and Mac disconnected. Open directly on the personal map.
2. Open planner. Enter a short outing request for the prepared starter area. Show live on-device processing and an actual catalog-backed place card. Change one meaningful preference to prove the result is not canned.
3. Choose a place. State that the marker is a destination and any shown distance is straight-line; route navigation is deferred.
4. Start walking and show genuine corridor reveal on a prepared safe walking segment. Pause, resume and finish. For a seated pitch, use a clearly labeled replay of the previously verified outdoor walk while still demonstrating live AI.
5. Show recap, reopen the app and show persisted exploration. Close with the product promise and accurately state starter coverage and measured limitations.

Prepare a recorded backup of a real prior run. Label replay and simulation clearly. A recording is fallback evidence, not a substitute for a required live demo if the event forbids it.

## Evidence template

```text
Commit/build:
Date/time (Asia/Manila):
Device / iOS / Xcode:
Runtime pinned version:
Model source / filename / SHA256 / bytes:
Cold load / warm request latency:
Peak memory (measured or unavailable):
Offline conditions:
AI cases passed / failed and reasons:
Outdoor walk outcome:
Known limitations:
Official rule/deadline source:
```

This planning package contains no executed app or phone benchmarks. Complete these checks during the build on the Mac and iPhone.
