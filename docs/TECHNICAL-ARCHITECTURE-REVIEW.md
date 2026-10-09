# Life Off Desk technical architecture review

**Review date:** 2026-10-10  
**Scope:** current `main` checkout, iPhone application, local datasets, and local AI runtime  
**Target device:** iPhone 12 Pro Max  
**Architecture image:** [SVG](architecture/lifeoffdesk-system-architecture.svg) · [PNG](architecture/lifeoffdesk-system-architecture.png)

## Executive assessment

Life Off Desk is an offline-first, single-device iPhone app. SwiftUI presents a map-first experience while `AppModel`, an `@MainActor` composition root, coordinates walk sessions, streamed region data, deterministic recommendations, persistence, and an optional local language model. There is no application backend, account system, cloud inference, or remote source of truth.

The separation between AI and authoritative app logic is the strongest architectural decision. The language model produces small, constrained JSON decisions. Deterministic code validates those decisions, searches the place catalog, computes walk facts, renders safety guidance, and owns all GPS, distance, routing, and persistence behavior. If the model is unavailable, the core walking and history experience remains usable.

The greatest near-term resource cost is the 1.7B local model. The greatest long-term scaling risk is loading and recomputing an ever-growing local walk history and its geometry. The most serious durability gap is device loss: atomic writes and `.bak` files protect against interrupted local writes, but they are not disaster recovery.

## System shape

| Layer | Current responsibility |
|---|---|
| Product UI | SwiftUI map, planner, adventure history, recap, help, and preferences |
| App coordination | `AppModel` owns screen state and connects services on the main actor |
| Walk pipeline | Core Location → fix filtering → session state → street context/reveal → computed statistics |
| Map pipeline | Region packs → chunk demand → off-main decode/graph build → Canvas map with cached/simplified geometry |
| AI pipeline | Prompt/input → serialized llama.cpp inference → grammar/schema validation → deterministic execution/rendering |
| Local content | OSM-derived road/place packs, evidence metadata, safety cards, lexicon, and labeled demo data |
| Personal data | Versioned JSON files and photos under Application Support with atomic writes and backup recovery |
| Platform | CoreLocation, SwiftUI/Canvas, UIKit, Speech, Vision, and CryptoKit |

The region library loads primary and context packs first, then asks for nearby packs using viewport, current location, destination, and history demand. Street-network and walking-graph construction happen off the main thread. A generation counter prevents an older graph build from replacing a newer one.

## Where AI is used

| Capability | AI responsibility | Deterministic responsibility | Fallback |
|---|---|---|---|
| Planner | Extract bounded Taglish/English intent | Filter and rank the local catalog; apply hard constraints | Manual filters and catalog results |
| Adventure history search | Produce a validated query/filter object | Search saved walks and compute matches | Standard history browsing/filtering |
| Recap narration | Select allowed fact/template IDs | Compute every number and render the final sentence | Computed recap copy |
| World coach | Select computed facts, tone, and an offered quest | Supply candidates and render templates | Deterministic insight cards |
| “Para sa’yo” | Pick one precomputed candidate and reason IDs | Build shortlist, enforce constraints, cross-check the result | Highest deterministic candidate |
| Safety help | Select a bundled topic and an emergency flag | Keyword layer can raise urgency; bundled sourced card supplies all advice | Keywords and cards work without the model |
| Speech input | Apple’s on-device speech recognition transcribes input | App routes the resulting text | Typing |
| Photo context | Apple Vision supplies broad object labels | App stores/uses labels as context only | No label; never treated as a diagnosis |

AI does **not** determine whether a GPS fix is valid, calculate distance or duration, decide route reachability, write medical advice, bypass accessibility constraints, or become the source of persisted truth.

### How the local model is maximized safely

- One `InferenceCoordinator` serializes generation and prevents duplicate model loads.
- The planner can preload the model while region content loads in parallel.
- A shared prompt prefix permits KV-cache reuse; the recorded development optimization reduced the same six-request CPU run from about 27 seconds to about 10 seconds without changing its six outputs.
- GBNF grammars, schema validation, enum/bounds checks, and one repair attempt keep output small and machine-checkable.
- Candidate and fact IDs limit the model to information already computed by the app.
- Cancellation epochs prevent a late response from updating UI after cancellation or unload.
- The model unloads before a walk and under memory pressure, reserving resources for tracking and map rendering.

Reducing the model, context, or prompt further should follow a repeatable device-quality evaluation. A faster response that changes intent accuracy or safety routing is not an architectural win.

## Cost and failure analysis

### 1. Highest resource cost: local inference

The selected `Qwen3-1.7B-Q4_K_M.gguf` file is **1,282,439,264 bytes** (about 1,223 MiB). The app’s preflight asks for the model size plus **700 MiB** of available-memory headroom, about **1.88 GiB total**. This is a conservative admission gate; it is not a measured peak resident-memory figure.

Likely failure symptoms are model load rejection, long cold-start latency, memory-pressure unload, thermal slowdown, or cancellation lag. The exact iPhone 12 Pro Max breakpoint is still unknown because cold-load time, peak memory, p50/p95 generation latency, tokens per second, temperature, and energy have not been formally captured on that phone.

Containment already exists: inference is optional, serialized, cancelable, retried after a failed load, and removed from memory during the walk. Manual and computed paths preserve the main product.

### 2. Highest scale cost: accumulated walk history

Walks are stored as individual JSON files and location updates can arrive at about one fix per second. History and derived statistics are decoded/recomputed in memory. As a scale illustration rather than a measured limit, 365 thirty-minute walks would contain roughly 657,000 raw fixes before filtering or thinning. The actual point at which launch or recap performance becomes unacceptable has not been measured.

Recommended early fix:

