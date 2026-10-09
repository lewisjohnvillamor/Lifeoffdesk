# Life Off Desk

An offline-first iPhone exploration app: ask in Taglish for a nearby outing, pick a real local place, and reveal your personal map through actual walking.

**First city: Makati. First test phone: iPhone 12 Pro Max. Develop on an Apple silicon Mac with Xcode.** Both genuine phone-local AI suggestions and GPS fog reveal are required. No account or cloud inference is part of the intended MVP.

## Start on your Mac

```bash
git clone https://github.com/lewisjohnvillamor/Lifeoffdesk.git
cd Lifeoffdesk
brew install xcodegen
scripts/setup_ios.sh        # verifies downloads, unpacks llama.xcframework, generates the Xcode project
open LifeOffDesk/LifeOffDesk.xcodeproj
```

Set your signing team, pick the iPhone (simulator builds are not supported by the pinned runtime) and Run.

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

The app source, tested core logic, on-device inference adapter and Makati starter data are in place. **The app has not yet been compiled in Xcode, installed on the iPhone, run offline on the phone or tested outdoors.** The inference adapter has been run against the real model on a Linux CPU as a development diagnostic only. See [build status](docs/BUILD-STATUS.md) for exactly what was tested.

The first build is a small Makati subset; broader Luzon maps, road routing, social features and photo cutouts follow after the required loops pass.
