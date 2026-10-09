# Materials and tool disclosure

- Planning assistance: ChatGPT/Codex; project plans, reference board and mascot stickers came from the conversation. Reference images were AI-generated using the founder's supplied visual direction/personal cat. Original personal photos are excluded from this repository.
- App implementation: Swift/SwiftUI source written 2026-10-09 with Claude Code (Anthropic) during the hackathon. It has not yet been built in Xcode, installed on the iPhone, or tested outdoors; see docs/BUILD-STATUS.md.
- Build tooling: XcodeGen (MIT) generates the Xcode project from LifeOffDesk/project.yml; not vendored.
- Candidate engine: llama.cpp from ggml-org, MIT; preserve upstream license/notices with distribution. Pinned release downloads are listed in config/materials-lock.json.
- Candidate model: Qwen3-0.6B GGUF, ggml-org quantization of Qwen, Apache-2.0 metadata. Preserve upstream model license/notices and provenance before distribution. Listing: https://huggingface.co/ggml-org/Qwen3-0.6B-GGUF .
- Map/place data: OpenStreetMap contributors, ODbL. The bundled LifeOffDesk/Resources/StarterData/*.json files are a derived database of OSM data (retrieved 2026-10-09 via the overpass.private.coffee Overpass mirror) and are made available under ODbL with attribution shown in the app. Preparation script records source IDs/URLs, retrieval date and attribution. Source tags do not establish real-time access, hours or prices. Distribution/derived database obligations must be checked before release: https://www.openstreetmap.org/copyright .
- Figma: previous file remains unrevised; included update script is unapplied and runtime-untested. Latest static image is an illustrative reference.

Some planning/reference work predates the final repository handoff. Disclose earlier material and confirm event eligibility; follow the exact organizer requirements in docs/HACKATHON.md. Add actual dependency versions and any additional AI tools used during implementation.
