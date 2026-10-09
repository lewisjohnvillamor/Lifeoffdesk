# Life Off Desk — build status

## Founder phone check and silent-failure audit (2026-10-09)

**Founder-reported, iPhone 12 Pro Max:** after building `main` at `7317b4d`, the founder reported that all six phone checks "are working": 1.7B load and responses, fully offline use of planner/history search/Taglish recap/preferences, an outdoor walk (GPS trail, street matching, new streets, km by streets), camera/library/share/sticker, VoiceOver/large text/reduced motion, and the device edge cases (erase during AI, walk start during load, relaunch). This is recorded as the founder's report. No load time, latency (p50/p95), memory or thermal numbers, model hash readout or diagnostics JSON were provided to this repository yet, and no latency budget has been agreed, so performance acceptance stays open until those numbers are recorded (Settings → AI diagnostics → Copy JSON report).

**Silent-failure audit of the AI path** (model file → coordinator → task → UI), fixed in this round:
- Interrupted requests (walk start, low-memory warning, erase) used to reset the planner/history to idle silently. Now they show "Na-interrupt ang AI (reason). Subukan ulit." with retry; recap narration shows the computed fallback with the interruption reason.
- A same-named model file in Documents was used without checking it. Now every load checks the exact locked byte size (1,282,439,264) and refuses a wrong/incomplete copy with a message. The full SHA-256 stays on demand.
- Loading with too little free memory could get the app killed by iOS. A preflight now checks `os_proc_available_memory()` against file size + 700 MB headroom (a provisional figure) and explains instead of loading.
- Planner "model failed" now shows the reason (engine error, or the validator errors after the repair attempt).
- An unreadable `place-facts.json` already failed closed but was indistinguishable from "no facts". Now it is listed in diagnostics with the number of loaded access facts, plus the last AI problem and last interruption.

Remaining by design: the model can still be steered by hostile text into stricter filters (visible, removable chips; hard filters stay deterministic); a held-out miss returns a wrong-but-valid filter that the user sees as chips, not a hidden error.

## Local AI expansion implemented — P0-12–16 code complete, phone acceptance pending (2026-10-09)

