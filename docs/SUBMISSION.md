# Submission pack — AppBuildersPH Hackathon 2026 (Local AI)

Deadline **10:00 AM, October 10, 2026 (Asia/Manila)** on https://cerebralvalley.ai/e/appbuildersph-hackathon-2026. One submission only, no edits, code freezes at 10:00 AM (judges review the repository as of the deadline). Repository: https://github.com/lewisjohnvillamor/Lifeoffdesk (public).

Fields marked **FOUNDER** must be filled by the team; nothing here is invented on their behalf.

## The project

- **Project name:** Life Off Desk
- **Short description:** An offline iPhone app that gets desk-bound people outside. An on-device AI notices when your world is getting smaller ("Uyyy, lumiliit na ang mundo mo!") and suggests a real nearby adventure. You can ask in Taglish ("tahimik na park, 30 mins lang"). As you walk, a paper map lifts its fog over the streets you actually covered. If something goes wrong, the SOS help chat understands Taglish (and photos), points you to reviewed first-aid and roadside cards, and shows 911, local hotlines and the nearest police or hospital. All of it works in Airplane Mode.
- **Team name and members:** **FOUNDER**: use the team name and names exactly as on the official list.
- **GitHub repository:** https://github.com/lewisjohnvillamor/Lifeoffdesk (public)
- **Hardware tested on:**
  - iPhone 12 Pro Max, the founder's own phone (A14 Bionic, 6 GB RAM). **FOUNDER**: add the iOS version from Settings → General → About.
  - Development Mac with Apple silicon and Xcode. **FOUNDER**: add the model and macOS version.
  - CI: GitHub Actions macOS runners (build and tests only).

## The proof

- **Demo video (~1 min):** **FOUNDER**. Use a real iPhone screen recording in Airplane Mode for the product demo (shot list below). The launch film `marketing/life-off-desk-launch-square.mp4` (56 s) is a promo built from labelled demo-world Simulator captures plus stock footage, so label it a promo if you use it here.
- **Screenshots:**
  - App Store-style panels: `marketing/mockups/store-1.jpg` … `store-7.jpg`.
  - Per-feature panels: `marketing/mockups/*-portrait.jpg` (map, route, coach, help chat, recap, card).
  - Raw captures: the `ci-screenshots` branch.
  - Screens with sample adventures are labelled "Demo world" / "SAMPLE".
