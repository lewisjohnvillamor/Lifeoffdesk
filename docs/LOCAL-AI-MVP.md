# Local AI MVP expansion — Claude implementation handoff

Decision: 2026-10-09. Founder approved all four capabilities below as MVP work. **Specification only; implementation and device acceptance remain pending.** Preserve the original walking and planner P0 gates. Other AI ideas remain follow-up work.

## Model and execution contract

Use the selected **Qwen3-1.7B-Q4_K_M.gguf**, llama.cpp b11429 and the pinned artifacts in [materials-lock.json](../config/materials-lock.json). Model SHA-256: `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`. Recorded model size is approximately 1,282,439,264 bytes; this is disk size, not peak RAM. The previous 0.6B evaluations remain historical evidence, not the current selection or evidence of 1.7B phone quality.

At handoff, `main` is `55d67ba`; local edits already select 1.7B in `AIService.swift` and `project.yml`. Preserve those edits. The default downloader/setup still provisions the legacy `model` group. Align download defaults, resource path, runtime filename/hash and diagnostics before claiming a clean-install build works. Until then use the explicit `model-large` download in [Mac setup](MAC-SETUP.md). Do not silently fall back to another model or cloud inference.

Introduce one inference coordinator around the existing engine: single-flight model loading, one generation at a time, task IDs, cancellation and a generation epoch invalidated by unload/erase. Actor isolation alone is insufficient if generation yields while sharing a native context. A stale load/generation must not update state after cancellation or overwrite a newer request. Walking starts immediately; cancel pending AI and release model resources safely after active native work stops. No continuous background inference. Keep current bounded context/output settings until real-device measurements justify changing them.

Each task has its own small schema, prompt and constrained grammar. Validate exact keys, enums, lengths, bounds and referenced IDs after decoding. Reject extra fields, unsupported facts and invalid candidate IDs. Permit at most one bounded repair, then show retry/manual controls with the original input intact. Never execute model-generated SQL, paths, predicates or tools. Treat user text and catalog labels as untrusted data.

## P0-12: natural-language adventure-history search

User example: “Mga short walks ko last week na may photos.” Real local inference extracts filters; deterministic code queries saved adventures.

- Proposed `HistoryQueryV1`: `period` enum (`all`, `today`, `yesterday`, `thisWeek`, `lastWeek`, `thisMonth`, `custom`), optional ISO date range for custom, `maxActiveMinutes?`, `hasPhotos?`, bounded category enums, `sort` (`newest`, `oldest`, `longest`), `limit` 1–20 and `needsClarification`. Reject unsupported interpretations rather than invent filters. Ask for clarification for ambiguous dates.
- Resolve relative dates in app code using a captured reference date, timezone and documented Monday week start. Use half-open intervals; test month/year boundaries and timezone changes. Duration comes from stored/computed active duration. Search only real local records; explicitly labeled demo data stays separate.
- Category searches can use catalog places **passed near**, with the existing proximity rule recorded in the index. A 40 m proximity association is not proof of a visit or preference. Label it accordingly; do not infer venue entry from GPS.
- Build a lightweight in-memory index from persisted adventure summaries off the main thread. Return session IDs with deterministic sort/tie-breaks. Rebuild/invalidate after save, delete or migration. No embeddings/vector database required for this slice.
- UI: a search entry in Adventures, visible filter chips and clear/reset. Empty history and zero matches are valid results. Model unavailable leaves ordinary history and manual filters usable.

## P0-13: grounded recap narration

User example: reopen an adventure and request a short Taglish recap. Save the completed walk before offering AI; inference never blocks Finish or persistence.

- Compute a versioned `RecapFacts` snapshot from accepted samples and chronological exploration state: active duration, tracked distance, supported discovery metrics and IDs of places passed near. Omit unavailable facts. Never let the model calculate distance, calories, routes or discoveries.
- For MVP, the model selects up to three supplied fact IDs plus an approved tone/template enum. A deterministic renderer inserts the values and localized Taglish phrases. This creates a bounded narrative without allowing free prose to introduce a venue visit, safety claim or numerical error. Describe this honestly as AI-selected narration with grounded templates.
- Validate fact membership and compatible templates. An invalid output cannot reach the saved/shareable recap. Ordinary computed recap remains the fallback, explicitly distinguishable from a successful AI result.
- Cache by session ID, facts hash, schema/prompt/model version and language. Reopening need not rerun the model. Invalidate when the source record changes; deletion/erase removes cached outputs and prevents in-flight regeneration. Historical metrics must not change merely because a later adventure explored the same street.

## P0-14: editable preference memory

