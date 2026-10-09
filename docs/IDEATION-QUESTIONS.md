# Life Off Desk — decisions and remaining questions

## Confirmed

- Brand: Life Off Desk; personal male cat mascot; ivory/forest/sage visual direction.
- Platform: native iPhone; first device iPhone 12 Pro Max; Apple silicon Mac with Xcode ready.
- Core interaction: map-first entry; exploration through actual movement; optional-to-use chat.
- Both fog-of-war walking and AI suggestions are must-have MVP features.
- Starter city: Makati. Planner language: Taglish. Event link is confirmed in HACKATHON.md.
- AI must execute on the iPhone; a phone-to-Mac server is not accepted as the main implementation.
- Offline-first, private and no mandatory account. Initial market Luzon; first detailed region intentionally small.

## Questions that still affect this build

1. **Exact cutoff and Local AI track:** The event link is confirmed; see HACKATHON.md. What submission cutoff/track requirements did the kickoff briefing provide? The public page does not specify them.
2. **Exact walk segment:** Makati is confirmed. The starter download uses a proposed CBD bounding box; choose a short outdoor segment suitable for the actual demonstration and validate its geometry/places.
3. **Phone version/signing:** What iOS version is installed, and does a signed test app launch? Xcode readiness is confirmed; a device launch still needs proof.

Confirmed language: Taglish planner input and concise Taglish responses. Include English control prompts in evaluation to support natural code switching.

## Product choices worth settling before a wider release

- What should count as exploration: walking only, cycling, transit or any movement? Starting assumption: deliberate walking sessions.
- Should AI suggestions be allowed to show undiscovered places through the fog? Starting proposal: show a destination marker after selection; surrounding map stays hidden.
- Is the first promise “help me go outside” or “collect my personal map”? Proposed positioning joins them through one short outing; avoid unrelated productivity features.
- Do we need import from previous walking apps? Proposed answer for day one: no import; keep it on the roadmap if switching friction matters.
- How should exploration near home be treated in exported images? Proposed answer: exports are opt-in; avoid revealing precise home coordinates in public demos.
- How should backup/export work before real personal memories accumulate? Proposed P1 local export; no cloud-sync promise yet.
- Who are the first 3–5 testers, and what outing behavior would count as value? Interview recruitment and retention targets remain unvalidated.
- What is the mascot's name? Optional ideation; it does not block functional work.
- Monetization, recurring costs and model/map updates: decide after proof of use, with transparent download sizes and licenses.

## Proposed success measures

For the build: both P0 paths complete offline on the actual phone and results persist. For early user testing: time from open to first walk, whether the suggestion helps someone choose, number of completed voluntary outings, and whether users return to their map. Do not present sample metrics as measured retention or market validation.

Record each new decision with date, owner and reason; update MVP-FEATURES.md rather than appending competing requirements indefinitely.