1. Write a compact summary/index for list, profile, and aggregate statistics.
2. Load full track coordinates only when a walk detail or map requires them.
3. Thin saved tracks by a documented geometric error bound while retaining raw active-session recovery.
4. Cache monthly/yearly aggregates and invalidate them when a walk changes.

### 3. Highest rendering cost: revealed-world geometry

A prior demo with **84 walks**, about **217 km**, and roughly **400,000 fog/island vertices** caused map pan and replay lag. The implementation now simplifies each line with Douglas–Peucker, strokes once per walk, caches island geometry, culls visible tiles, and skips the blurred shadow at distant zoom levels. This is an observed failure mode with a code mitigation; smoothness on the target phone remains unverified.

### 4. Dataset and graph growth

The current checkout contains **89,294 road records**, **26,934 place records**, and **26.58 MiB** of region data across the demo and starter packs. Chunk streaming and idle eviction constrain the working set, while detached graph builds protect the main thread. Loading several dense adjacent cities can still create decode, allocation, and Dijkstra-style route-search spikes. Add signposts around pack decode, graph construction, node/edge counts, route search, and eviction before expanding the geography.

### 5. Correctness at the edge of map knowledge

OSM-derived records can be incomplete or stale. Private/no-access roads are penalized and motorways are excluded, but the app does not provide live closures, traffic, turn-by-turn navigation, or guaranteed accessible paths. A graph-valid route can still be impractical in the real world. The UI must keep uncertainty visible, and unreviewed opening-hours/access claims must not be promoted to verified facts.

## Redundancy and fail-safes

| Failure | Existing containment | Residual risk |
|---|---|---|
| Invalid or implausible GPS | Reject inaccurate, stale, future, non-increasing, and implausible fixes; split segments across gaps | Urban canyon drift and wrong-street context still require outdoor testing |
| App termination during a walk | Active checkpoint; recovery returns paused and never silently resumes | Last updates since the most recent checkpoint may be absent |
| Interrupted/corrupt write | Temp file, atomic replace, `.bak`, schema checks, corrupt-file quarantine | Backup is on the same device |
| Crash while completing a walk | Persist completed walk before clearing active state | A retry can duplicate rather than lose a walk |
| Model missing or load failure | Visible unavailable state; retry next request; deterministic/manual paths | Reduced convenience and narration |
| Memory warning or walk start | Cancel generation and unload model | Subsequent AI use pays cold-load cost |
| Malformed AI JSON | Grammar, schema, enum/bounds validation, one repair attempt | A valid but poor choice can remain; deterministic cross-checks limit impact |
| Late AI response | Request IDs and cancellation epoch discard stale output | Generation may consume time before cancellation completes |
| Disconnected/missing street graph | Labeled straight-line fallback | Straight-line context is not a verified walking route |
| Safety model mistake | Keyword detection can only raise urgency; advice comes from bundled cards | Held-out coverage is finite and requires ongoing review |
| Speech/Vision unavailable | Typed input and no-label behavior | Less contextual input |
| Device loss | None beyond local files | All personal history can be lost; export/backup is needed |

## Benchmark evidence

Benchmark labels matter because a Mac CPU result does not prove iPhone performance.

| Evidence | Result | Environment / limitation |
|---|---|---|
| Core package suite, this review | **158 tests passed, 0 failures, 22.006 s** | Development Mac; logic tests, not UI/device performance |
| Planner v5 held-out set | **60/60 schema-valid; 46/60 intent pass** | Development-machine CPU evaluation |
| Adaptive suggestions | **14/14 schema-valid; 10/14 intent pass; ~25 s/request** | Development-machine CPU evaluation |
| History query | **14/14 schema-valid; 10/14 pass; ~18–21 s/request** | Development-machine CPU evaluation |
| Recap narration | **12/12 valid fact-ID selections** | Validity check, not prose preference scoring |
| Safety keyword suites | Current repository suites pass all included cases | Finite, already-seen test sets; not population-level accuracy |
| Planner phone latency | Founder observed roughly **10 s** | Anecdotal observation; no instrumentation or distribution |

The acceptance benchmark still needed on the iPhone 12 Pro Max should record:

- cold and warm model load;
- per-task p50/p95 latency and tokens per second;
- peak resident memory, memory warnings, thermal state, and battery impact;
- cancellation time and behavior during app backgrounding;
- offline results after a clean launch;
- GPS filtering, background tracking, street snapping, and recovery outdoors;
- map frame pacing during pan, zoom, replay, and a large history;
- region decode, graph-build, route-search, launch, and history-query durations.

Store benchmark inputs, commit/device/runtime identifiers, and raw results together. A single fast run should not become the published benchmark.

## Priority architecture work

1. **Instrument and run the physical-phone acceptance matrix.** This resolves the largest unknowns before tuning or adding more geography.
2. **Add a walk summary/index and bounded track thinning.** This prevents predictable history growth from turning into a migration emergency.
3. **Add user-controlled export/restore.** Local `.bak` recovery cannot protect against loss, replacement, or uninstall.
4. **Measure region and graph budgets.** Cap resident packs/nodes with evidence from the target phone and cache graph artifacts where it proves valuable.
5. **Continue route/place evidence review.** Preserve the difference between computed suggestions and verified access facts.
6. **Reconcile stale model-size documentation.** Any remaining reference to the former ~429 MB model must be updated; the current selected artifact is the 1.7B model described above.

## Evidence boundaries

All counts and file sizes above describe the current working checkout. The five city-region manifests were being updated in parallel during this review, so these inventory totals can change with the next data commit. Project documentation also contains historical measurements from older runtime/model states; this review uses the currently selected 1.7B material lock and explicitly labels development-machine results, anecdotal observations, projections, and unmeasured device limits.
