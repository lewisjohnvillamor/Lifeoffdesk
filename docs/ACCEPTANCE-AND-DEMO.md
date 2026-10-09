# Life Off Desk — acceptance and demo

## Required verification

The expanded MVP also requires the [local AI acceptance matrix](LOCAL-AI-MVP.md#acceptance-and-evaluation) and [accessibility evidence fixtures](ACCESSIBILITY-AND-SAFETY.md#verification-fixtures). On the actual offline phone, search saved adventures in Taglish, request a grounded recap, explicitly save/edit/reset preferences, and obtain adaptive suggestions without relaxing hard constraints. Show an unknown-access/no-match example. Labeled fixtures can prove logic, but cannot verify a real entrance, outdoor GPS or phone inference. Original walk/planner demo acceptance alone does not establish completion of P0-12–16.

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

## Blank slate vs explored map

Settings → Presentation → **Demo map** switches the map to bundled synthetic walks (`scripts/build_demo_walks.py`) so the audience sees a well-explored map; **Replay a sample walk** animates the fog reveal. The UI labels this as synthetic, not real GPS. Turning it off (or tapping Start walking) returns to the personal map, which may be blank. Say plainly in the pitch that the explored map is sample data; real walks are shown separately.

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
