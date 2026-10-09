---
name: life-off-desk-local-ai
description: Implement, benchmark or review genuine on-device AI outing suggestions in Life Off Desk. Use for iPhone 12 Pro Max inference, natural-language preference extraction, grounded local place search, offline validation and model/runtime feasibility; a Mac server is not the accepted primary demo.
---

# Life Off Desk Local AI

Read `references/build-contract.md`. Inspect actual model/runtime availability and current official documentation; pin version, artifact provenance and checksum. Never claim phone compatibility or latency from a Mac benchmark.

1. Prove actual iPhone inference first, with airplane mode on, Wi-Fi off and Mac disconnected. Download provisioning artifacts beforehand. Record model bytes, cold load, warm latency and memory if measurable.
2. Start with a small compatible GGUF candidate through pinned llama.cpp iOS integration. Treat Qwen3-0.6B as a candidate, not a measured winner. Use short context/output and the correct chat template; adjust from evidence.
3. Extract bounded typed preferences for time, budget, categories, mood and walking. Validate types/enums/ranges; treat missing facts as unknown. Use constrained output if supported. Permit at most one bounded repair before clear retry/manual filters.
4. Query a real, provenance-bearing bundled catalog in app code. Compute distances and rank deterministically. Model output must not invent place names, hours, prices, quietness or roads. Unknown price cannot satisfy a strict budget ceiling.
5. Render up to three actual records with reason and uncertainty. Selected place becomes a destination marker; straight-line distance is not walking distance or an ETA.
6. Handle loading/cancel/no match/failure without losing prompt or blocking walking. Run inference on demand outside the UI thread. Manual filters are fallback usability, not evidence of AI.
7. Evaluate at least ten representative cases including ambiguous English/Taglish if required, unsupported venue facts and injected instructions. Report intent errors separately from valid JSON; do not claim production accuracy.

If phone inference fails inside the early budget, try one compatible smaller artifact or lower context. Report remaining blocker and incomplete P0 status; do not secretly substitute a Mac server, canned answers or rules. Verify both planning and walking offline before declaring completion.

Current repository decisions: Makati starter city, required Taglish planner. Read docs/HACKATHON.md and docs/MAC-SETUP.md when preparing the build. Project docs override the dated portable contract snapshot.