- Add a separate versioned `PreferenceProfile` with optional category choices, outing duration, radius, novelty preference and language. A small Settings editor supports view, edit, reset and an explicit “Save these preferences” action from planner results.
- Keep extracted preferences ephemeral until the user confirms saving. Do not infer disability, health status, identity or personality from routes/photos. Optional functional access requirements may be saved only through explicit user choice; explain they remain local and can be removed.
- Precedence: explicit current request > explicitly saved soft preferences > optional deterministic history signals > defaults. Hard access requirements remain active until the user explicitly changes them; ambiguous contradictory text requires clarification.
- Version and atomically persist the profile with recovery. Missing legacy profile means no saved preferences. Unknown schema versions must be preserved, not overwritten with defaults. Failed writes show unsaved state. Erase clears preferences, caches and derived history alongside walks.

## P0-15: adaptive suggestions

- Extend the existing planner with explicit novelty intent (“somewhere new”, “something familiar”) and saved preferences. Deterministic code generates, filters and ranks catalog or exploration candidates using supported facts, coverage and prior accepted exploration.
- Apply hard constraints and the [accessibility evidence policy](ACCESSIBILITY-AND-SAFETY.md) before ranking. A model cannot relax a requirement to fill three cards. Zero eligible candidates produces a useful empty state and an explicit option to change filters.
- AI can select valid intent/reason enums; optionally select from a bounded supplied candidate-ID list. Validate membership and rerun eligibility before display. Distance, novelty and factual reasons are calculated by code. Prefer no extra model call when intent extraction already supplies everything needed.
- Passing near a place is not liking it. Explicit user choices may influence suggestions; any optional behavioral signal must be explainable and resettable. No unexplained “you love this” claims.
- Keep up to three results. Label straight-line distance; no walking ETA, route accessibility or promise of safety. Unsupported route-level requests get an explanation and an optional venue-only filter, requiring the user's choice.

## Integration order and ownership

1. Align 1.7B provisioning and prove offline inference on the actual iPhone 12 Pro Max. Fix shared inference lifecycle before adding more task types.
2. Add pure Swift contracts, validators and deterministic history/recap services in `Packages/LifeOffDeskCore`. Add evidence types/policy there independently of GPS matching. Proposed files: `HistoryQuery.swift`, `RecapFacts.swift`, `PreferenceProfile.swift`, `PlaceEvidence.swift`, `EligibilityPolicy.swift` (names are proposals, not existing implementations).
3. Deliver history search and grounded narration first; then preference persistence/editor and adaptive ranking. Add task-specific prompts/grammars beside the existing AI service, and integrate UI through one owner of `AppModel`.
4. Coordinate with Claude's GPS branch before modifying `RoadContext`, road pack builders, `AdventureSuggester` or map/trace rendering. Agree stable segment IDs and metadata preservation. Do not merge an unfinished branch merely to enable these features.
5. Before adding persistent AI state, cover existing recovery risks: backup-only records, unknown schema preservation and Finish write failure retaining recoverable session state. Test against the integrated branch; do not assume earlier findings remain unchanged.
6. Complete the acceptance matrix below and update [build status](BUILD-STATUS.md). Reserve the final 20% of the actual available time for verification/demo. The old eight-hour allocation does not establish that this expanded scope fits; report unfinished P0 honestly.

Schema changes must update Codable migration/defaults, strict validator keys, prompt examples, grammar, fixtures and diagnostics together. Avoid adding every task field to `OutingPreferences`; use separate versioned contracts.

## Acceptance and evaluation

| Area | Required evidence |
| --- | --- |
| History | Correct dates, duration/photo/category filters, stable ordering, empty results, deletion invalidation, no fixture leakage; clarify unsupported requests |
| Recap | Exact source values and valid IDs, no invented visits/facts, stable historical metrics, no blocking Finish, cache invalidation and offline reopen |
| Preferences | Explicit save/edit/reset, precedence and hard-constraint conflict, relaunch, failed-write recovery, unknown schema preservation and erase |
| Adaptation | Deterministic novelty, candidate membership, zero-match behavior, no silent constraint relaxation and honest reasons |
| Evidence | Missing, negative, limited, stale, conflicting and wrong-scope facts never pass a hard positive requirement; restricted candidates excluded |
| Runtime | Concurrent requests, cancel/unload/reload, start walking during load/generation and erase during inference cause no stale write or native-context race |

Prepare at least 12 fresh held-out English/Taglish prompts per capability, including ambiguous and unsupported requests; keep parser accuracy separate from 100% schema-validity claims. Add hostile text and fabricated IDs. Deterministic tests alone cannot establish model comprehension.

On the target phone, record model hash, runtime, build commit, iOS, cold load, cold/warm response latency (p50/p95 with sample count), memory/thermal observations and cancellation responsiveness. Do not invent pass thresholds after seeing results: agree a usable latency budget before declaring performance accepted. Test with airplane mode, Wi-Fi off, Mac disconnected and all materials pre-provisioned. Include actual outdoor walking and local erase/relaunch. Simulator/manual fallbacks do not pass the local-AI gate.

## Follow-up only

Open-ended chat, voice interaction, image understanding, automatic journaling, inferred sensitive profiles, embeddings over large personal archives, live hazard advice and generated routes are outside this expansion. They need separate approval and evidence.
