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

At 80% of the time budget, stop adding features. P1 photos/cutouts only fit if both P0 paths are already proven. Before switching artifacts, check file path and checksum, model/runtime compatibility, correct chat template, available memory, signed-device logs and context allocation. Record the actual error without exposing private data. If the model gate exceeds its cap, try shorter context and retest. A smaller artifact requires an explicit change to the selected 1.7B decision and fresh evidence. Report the blocker if genuine phone inference is still unavailable. A Mac server or hardcoded answer does not satisfy the user's phone-only requirement.

## Dependency order

For the founder-approved 1.7B expansion, follow [LOCAL-AI-MVP.md](LOCAL-AI-MVP.md): align provisioning and serialize inference → versioned evidence/contracts → history search and grounded narration → editable preferences → adaptive suggestions → actual phone acceptance. Apply [ACCESSIBILITY-AND-SAFETY.md](ACCESSIBILITY-AND-SAFETY.md) before interpreting access requirements as matches. This is additional MVP scope, not a claim that it fits the historical eight-hour allocation. Coordinate road metadata contracts with Claude's GPS work and use one integration owner for shared app state.

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