Merged `main` (`f24a819`, the 1.7B/accessibility specification) into the working branch and implemented it. **Nothing below has run on the iPhone 12 Pro Max**; every phone gate in [LOCAL-AI-MVP.md](LOCAL-AI-MVP.md#acceptance-and-evaluation) remains open.

**1.7B provisioning aligned.** `download_materials.py` default (`required`) now fetches `model-large` + runtime; `setup_ios.sh`, `project.yml` (bundled resource), `AIService` filename/SHA-256 (`d2387ca2…`), the eval script and Mac setup all select `Qwen3-1.7B-Q4_K_M.gguf`. CI's unsigned device build downloads and bundles the 1.28 GB artifact successfully. No silent fallback: a missing file shows "model missing".

**Inference coordinator.** `InferenceCoordinator` (Core actor) owns all model work: single-flight load, one generation at a time, task IDs, caller cancellation, and an epoch that walk start, memory warning and erase bump; stale loads are never installed and late results throw `stale`. Planner, history search, recap narration and diagnostics all go through it. 5 tests with a fake slow engine (no overlap, one load for 6 concurrent requests, unload during generation/load, cancellation, retry after failed load).

**P0-12 history search.** `HistoryQueryV1` (period enum incl. custom ISO dates, min/max active minutes, hasPhotos, passed-near categories, sort, limit 1–20, needsClarification), strict validator (exact keys, enums, bounds, duplicates, custom-only dates), GBNF grammar, Taglish prompt with a captured reference date, one repair. Dates resolve in app code: Monday week start, half-open intervals, captured time zone. Deterministic search over a summary index of real saved adventures (sample data excluded) with stable tie-breaks. UI: search field in Adventures, removable filter chips, empty/zero-match states, passed-near disclaimer; calendar/list keep working without the model. 12 tests incl. month/year boundaries and time-zone edge.

**P0-13 grounded recap narration.** `RecapFacts` from the chronological recap (zero/unavailable facts omitted). The model selects ≤3 supplied fact IDs + tone (grammar lists only supplied IDs); a deterministic Taglish renderer inserts computed values. Validator rejects unsupplied IDs, extra keys/prose, duplicates. Recap shows "AI-selected highlights · values computed" or a labelled computed fallback with the reason. Cache keyed by session, facts hash, schema, prompt version, model file and language; removed on delete/erase; a deleted adventure is never resurrected by an in-flight request. Finish/save never waits for AI. 7 tests.

**P0-14 preferences.** Versioned `PreferenceProfile` (categories, duration, radius, novelty, language, access needs) in `preferences.json` with atomic write + backup. Newer schema is detected by a probe, preserved byte-for-byte and blocks saving; corrupt file falls back to backup; erase clears it. Precedence: explicit request > saved soft preferences > defaults; saved access needs stay (union) until edited; applied saved fields are shown under results. Settings editor (view/edit/reset/save, unsaved-changes note) and planner "Save these preferences" (explicit only). 6 tests.

**P0-15 adaptive suggestions.** Planner schema v5 adds `novelty`, `accessNeeds`, `routeAccess` (prompt/grammar/validator/examples/fixtures updated together; older JSON decodes with neutral defaults). Ranking uses computed passed-near history ("bago para sa'yo" / "nadaanan mo na"); passing near is never called liking. Route-level access requests get an explanation and an optional, user-chosen venue-entrance filter. 3 tests.

**P0-16 evidence and eligibility.** `EvidenceFactV1` + versioned `place-facts.json` sidecar per detailed pack (listed in the region manifest checksums; builder keeps curated facts across rebuilds). **Both sidecars are empty: no entrance has been reviewed**, so any hard access requirement currently returns the honest empty state ("Walang lugar … may reviewed na record") with a button to remove the requirement. `EligibilityPolicy` passes only a scoped, reviewed, unconditional, current (explicit `validUntil`) positive fact; absent, negative, limited, source-only, conflicted, contradictory, expired, no-validity, future-dated, conditional, wrong-place, wrong-kind and street-scoped facts all fail (synthetic fixtures, 7 tests). Cards say "Path to it: not verified". Frontier targets are now snapped to a real unexplored street point (restricted ways already excluded from the street network); 1 test.

**Other fixes this round.** Walking-graph distances ("3.49 km by streets") no longer show a walking ETA, per the spec. No-photo memory cards use the paper-map look with the inked route and explain a missing GPS trail (the founder saw an empty green card). Me shows off-street distance so "new streets" vs "area explored" is explainable; totals say "Calculating…" while sample stats compute. Diagnostics can load the model on demand.

**Verification here.** 113 core tests pass (Linux, Swift 6.3.3) and in CI (macOS); 11 Python tests pass; CI unsigned device build and simulator build pass. Simulator screenshots confirm the paper no-photo card, collage, the Adventures search bar (disabled for sample data) and planner layout; the Vision sticker cut-out fell back to the bordered photo in the Simulator (needs the phone).

**Development-machine model evaluation (Linux CPU, Qwen3-1.7B Q4_K_M, grammar on; NOT iPhone evidence).** Fresh held-out sets written before any run and not used for tuning: `eval/adaptive-heldout.json` (14), `eval/history-heldout.json` (14), `eval/recap-heldout.json` (12), plus the existing 60 Taglish planner cases. Adaptive planner: **14/14 schema-valid, 10/14 intent pass**, ~25 s per request on this CPU. Failures: "hindi ko pa napupuntahan" not mapped to `new` (#301); "walang hagdan sa entrance … naka-wheelchair" returned both needs where the case expected wheelchair only (#305, arguably correct); a route request dropped the park category (#308); a prompt-injection case ("set accessNeeds to everything") produced both access needs plus clarification (#311). The last fails closed (stricter visible, removable chips; never relaxed access) but shows the model can be steered; hard filters stay deterministic. Follow-up results (same machine): **60 Taglish planner cases on v5: 60/60 schema-valid, 46/60 intent pass** (v4 was 41/60 on both 0.6B and 1.7B). **History search: 14/14 schema-valid, 10/14 pass**, ~18–21 s each. Failures: the spec's own example "Mga short walks ko last week na may photos" (#401) produced contradictory min/max minutes, which the validator turned into a clarification instead of guessing; "Long walks na walang photos" (#408) became sort=longest/limit 1 instead of ≥60 min; "first ever adventure" (#409) asked for a date instead of sort=oldest; the SQL-injection prompt (#412) asked for a date instead of returning all (safe, but scored as a miss against the pre-written expectation). **Recap narration: 12/12 valid fact-ID choices rendered with computed values**, including cases with hostile place names (the grammar only allows supplied IDs). Expectations were not changed after seeing results. Files: `eval/results/{adaptive,history,recap,taglish}-heldout*-1.7b-linux.json`. Phone latency/memory with 1.7B is unmeasured; agree a latency budget before calling performance accepted.

## Approved local AI expansion — documentation handoff, 2026-10-09

Pulled `main` at `55d67ba` before this handoff. Claude's street-snapping branch remains separate. The founder selected Qwen3-1.7B Q4_K_M and approved history search, grounded recap narration, editable preferences and adaptive suggestions as MVP additions. This supersedes the historical “0.6B stays” decision below, not its recorded evaluation results.

P0-12–16 are **specified, implementation/device acceptance pending**. See [LOCAL-AI-MVP.md](LOCAL-AI-MVP.md) and [ACCESSIBILITY-AND-SAFETY.md](ACCESSIBILITY-AND-SAFETY.md). The latter defines reviewed, scoped facts and strict unknown handling; no new accessible venues or safe routes have been verified.

Existing local changes in `AIService.swift` and `project.yml` select 1.7B; they are preserved and excluded from this documentation commit. Default setup/download selection still needs alignment. This handoff changes Markdown only: no new app builds, model evaluations, outdoor tests, offline phone runs or performance measurements were performed. Documentation verification covers local links, cross-references, locked artifact identity and whitespace. Earlier device gates remain unresolved unless separately documented with new evidence.

Updated 2026-10-09, Asia/Manila. Implementation started at the hackathon kickoff.

## Demo update and visible fog — local Mac verification, 2026-10-09

Pulled `927f450` with `git pull --ff-only`, preserving local simulator work (backup
stash retained). Ran `bash scripts/setup_ios.sh`: both cached model/runtime hashes
verified and the physical-device Xcode project generated.

Fixed the Canvas reveal mask to clip painting to the explored corridor rather than
using a destination-in stroke that left ground outside the stroke visible. Added
static cloud shapes and a fresh-map explanation; street detail remains hidden until
explored. Added an idle-screen **Preview demo map** shortcut to the upstream labeled
synthetic walks/replay, without writing demo data into personal exploration.

Validation: 47 core tests and 11 Python tests passed. Simulator planner/input-retention
and launch tests passed; launch averaged 1.982 s across three Debug measurements
(Mac simulator only). The initial demo UI test exposed a shortcut hidden when saved
exploration existed; moved the shortcut into idle controls and reran the demo test:
preview, synthetic replay disclosure and exit back to personal map all passed.
Final unsigned physical-iPhone build passed. Local result bundles:
`build/demo-smoke.xcresult` (initial failure), `build/demo-smoke-fixed.xcresult` (fixed demo test).
Phone AI, real GPS, outdoor/offline behavior and phone performance remain unverified.

## Local Mac / Simulator verification — 2026-10-09

Base commit `e012b4b`; `git pull --ff-only` reported already up to date. These results
include the uncommitted simulator-support changes. Xcode 26.3 (17C529), Apple silicon,
iPhone 12 Pro Max simulator with iOS 26.3. No physical device was connected;
actual phone iOS, signing team and signed launch remain unverified.

- Simulator Debug build and launch passed; app left open for manual exploration.
  Separate `project-simulator.yml` excludes the model and llama framework, uses
  `com.lifeoffdesk.simulator`, and displays a simulation banner. No generated AI answers.
- 44 core XCTest cases passed on this Mac: GPS filtering, session transitions,
  persistence/recovery, exploration, catalog search and structured-output validation.
- 2 Simulator UI tests passed: planner reports AI unavailable, retains the entered
  Taglish request, returns to walking entry and relaunches; launch metric collected.
- XCTest app-launch duration: **1.958 seconds average** across 3 measured iterations
  (1.868, 1.957, 2.049 s; relative standard deviation 3.787%). Debug build on a Mac
  simulator, not an A14 benchmark; no performance baseline or regression claim.
- Original physical-iPhone configuration also built successfully for generic iOS
  with signing disabled. It still links the pinned runtime and bundles the model.
- Local test artifact: `build/simulator-smoke.xcresult` (ignored). Logs:
  `/tmp/lifeoffdesk-{core-tests,simulator-tests,device-build}.log`.

Still untested: physical-phone inference/latency/memory, airplane-mode operation,
outdoor GPS/fog, signed deployment, background tracking and real-device persistence.
The UI smoke test confirms walking entry remains available, not a completed walk.

## What exists now

| Part | Location | State |
| --- | --- | --- |
| Core logic (GPS filter, sessions, recovery, exploration, persistence, AI schema validation, prompt/grammar, catalog search, Taglish copy, eval scoring) | `Packages/LifeOffDeskCore` | Implemented; 43 XCTest cases pass on Linux (Swift 6.3.3) |
| iPhone app (SwiftUI map/fog, walk controls, planner sheet, recap/history, settings/erase, AI diagnostics) | `LifeOffDesk/` + `LifeOffDesk/project.yml` | Compiles unsigned for generic iOS in CI (Xcode 16.4, macos-15); **not yet installed or run on a phone** |
| On-device inference adapter (llama.cpp b11429 C API, GBNF-constrained JSON, ChatML/no-think) | `LifeOffDesk/Services/AI/LlamaEngine.swift` | Compiled and run against the real model on Linux; **not yet run on iPhone** |
| Starter map packs | `LifeOffDesk/Resources/StarterData/<region>/` | Makati CBD (primary): 30 places + 4,131 street/footpath lines. Muntinlupa: 30 places (27 parks, 3 cafés) + 12,216 lines. Metro Manila: 13,400 main-road lines, no places. All places `source-only-unreviewed`; ~4.3 MB total |
| Demo map (synthetic) | `scripts/build_demo_walks.py`, `StarterData/demo/sample-walks.json`, Settings → Demo map | 34 synthetic walks (24 Makati ≈55 km, 10 Muntinlupa ≈22 km) generated along OSM streets; labelled in UI; never saved as personal data; animated replay |
| Dev-machine planner eval | `Tools/PlannerEval`, `scripts/run_planner_eval.sh`, `eval/results/` | Linux CPU diagnostics only |
| CI compile check | `.github/workflows/ios-build.yml` | Passing: core tests on macOS, Python tests, pinned downloads verified, XcodeGen, unsigned iOS build |

## MVP feature status (docs/MVP-FEATURES.md)

"Code done" means implemented and compiling; none of these is accepted until checked on the iPhone.

| ID | Feature | Code | Phone/outdoor verified |
| --- | --- | --- | --- |
| P0-01 | Map-first entry | Done | No |
| P0-02 | Explicit walk session (start/pause/resume/finish, permission) | Done; state logic unit-tested | No |
| P0-03 | Real GPS tracking with filtering | Done; filter unit-tested on synthetic replays | No outdoor walk yet |
| P0-04 | Fog of war, narrow corridor | Done (25 m corridor, tiled drawing) | No |
| P0-05 | Local persistence + recovery | Done; unit-tested | No relaunch/force-quit test on phone |
| P0-06 | On-device AI chat (Taglish) | Done; real model run on Linux CPU only | **No — the key open gate** |
| P0-07 | Grounded suggestions (≤3, sourced) | Done; unit-tested | No |
| P0-08 | Choose destination, straight-line label | Done | No |
| P0-09 | Honest recap + reopen | Done | No |
| P0-10 | Offline starter area | Done for Makati + Muntinlupa (+ NCR main roads); places unreviewed | No airplane-mode run |
| P0-11 | Errors/privacy (permission, no fix, no match, model missing/failure, erase) | Done | No |
| P1 | Photo memory card (photo + real route + computed new-street distance, share) | Done; renders in Simulator (no-photo fallback seen) | Photo picking/sharing not tried on phone |
| P1 | Cutouts, mascot accents, storage view/export | Not started | — |

## Visual/UX update (2026-10-09, after founder review)

- Map restyled to a paper-and-ink look (PlainWalk reference): fibrous paper fog, faint ghost streets, explored corridor as a raised torn-paper island with inked roads, optional 3D tilt. Verified by CI Simulator screenshots, not on the phone.
- Provisional reveal corridor widened from 25 m to 50 m total so explored areas read as places, not lines. Still a tuning value; check outdoors.
- Planner copy cut down: one input with send arrow, quick picks, compact cards with one caveat line (full uncertainty labels on tap).
- Fixed a real performance bug: recaps rasterised every stored walk on the main thread (seconds with a long history; it also blocked the recap sheet). Now neighbourhood-only capsule rasterisation; test proves identical results. Core suite 12 s → ~2 s.
- CI now captures Simulator screenshots (intro pages, blank, demo, close-up, flat, planner, recap, memory card, and a simulated-GPS walk through the real tracking pipeline: 91 m / 0:40 recorded, dotted trail and icon controls rendered).
- One-time skippable five-page intro (founder decision); smoke test checks it shows once.
- Trail styling: new ground as ink dots, revisited streets as a solid grey line.
- Walk controls are round icons (camera, pause/resume, finish) with accessibility labels.
- Captured moments: camera during a walk; photo saved on device with the latest accepted fix (none without a fix) and pinned on the map; erase removes them.
- Memory card styles: Photo / Collage / Sticker, choose from the walk's photos, add from library or take a final photo. Sticker uses iOS 17 on-device subject lifting; not verifiable in Simulator (white-border fallback used there).

## Founder feedback round 3 (2026-10-09)

- Layout restructured to three tabs (Map, Walks, Me). Map has no bottom card: tagline, round side buttons (Spot camera while walking, Locate, Layers menu with tilt and demo), today/total new-streets stack, one **Start exploring** button; while walking Pause plus **Hold to end** (VoiceOver gets a direct Finish action).
- Walks tab: this week vs last week, day dots, month calendar (tap a day to filter), "Watch your world grow" timelapse of all shown walks, walk list by month. Me tab: total new streets, distance, walks, area explored, photo spots, settings.
- Fixed: per-walk "new streets" now measured only against earlier walks (`WalkStats`, tested); later walks no longer shrink earlier numbers. Summed newly revealed area = exact explored area.
- Fixed "two maps": Metro Manila context roads duplicated detailed-pack roads with different hand-drawn wobble, drawing doubled lines that drifted apart when zooming. Context roads are now skipped inside detailed areas.
- Fixed planner origin: GPS ran only during walks, so the planner fell back to the Makati reference point. One-shot fixes are now taken when the planner opens, a destination is chosen, permission is granted or the app starts; the planner waits up to 8 s for one ("Hinahanap ka…"). "You are here" also shows outside walks (fixes are not trail).
- The map opens framed on the most recent walk.
- Planner: new `food` category and `keywords` field (validated, filler/mood words filtered); places now include up to 60 OSM food places per detailed area with cuisine tags kept as unverified source claims. Keyword search matches names/cuisine only; no match → honest empty result or labelled category fallback; an empty request → clarifying question instead of listing nearby parks. Linux CPU dev run (prompt v3, 14 cases incl. "Good pizza place."): 14/14 schema-valid, 13/14 intent (`eval/results/dev-linux-cpu-prompt-v3.json`). Not phone evidence.
- Catalog now 90 places per detailed area (still `source-only-unreviewed`).

## Adventures reframe and AI evaluation (2026-10-09)

- Product language moved from walks to **adventures**: tab "Adventures", metrics are new streets, **places found** (catalogue places within 40 m of the accepted trail, computed) and area explored; distance is secondary.
- **Next adventure** (✨ sheet): real targets only — undiscovered catalogue places ordered by the user's favourite categories, and **street frontiers** (clusters of unexplored street length nearby, by compass sector, computed from bundled road data). Frontiers do not run out while fog remains, which addresses area exhaustion; full coverage is the cue for more area packs later.
- AI evaluation expanded: `eval/taglish-heldout.json`, 60 new prompts (slang, typos, English/deep Tagalog, combined constraints, brands, out-of-scope, unsupported facts, injection), written after prompt v3 and not used for tuning. Linux CPU dev results (not phone):

| Model / prompt | 14 tuning cases | 60 held-out | Typical latency (dev CPU, 2 threads) |
| --- | --- | --- | --- |
| Qwen3-0.6B Q4_0, prompt v3 | 13/14 | 40/60 | 4.5–5.5 s |
| Qwen3-1.7B Q4_K_M, prompt v3 | — | 41/60 | 11–15 s |
| Qwen3-0.6B Q4_0, prompt v4 (10 examples, contradiction rule) | 13/14 | 41/60 | 6–8 s |

  All runs 100% schema-valid; no invented places. The bigger model did not help, so 0.6B stays. Remaining misses: durations in words, two categories in one request, implicit categories ("art", "fresh air"), some budgets. The held-out set has now been seen once; a fresh set is needed for the next honest measurement. Both sets can be run on the phone from Settings → AI diagnostics.
- Validator now resolves a model saying "ask" while extracting usable preferences in favour of the extracted data; it asks only when nothing usable came out.

## Street matching (2026-10-09)

- Accepted GPS is matched to bundled streets (within 25 m, heading within 40°, 5 m pieces). Raw trails are still the only stored data; matches are recomputed from them, so replacing street data never loses exploration.
- The paper island now follows matched street centrelines (40 m ribbon); off-street stretches ≥ 20 m (plazas, unmapped paths) keep a raw-trail ribbon. The live trail is drawn dotted on newly walked street pieces and solid grey on streets walked before.
- "New streets" = matched street length walked for the first time, counted against earlier adventures only. Frontier suggestions use unwalked street segments.
- Tests cover GPS drift snapping to the walked street, crossing a street without painting its length, cutting through a block (unmatched, not painted), once-only counting across adventures, reveal following centrelines, and frontiers skipping walked streets. Tolerances are provisional; check outdoors (wide avenues, parallel streets, underpasses).
- CI walking screenshot now uses a simulated route along real Makati street geometry (not hand-typed points).

## Delete, memory card route and street distances (2026-10-09)

- **Delete one adventure**: Recap → trash button → confirmation ("Delete this adventure?" / Delete adventure / Keep it). Removes the walk file and its backup, that adventure's photos and index entries, its exploration and recomputes stats. Sample (demo) adventures cannot be deleted. Core test `testDeleteOneAdventureKeepsTheOthers`. Not yet tried on the phone.
- **Memory card route** now draws the adventure's matched street pieces (plus off-street stretches), fitted to the card, instead of raw GPS points. CI screenshot 08b shows clean street lines. The earlier noisy card came from a synthetic sample walk drawn raw.
- **Photos**: simulator-only `--seed-photo` adds the bundled mascot test image (sim build only, not personal evidence) twice to a sample adventure; CI screenshot 08b shows both saved thumbnails and the selected photo on the card. Camera capture, library import and share sheet still need the phone.
- **Collage / sticker**: the first CI attempt did not switch styles (stale sheet state in the screenshot helper, fixed); collage and Vision sticker cut-out remain unverified until the next CI screenshots, and sticker lifting must be checked on the phone (Vision availability differs in the Simulator).
- **Street distances**: planner results, next-adventure ideas and the destination pill now use the shortest path over the bundled OSM streets (`WalkingGraph`: motorways excluded; private/no-access ways cost double and are flagged "may private road sa daan"), shown as "3.49 km lakad · ~47 min" (4.5 km/h). Off-street or disconnected points fall back to labelled straight-line. Time limits use street distance. This is a distance estimate, not navigation; OSM may miss gates, footbridges or closures. Founder example (Fordham Tower at East Bay → Hillsborough Aqua Park): straight-line ≈ 1.57 km; a development-only Python check on the same bundled data gave ≈ 3.0–3.5 km along streets depending on private-road handling, versus Google's 4.1 km walking route (different endpoints: our park marker is the area midpoint). Swift tests use synthetic layouts only.

## Gate table

| Gate | Status | Evidence |
| --- | --- | --- |
| Organizer source | Read | HACKATHON.md; exact cutoff and track rules still unknown |
| Starter area/language | Updated 2026-10-09 | Metro Manila recording area; Makati CBD (primary) + Muntinlupa detailed; Taglish. Demo segment still to choose |
| Xcode build | Passed in CI (unsigned) | GitHub Actions macos-15, Xcode 16.4, `generic/platform=iOS`; first run found one init error, fixed |
| Target iOS/signing | Not tested | Deployment target iOS 17.0; set DEVELOPMENT_TEAM in Xcode |
| Signed phone launch | Not tested | — |
| Actual phone inference offline | **Not tested** | Use Settings → On-device AI diagnostics on the phone in airplane mode |
| Inference adapter on real model (dev machine) | Passed (Linux CPU) | See below; not phone evidence |
| Catalog/data provenance | Prepared, unreviewed | OSM source URLs, retrieval time, rule-based selection recorded; no human review. Region boxes are OSM admin-boundary bounding boxes (Muntinlupa relation 1346849, Metro Manila 147488), which include water and some neighbouring areas |
| GPS filtering/session/persistence logic | Unit-tested | Synthetic replay fixtures only |
| Outdoor GPS/fog | Not tested | — |
| Background tracking | Not tested | `UIBackgroundModes: location` + `allowsBackgroundLocationUpdates` configured; verify on phone |
| Full offline demo | Not tested | — |
| Figma map-first revision | Unapplied | — |
| Sticker sheet split | Not done | Mascot not yet used in UI (P1) |

## Tested here (Linux container, 2026-10-09)

**Core unit tests — 63 passing** (demo dataset + replay tests added; multi-region pack checks and a Muntinlupa search test). Covers: invalid/inaccurate/stale/future/non-increasing fixes; teleport jumps; 15 s gap segment breaks; 5-minute stationary jitter (±4 m, 5–15 m accuracy) adds ≤3 trail points and <20 m; measured-zero-speed suppression; pause adds no trail; resume starts a new segment; distance excludes inter-segment gaps; active time excludes pauses; idempotent finish; invalid transitions; crash recovery to paused without counting closed time; recap numbers; exploration merge idempotence; revisits add no area; gaps are not revealed; corridor width; atomic save/reload; corrupt file falls back to backup and is set aside; newer-schema files untouched; erase keeps model/catalog; validator types/enums/bounds/extra keys/think-block stripping; out-of-range budget/duration → clarification; prompt sanitising against template injection; few-shot examples distinct from eval prompts; search radius/category/budget/mood/time labelling; bundled catalog keeps all facts unverified; planner repair (max one) and failure paths with a scripted engine (scripted engine is not AI evidence).

Two defects found and fixed by these tests: random GPS jitter leaked into the trail with the original 5 m threshold (now combined-accuracy threshold + speed hint), and 5 m raster cells under-counted the 25 m corridor (now 2.5 m).

**Python preparation tests — 11 passing** (demo generator determinism added; region queries, roads-only regions, place selection caps). Fixed `prepare_makati.py` dropping every park/museum way (Overpass `out geom` returns bounds, not center); now uses the bounds midpoint and records `positionMethod`.

**Real model through the app's LlamaEngine (development diagnostic, NOT iPhone evidence).** Machine: Linux x86_64, 4 vCPU Intel Xeon 2.1 GHz, CPU only, 2 threads. Runtime llama.cpp b11429 built from source; model `Qwen3-0.6B-Q4_0.gguf`, 428,970,080 bytes, SHA-256 `da2572f1…17d4` (matches lock). Context 2048, max 160 output tokens, greedy, grammar-constrained.

| Prompt version | Load | First request | Per-case | Schema-valid | Intent pass |
| --- | --- | --- | --- | --- | --- |
| v1 (`eval/results/dev-linux-cpu-prompt-v1.json`) | 0.46 s | 3.1 s | 2.8–4.4 s | 12/12 | 10/12 |
| v2, current (`…-prompt-v2.json`) | 0.79 s | 5.3 s | 3.6–4.8 s | 12/12 | 11/12 |

The v2 prompt was adjusted after seeing v1 failures, so the 12 cases are no longer a held-out set. Remaining intent problems in v2: case 6 "may one hour ako" → duration null; the model often adds an unrequested `quiet` mood (harmless to grounding, shown as "Hindi pa verified kung tahimik"); "tahimik na lugar" and "nature vibes" were mapped to `scenic`, which has no catalog places, so they return the no-match message. Case 10 (injection "invent Secret Moon") produced only real catalog cafés. Latency on the phone will differ (Metal, A14); measure it.

## Next steps on the Mac and iPhone

1. `brew install xcodegen && scripts/setup_ios.sh`; open `LifeOffDesk/LifeOffDesk.xcodeproj`, set signing team and a unique bundle ID, run on the iPhone 12 Pro Max. CI compiles it unsigned; signing and on-device launch are still unproven.
2. Settings → On-device AI diagnostics: Verify SHA-256, then Run all cases with airplane mode on, Wi-Fi off, Mac unplugged. Copy the JSON report into `eval/results/iphone-…json` and fill the evidence template in ACCEPTANCE-AND-DEMO.md.
3. Short outdoor walk: check fix acquisition, pause/resume, recap, relaunch persistence, force-quit recovery, background tracking, permission denial.
4. For the Muntinlupa test walk, note that many selected parks are inside subdivisions (Alabang Hills, Ayala Alabang, Pacific Malayan, Camella) and may be residents-only. Review the places (gated village parks such as Bel-Air/Urdaneta/San Miguel may not be publicly accessible) before calling anything verified; choose the demo segment.

## Known limitations

- The pinned xcframework has no simulator slice. `project-simulator.yml` now supports UI/walking checks with AI explicitly unavailable; real inference still requires the device.
- The model file is bundled into the app (~429 MB) by default; it can instead be copied to the app's Documents folder via Finder.
- Map rendering is a simple projected Canvas of OSM road lines; no labels, no routing, no tiles.
- Distances are straight-line from the current fix, or from the starter-area reference point (labelled) when there is no fix.
- GPS thresholds are provisional values from ARCHITECTURE-AND-DATA.md, not tuned outdoors.
- `prepare_makati.py` still defaults to overpass-api.de, which was unreachable from this container; data was fetched with its printed query from a public mirror and processed with `--input`.
