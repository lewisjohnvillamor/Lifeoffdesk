# Life Off Desk

An offline-first iPhone exploration app: ask in Taglish for a nearby outing, pick a real local place, and reveal your personal map through actual walking.

**First city: Makati. First test phone: iPhone 12 Pro Max. Develop on an Apple silicon Mac with Xcode.** Both genuine phone-local AI suggestions and GPS fog reveal are required. No account or cloud inference is part of the intended MVP.

## Start on your Mac

```bash
git clone https://github.com/lewisjohnvillamor/Lifeoffdesk.git
cd Lifeoffdesk
python3 scripts/download_materials.py
python3 scripts/prepare_makati.py
```

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

## Current status

Planning, branding, assets and download/data-preparation scripts are present. **The native app, real-phone AI benchmark and outdoor GPS tests have not been implemented or verified.** Taglish evaluation prompts are supplied; they are not performance results. Large models/runtime downloads, private photos and personal tracks are ignored by Git.

The first build is a small Makati subset; broader Luzon maps, road routing, social features and photo cutouts follow after the required loops pass.
