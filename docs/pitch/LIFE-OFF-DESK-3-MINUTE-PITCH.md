# Life Off Desk — three-minute pitch script

Target runtime: **2:45–2:55**, leaving a few seconds for slide transitions.

## Slide 1 — Problem identification · 0:00–0:25

“Most desk workers know they should step out. The hard part is deciding where to go when they only have thirty minutes and little energy left. Life Off Desk is for that moment: a private iPhone companion that makes the world beyond your desk feel easier to enter, even when there is no signal.”

## Slide 2 — Solution · 0:25–0:55

“You can ask naturally in Taglish—‘Tahimik na park, thirty minutes lang.’ The app finds grounded local options, tracks the real walk, reveals only the streets you covered, then saves the route, photos, and an honest recap. The AI interprets the request. Deterministic code verifies every place, distance, route decision, and number.”

## Slide 3 — ICP · 0:55–1:15

“Our initial customer is a Metro Manila desk worker: developers, freelancers, and hybrid teams looking for a low-effort fifteen-to-sixty-minute break. They want novelty without spending time planning, using mobile data, or uploading sensitive location history.”

## Slide 4 — Technical implementation · 1:15–1:50

“Everything important runs on the phone. Core Location records movement. A quantized Qwen3 1.7B model through llama.cpp converts Taglish into constrained JSON. Swift engines then search bundled place and street data, enforce accessibility rules, calculate statistics, and persist the walk. There is no backend, account, or cloud inference. If AI is unavailable, walking, maps, history, and safety guidance still work.”

## Slide 5 — Phone proof and limitation · 1:50–2:25

“We ran sixty held-out requests on an iPhone 12 Pro Max in Airplane Mode. All sixty returned valid schemas; forty-seven passed intent evaluation. Model load was 1.59 seconds, median generation 7.38 seconds, p95 8.84 seconds, with a 532 MiB peak footprint. The sustained run moved from serious to critical thermal state, so this design fits short, purposeful requests—not continuous generation. Battery impact still needs a controlled unplugged run.”

## Slide 6 — Future direction · 2:25–2:55

“Next we will instrument outdoor GPS and street snapping, add export and compact history indexes, and review accessibility evidence before expanding city packs. The aim is a trusted city companion that keeps location history private and grows through real movement. A little walk can create a bigger world.”

## Evidence notes

- Phone source: `eval/results/taglish-heldout-iphone12promax-airplane-2026-10-10.json`.
- The phone was charging at 65% throughout, so this run does not establish battery consumption.
- The 60 requests were a sustained stress-style sequence; ordinary use is expected to be much shorter, but that expectation still needs measurement.
- “Intent pass” uses the repository’s held-out expected intents. Schema validity does not imply perfect interpretation.
- Architecture details: `docs/TECHNICAL-ARCHITECTURE-REVIEW.md`.
