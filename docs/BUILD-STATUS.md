# Life Off Desk — build status

Updated 2026-10-09, Asia/Manila. Implementation started at the hackathon kickoff.

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
| P1 | Photo memory, cutouts, mascot accents, storage view/export | Not started | — |

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

**Core unit tests — 47 passing** (demo dataset + replay tests added; multi-region pack checks and a Muntinlupa search test). Covers: invalid/inaccurate/stale/future/non-increasing fixes; teleport jumps; 15 s gap segment breaks; 5-minute stationary jitter (±4 m, 5–15 m accuracy) adds ≤3 trail points and <20 m; measured-zero-speed suppression; pause adds no trail; resume starts a new segment; distance excludes inter-segment gaps; active time excludes pauses; idempotent finish; invalid transitions; crash recovery to paused without counting closed time; recap numbers; exploration merge idempotence; revisits add no area; gaps are not revealed; corridor width; atomic save/reload; corrupt file falls back to backup and is set aside; newer-schema files untouched; erase keeps model/catalog; validator types/enums/bounds/extra keys/think-block stripping; out-of-range budget/duration → clarification; prompt sanitising against template injection; few-shot examples distinct from eval prompts; search radius/category/budget/mood/time labelling; bundled catalog keeps all facts unverified; planner repair (max one) and failure paths with a scripted engine (scripted engine is not AI evidence).

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

- Simulator builds are impossible with the pinned xcframework (ios-arm64 + macOS slices only); develop on the device.
- The model file is bundled into the app (~429 MB) by default; it can instead be copied to the app's Documents folder via Finder.
- Map rendering is a simple projected Canvas of OSM road lines; no labels, no routing, no tiles.
- Distances are straight-line from the current fix, or from the starter-area reference point (labelled) when there is no fix.
- GPS thresholds are provisional values from ARCHITECTURE-AND-DATA.md, not tuned outdoors.
- `prepare_makati.py` still defaults to overpass-api.de, which was unreachable from this container; data was fetched with its printed query from a public mirror and processed with `--input`.
