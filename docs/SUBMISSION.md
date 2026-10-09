# Submission pack — AppBuildersPH Hackathon 2026 (Local AI)

Deadline **10:00 AM, October 10, 2026 (Asia/Manila)** on https://cerebralvalley.ai/e/appbuildersph-hackathon-2026. One submission only, no edits, code freezes at 10:00 AM (judges review the repository as of the deadline). Repository: https://github.com/lewisjohnvillamor/Lifeoffdesk (public).

Fields marked **FOUNDER** must be filled by the team; nothing here is invented on their behalf.

## The project

- **Project name:** Life Off Desk
- **Short description:** An offline iPhone app that gets you off your desk and exploring. Ask in Taglish ("tahimik na park, 30 mins lang") and an on-device LLM turns it into a search over real local places; walk, and a paper-map fog reveals the streets you actually covered. It also searches your past adventures and writes grounded Taglish recaps, all without the cloud.
- **Team members:** **FOUNDER** — names exactly as listed on appbuildersph.com/hackathon.
- **Public GitHub repository:** https://github.com/lewisjohnvillamor/Lifeoffdesk

## The proof

- **Demo video (~1 minute):** **FOUNDER** — record on the iPhone 12 Pro Max in Airplane Mode (suggested shot list below).
- **X / LinkedIn video URL:** **FOUNDER** — post must tag Devin / Cognition and include **#AppBuildersPH**.
- **What runs locally (on the iPhone, offline):**
  - Qwen3-1.7B (Q4_K_M GGUF) through llama.cpp b11429 compiled into the app (Metal): Taglish planner intent extraction, history-search filter extraction and recap highlight selection, each grammar-constrained and validated.
  - Apple Vision `VNGenerateForegroundInstanceMaskRequest` for the photo-sticker cut-out.
  - Deterministic engines: place search and ranking, street-distance shortest paths over bundled OpenStreetMap streets, GPS filtering and street matching, fog-of-war exploration, history search, recap facts, accessibility eligibility.
  - All data: bundled OSM map/place packs (Makati CBD, Muntinlupa, Metro Manila main roads), walks, photos, preferences and AI caches, stored only on the device. No account.
- **What requires internet:** nothing at runtime. The app makes no network calls. Internet is only needed **before** use: downloading the model and runtime once at build time (Hugging Face, GitHub releases; checksum-verified), and preparing map data at build time (OSM via an Overpass mirror). GPS works without data.

## The disclosures

- **Models used:** Qwen3-1.7B Q4_K_M GGUF (ggml-org quantization of Qwen3, Apache-2.0), pinned in `config/materials-lock.json`, SHA-256 `d2387ca2…b7b5`. Qwen3-0.6B Q4_0 was evaluated earlier and is no longer used. Apple Vision (system framework, on-device).
- **Technologies and frameworks:** Swift 5/SwiftUI (iOS 17), llama.cpp b11429 iOS XCFramework (MIT), CoreLocation, Vision, PhotosUI, CryptoKit, Network, XcodeGen (MIT); Python 3 scripts for data preparation; GitHub Actions (macOS runners) for CI builds, tests and Simulator screenshots.
- **APIs and cloud services:** none in the app. Build-time only: OpenStreetMap data via Overpass API mirrors (ODbL; attribution shown in-app), Hugging Face and GitHub for pinned downloads, GitHub Actions for CI.
- **Existing code and assets:** no application code predates the hackathon (first commit 2026-10-09 15:14 +08:00, after building began). Pre-existing **planning material and assets** are disclosed: the product brief/ICP and build reference (`Life-Off-Desk-*.txt`), the brand guide, a static UI board (`design/`) and the cat mascot artwork (`assets/mascot/`) were prepared beforehand in ChatGPT conversations (AI-generated from the founder's visual direction). Open-source llama.cpp and the Qwen model are used unmodified. OSM data is third-party (ODbL).
- **AI development tools:** ChatGPT / Codex (planning, briefs, mascot images), Claude Code by Anthropic (implementation of the app, core library, scripts, tests and docs during the hackathon). **FOUNDER:** add any other tools used (e.g. Devin) — do not omit any.

## Why does this product benefit from running AI locally?

Life Off Desk is used *outside*, on foot, where the cloud is least reliable and most intrusive:

1. **It must work with no signal or data.** Walkers in Metro Manila move through areas with weak signal, and many users ration mobile data. The planner, history search and recaps run fully offline, so the app works at the moment you decide to go out.
2. **Location history is sensitive.** A record of where someone walks every day is about as private as data gets. Keeping the model, the trail, the photos and the preferences on the phone means none of it is ever sent anywhere: no account, no server, nothing to breach.
3. **It's instant and free per request.** Every Taglish question costs nothing per query, and nothing waits on a round trip, which matters for a free consumer app nudging people to take a 30-minute break.
4. **Local AI stays honest.** The small on-device model only *interprets* the request (Taglish → validated JSON). Search, distances, maps and every number come from deterministic code over bundled data, so the AI cannot invent places, hours or routes. Unknown accessibility is shown as unknown, never guessed.

## Evidence and honesty notes (avoid "fake benchmarks")

- Core logic: 114 automated tests (Swift) + 11 Python tests, run in CI on every push.
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