- **X / LinkedIn video URL:** **FOUNDER**. Post the square cut (`marketing/life-off-desk-launch-square.mp4`), tag Devin / Cognition and include #AppBuildersPH.
- **What runs locally (on the iPhone, offline):**
  - **Qwen3-1.7B** (Q4_K_M GGUF) through **llama.cpp b11429**, compiled into the app (Metal). Every call is grammar-constrained JSON plus a validator with one repair attempt. It handles:
    - Taglish planner intent
    - history-search filters
    - recap highlight choice
    - the "your world" coach (picks facts, tone and quest from computed trends)
    - "Para sa'yo" place recommendations (picks from real candidates)
    - help-chat routing to a reviewed card, plus an emergency flag
  - **Apple Speech**, on-device only (`requiresOnDeviceRecognition`): voice input in the planner and help chat.
  - **Apple Vision**: `VNClassifyImageRequest` names objects in a help-chat photo (e.g. a tire); `VNGenerateForegroundInstanceMaskRequest` makes photo stickers.
  - **Deterministic code** (no AI):
    - place search and ranking, and walking routes over bundled OpenStreetMap streets
    - GPS filtering, street matching and the fog-of-war map
    - arrival detection, recaps and stats, and the recommendation rule checks
    - the Taglish keyword safety net (emergencies can't be hidden by the model)
    - the hotline lookup and the nearest police, hospital or fire station
  - **Data, all on the device:**
    - offline OSM map and place packs: Metro Manila main roads; detailed Makati, Muntinlupa, Taguig, Pasay and Parañaque
    - 28 sourced help cards
    - 26 sourced emergency hotlines
    - your walks, photos and preferences
  - No account, no server.
- **What requires internet:** nothing at runtime; the app makes no network calls. GPS works without data, and tap-to-call uses the phone network. Internet is needed only before use:
  - one-time setup to download the model (Hugging Face) and the llama.cpp runtime (GitHub releases), both pinned and checksum-verified
  - preparing map data from OpenStreetMap (Overpass mirror) at build time
  - refreshing help cards and hotlines from their sources, as a manual review step

## The disclosures

- **Models used:**
  - **Qwen3-1.7B Q4_K_M GGUF:** ggml-org quantization of Qwen3, Apache-2.0, pinned by commit and SHA-256 in `config/materials-lock.json`. Qwen3-0.6B was evaluated earlier and is not used.
  - **Apple on-device models** through system frameworks: Speech recognition and Vision image classification and foreground masks.
  - **Considered but not used:** a third-party 0.5B "survival" fine-tune. It is English-only and writes unreviewed advice.
- **Technologies and frameworks:**
  - **App:** Swift / SwiftUI (iOS 17) with CoreLocation, Vision, Speech, AVFoundation, PhotosUI, CryptoKit and Network; XcodeGen.
  - **AI runtime:** the llama.cpp b11429 iOS XCFramework (MIT), with GBNF grammars.
  - **Data preparation:** Python 3 scripts for map data, help cards, keywords and hotlines.
  - **CI:** GitHub Actions.
  - **Launch film:** Remotion (React) and FFmpeg, with the Inter font (SIL OFL).
- **APIs and cloud services:**
  - **In the app:** none.
  - **Build or prep time only:**
    - OpenStreetMap via Overpass API mirrors (ODbL; attribution shown in the app)
    - Hugging Face and GitHub for pinned downloads
    - GitHub Actions for CI
    - Mixkit and Pexels for the launch film's music and stock clips (Mixkit Free License, Pexels License)
- **Existing code and assets:**
  - **No app code predates the hackathon.** The first commit is 2026-10-09 15:14 +08:00.
  - **Prepared beforehand in ChatGPT conversations:** the product brief and build reference, the brand guide, a static UI board (`design/`) and the cat mascot art (`assets/mascot/`). These were AI-generated from the founder's direction.
  - **Third-party:**
    - OSM data (ODbL)
    - help-card content paraphrased from NHS, St John Ambulance, WHO, the AA, GOV.UK and other linked public sources (each card links its source)
    - hotline numbers from official LGU, agency and operator pages; SLEX/Skyway/STAR/TPLEX come from one news report and are labelled as such
    - launch-film music "Just Keep Walking" by Michael Ramir C. and two stock clips (Mixkit Free License; Pexels License)
    - llama.cpp and Qwen, used unmodified
- **AI development tools:**
  - **ChatGPT / Codex:** planning, briefs and mascot images before the build.
  - **Claude Code (Anthropic):** implementation of the app, core library, scripts, tests, docs, marketing mockups and the launch film during the hackathon.
  - **FOUNDER:** add any other tool used (e.g. Devin). Do not omit any.

## Why does this product benefit from running AI locally?

Life Off Desk is used *outside*, on foot, where the cloud is least reliable and most intrusive:

1. **It must work with no signal or data.** Walkers in Metro Manila move through areas with weak signal, and many users ration mobile data. The planner, history search and recaps run fully offline, so the app works at the moment you decide to go out.
2. **Location history is sensitive.** A record of where someone walks every day is about as private as data gets. Keeping the model, the trail, the photos and the preferences on the phone means none of it is ever sent anywhere: no account, no server, nothing to breach.
3. **It's instant and free per request.** Every Taglish question costs nothing per query, and nothing waits on a round trip, which matters for a free consumer app nudging people to take a 30-minute break.
4. **Local AI stays honest.** The small on-device model only *interprets* the request (Taglish → validated JSON). Search, distances, maps and every number come from deterministic code over bundled data, so the AI cannot invent places, hours or routes. Unknown accessibility is shown as unknown, never guessed.

## Evidence and honesty notes (avoid "fake benchmarks")

- Core logic: 165 automated tests (Swift) and 15 Python tests, run in CI on every push.
- Help-chat routing, keywords only (no model): two held-out sets, 126/126 and 60/60 with 0 missed emergencies after fixes. Both sets have now been seen. Combined AI + keyword accuracy on the phone has not been measured.
- Model accuracy numbers in `docs/BUILD-STATUS.md` are **development-machine (Linux CPU) runs**, labelled as such: planner v5 held-out 60/60 valid, 46/60 intent; history 14/14 valid, 10/14; recap 12/12; adaptive 14/14 valid, 10/14. They are not phone measurements.
- Phone: the founder reported all six iPhone 12 Pro Max checks working (offline AI, outdoor walk, camera/sticker, accessibility, edge cases). **No phone latency/memory numbers have been recorded yet.** If you quote speed in the pitch, read it live from Settings → AI diagnostics and say it was measured then.
- Sample/demo adventures are synthetic and labelled "SAMPLE DATA" in the app.

## Judges: recreate it

See the README "Start on your Mac": `brew install xcodegen`, `scripts/setup_ios.sh` (downloads ≈1.34 GB, checksum-verified), open the project, set a signing team, run on an iPhone (the pinned runtime has no Simulator slice; the Simulator build shows every screen but AI says it is unavailable). Core tests: `swift test --package-path Packages/LifeOffDeskCore`.

## Demo plan (5 min live + 3 min Q&A)

Phone in **Airplane Mode** the whole time, mirrored over HDMI/USB-C.

1. (0:00–0:30) Problem and user: desk workers who never leave the building; one line on why local (offline, private).
2. (0:30–1:45) Map tab: show the explored paper map (Settings → Demo map, labelled sample data) vs a blank map. Tap ✨, type *"tahimik na park, 30 mins lang"*, get real places with "km by streets" and honest caveats. Point at the Airplane Mode icon.
3. (1:45–2:45) Start exploring: short walk or a recorded adventure. Show the inked trail, new streets, recap, Taglish recap ("AI-selected highlights · values computed"), make a card.
4. (2:45–3:45) Adventures tab (searches your **real** saved adventures, not sample data, so record a couple of adventures first): search *"adventures this week"* or *"mga lakad ko ngayong araw"* → filter chips → results. Avoid "last week" if all your walks are this week, and avoid "short walks … last week" (it asked for clarification in the dev test). Settings → preferences.
5. (3:45–4:30) Honesty and safety: ask for a wheelchair-accessible museum → honest "no reviewed record" state. Settings → AI diagnostics: model, hash, load time, offline network path.
6. (4:30–5:00) Why local AI wins, and what's next (more city packs, reviewed accessibility facts).

Rehearse every typed phrase on the phone first. Known weak phrasings (dev tests): "hindi ko pa napupuntahan" may not be read as "somewhere new"; "long walks" may become a sort; "first ever adventure" asks for a date. Time two or three requests in rehearsal; no phone latency has been recorded yet.

Backups: a pre-recorded 1-minute video on the laptop, demo mode for a populated map, and the model loaded once before going on stage (Settings → AI diagnostics → Load model now).

## Final checklist before 10:00 AM

- [ ] FOUNDER fills team member names (official list) and the extra AI tools.
- [ ] Record the ~1 min demo video on the phone (Airplane Mode visible).
- [ ] Post it on X or LinkedIn tagging Devin / Cognition with #AppBuildersPH; paste the URL.
- [ ] Optional: copy the AI diagnostics JSON from the phone into `docs/BUILD-STATUS.md` (real latency numbers) before the freeze.
- [ ] Confirm the repo is public (it is as of 2026-10-09) and `main` holds the final build.
- [ ] Submit once on Cerebral Valley; answers above are paste-ready.
