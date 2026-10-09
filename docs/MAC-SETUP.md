# Mac download and build setup

Develop on the confirmed Apple silicon Mac with Xcode. Target the actual iPhone 12 Pro Max. This repo currently contains the specification, references, assets and preparation scripts; it does not yet contain an implemented Xcode app.

## 1. Clone and check tools

In Terminal:

```bash
git clone https://github.com/lewisjohnvillamor/Lifeoffdesk.git
cd Lifeoffdesk
xcodebuild -version
python3 --version
```

If Xcode command-line selection is wrong, open Xcode → Settings → Locations and select the installed Xcode under Command Line Tools. Complete any first-launch component installation in Xcode. Python 3 and curl are needed by the preparation scripts; the scripts use the Python standard library, with no pip dependencies.

If you already cloned the repo, enter it and use `git pull --ff-only`; do not overwrite local work.

## 2. Start required downloads

```bash
python3 scripts/download_materials.py
```

This downloads one candidate model and the pinned llama.cpp iOS XCFramework. Each file is checked against a recorded SHA256 before acceptance. Approximate transfer: model 429 MB + framework 62 MB, about 491 MB total. Free space must also cover extracted runtime files and Xcode build products. Disk size is not peak inference RAM.

The model is ggml-org's Qwen3-0.6B Q4_0 artifact, pinned to a Hugging Face commit. The runtime is llama.cpp b11429, pinned to release assets. Neither Taglish quality nor iPhone performance has been measured here. Inspect config/materials-lock.json for exact sources/checksums.

Optional Mac command-line binaries for diagnostics:

```bash
python3 scripts/download_materials.py --group mac-tools
```

Mac inference is development diagnostics only; it does not satisfy the required iPhone-local demo. Downloads are ignored by Git. The script downloads artifacts and does not install or execute their contents.

## 3. Prepare Makati source data

```bash
python3 scripts/prepare_makati.py
```

The proposed starter bounding box is in config/starter-region.json. This makes one provisioning request to Overpass and saves source places, road GeoJSON and provenance under local-data/makati/. It does not download all Luzon. Public services can fail or rate-limit; do not loop requests aggressively.

Review 15–30 relevant source places before copying a curated catalog into app resources. Source records are not independent proof of current access, prices, quietness or hours. Review restricted/private paths. Road geometry is visual context, not a routing graph. Keep OpenStreetMap attribution/license notices. If the endpoint is unavailable, export the printed query through an available Overpass instance and run `python3 scripts/prepare_makati.py --input /path/to/export.json`.

## 4. Start the implementation agent

Read AGENTS.md and docs/IMPLEMENTATION-PLAN.md. Ask your agent to read these portable skill files directly:

- skills/life-off-desk-ios/SKILL.md
- skills/life-off-desk-local-ai/SKILL.md
- skills/life-off-desk-brand/SKILL.md

Automatic skill installation is not assumed. Follow the client-specific installation workflow if desired; direct reading works for this handoff.

Create/open the Xcode iOS app after inspecting the repo. Set signing, connect the iPhone and prove a minimal launch. Add the downloaded XCFramework to the app using the pinned upstream integration example; inspect its extracted structure rather than guessing paths. Bundle or provision the model with a documented local file path. Do not rely on a Mac server.

The next gate is real phone inference of the prompts in eval/taglish-cases.json, with airplane mode on, Wi-Fi off and Mac disconnected. Then complete actual GPS/fog, durable recap and grounded planner results. Record measured results in docs/BUILD-STATUS.md.

## 5. Submission

Confirm exact cutoff and track rules from the kickoff briefing; see docs/HACKATHON.md. Prepare an actual demo video and disclose libraries, AI tools and earlier planning/reference assets. No submission or message to the organizer has been made by this task.
