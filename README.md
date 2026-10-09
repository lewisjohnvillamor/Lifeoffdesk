# Life Off Desk

An offline iPhone exploration app: ask in Taglish for a nearby outing, pick a real local place, and reveal your personal map through actual walking. Built for the AppBuildersPH Hackathon 2026 (Local AI): an on-device LLM (Qwen3-1.7B via llama.cpp) runs the Taglish planner, adventure-history search and grounded recaps with no network at runtime.

**Submission answers (what runs locally, what needs internet, disclosures, why local AI, demo plan): [docs/SUBMISSION.md](docs/SUBMISSION.md).**

**First city: Makati. First test phone: iPhone 12 Pro Max. Develop on an Apple silicon Mac with Xcode.** Both genuine phone-local AI suggestions and GPS fog reveal are required. No account or cloud inference is part of the intended MVP.

## Start on your Mac

```bash
git clone https://github.com/lewisjohnvillamor/Lifeoffdesk.git
cd Lifeoffdesk
brew install xcodegen
scripts/setup_ios.sh        # verifies downloads, unpacks llama.xcframework, generates the Xcode project
open LifeOffDesk/LifeOffDesk.xcodeproj
```

Set your signing team, pick the iPhone and Run. `setup_ios.sh` downloads about 1.34 GB (model + runtime, checksum-verified). The pinned runtime has no Simulator slice; `LifeOffDesk/project-simulator.yml` builds a Simulator version that shows every screen but reports AI as unavailable.

Read [Mac setup](docs/MAC-SETUP.md) for prerequisites, download scope, source-data review and device steps. Downloads are separate from Git and checksum-verified. The Makati data script prepares unreviewed source records; it does not establish venues are currently open or accessible.

## Build contract

- [MVP feature list](docs/MVP-FEATURES.md)
- [Implementation plan](docs/IMPLEMENTATION-PLAN.md)
- [Architecture and data](docs/ARCHITECTURE-AND-DATA.md)
- [Brand guide](docs/BRAND-GUIDE.md)
- [Acceptance and demo](docs/ACCEPTANCE-AND-DEMO.md)
- [Hackathon source](docs/HACKATHON.md)
- [Remaining decisions](docs/IDEATION-QUESTIONS.md)
- [Skills and handoff](docs/SKILLS-AND-HANDOFF.md)
- [Current build status](docs/BUILD-STATUS.md)
- [Tool/material disclosure](THIRD-PARTY-NOTICES.md)

AGENTS.md and skills/ contain portable implementation guidance. The TXT brief and reference guide support later ingestion. Approved cat artwork is under assets/mascot/; the latest static interface board is under design/. The sticker sheet is still unsplit. The included Figma update script is unapplied.

## Repository layout

- `LifeOffDesk/` — SwiftUI iPhone app and `project.yml` (XcodeGen)
- `Packages/LifeOffDeskCore/` — platform-independent logic with tests (`swift test --package-path Packages/LifeOffDeskCore`)
- `Tools/PlannerEval/` — runs the app's planner against the pinned model on a dev machine (`scripts/run_planner_eval.sh`)
- `scripts/` — downloads, Makati OSM preparation, starter catalog build, iOS setup

## Current status

App, core library (114 tests), 1.7B on-device inference, street matching and the local-AI features (history search, grounded recap, preferences, adaptive suggestions, accessibility evidence) are implemented and merged. CI builds the unsigned iPhone app and the Simulator app on every push. The founder reported the iPhone 12 Pro Max checks working (offline AI, outdoor walk, camera/sticker, accessibility, edge cases).

**Phone measurements** (iPhone 12 Pro Max, `iPhone13,4`, iOS 26.6.2, Qwen3-1.7B Q4_K_M, `eval/taglish-heldout.json`, 60 cases, 2026-10-10). The Airplane Mode run had no network path at the start or the end:

| | Airplane Mode run | Earlier run the same day |
|---|---|---|
| Schema-valid / intent | 60/60, 47/60 | 60/60, 47/60 |
| Case latency | p50 7.38 s, p95 8.84 s (n=60) | p50 6.09 s, p95 7.50 s (n=60) |
| Generated tokens/s | 7.42 | not recorded |
| Highest sampled memory | 532 MB physical footprint | not recorded |
| Thermal state | serious, then critical | not recorded |
| Battery | 65% charging at start and end (USB cable; not a drain test) | not recorded |
| 60-case time | 412.8 s (warm-up 14.54 s) | 340.0 s (warm-up 13.59 s) |

Reports: [Airplane Mode](eval/results/taglish-heldout-iphone12promax-airplane-2026-10-10.json), [earlier run](eval/results/taglish-heldout-iphone12promax-2026-10-10.json). The Linux CPU development-machine score for this set is 46/60 intent and is not a phone result. Map-frame pacing was not measured. See [build status](docs/BUILD-STATUS.md).

Deferred by design: full Luzon map packs, turn-by-turn routing, accounts, live hazard information, reviewed accessibility facts (the evidence files ship empty, so access requests honestly return no verified places).
