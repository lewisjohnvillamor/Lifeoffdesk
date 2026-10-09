# Life Off Desk — architecture and data contracts

## Offline architecture

SwiftUI views call a walk coordinator, local store, local catalog and local AI adapter. Location updates and AI run through separate tasks. Inference runs only after a user request, away from the UI thread; cancel it when the user leaves or requests cancellation. Bound model work and avoid loading it continuously during a walk.

For the starter slice, render bundled road/path GeoJSON and POIs in a simple projected canvas. Mask underlying detail with the accumulated explored corridor. A trail can still be recorded outside bundled coverage, with “Map detail unavailable here.” Do not rely on a warmed online map cache as proof of offline maps. Adopt a full offline map SDK only after the small required demo works.

## Session lifecycle

Idle → requesting permission → acquiring GPS → walking ↔ paused → finished.

Denied permission returns to an actionable idle state. No valid fix means no fabricated live marker. Finish is idempotent. A crash or app termination leaves a recoverable paused session; never silently resume collection. Tracking begins explicitly and stops on Finish. Test the actual chosen background-location configuration on the phone rather than claiming continuous tracking from simulator behavior.

## Records

| Record | Minimum fields |
| --- | --- |
| WalkSession | UUID, schemaVersion, state, startedAt, endedAt?, activeDuration, accepted samples, segment boundaries, destinationPlaceID? |
| TrackSample | latitude, longitude, timestamp, horizontalAccuracy; optional measured speed |
| Exploration | schemaVersion, accepted segmented paths or derived mask, revealWidthMeters, source session IDs |
| Place | stable ID, name, coordinates, category, tags, source URL/ID, retrievedAt, verification status; optional supported cost/hours facts |
| Suggestion | source place ID, matched preferences, computed straight-line distance, uncertainty labels |
| Memory (P1) | UUID, sessionID, local file path, timestamp, optional opt-in location, optional cutout file |
| RegionManifest | ID, version, bounds, source/attribution, actual byte count, file checksums |

Keep exploration independent of map-data versions so replacing a starter map does not erase progress. Rebuild render caches from saved paths. Save atomic snapshots incrementally; retain recoverable prior state if decoding fails. Large model artifacts are provisioned separately; do not casually commit them to Git.

## GPS and reveal policy — starting values to test

These values are provisional tuning defaults, not empirically validated safety thresholds:

- Reject negative horizontal accuracy, samples older than 10 seconds and accuracy worse than 30 meters. Reject future timestamps above a provisional 2-second clock tolerance and non-increasing timestamps. Apply freshness at receipt; previously accepted historical samples remain valid history.
- Break the segment across an update gap above 15 seconds; never fill a long missing section with a revealed line.
- Reject implausible pedestrian jumps above roughly 4 m/s after considering time and accuracy. Treat vehicle mode as deferred.
- Use a small movement hysteresis (start at 5 meters) plus accuracy-aware stationary handling. A few meters of GPS drift must not steadily expand the map.
- Start with a 25-meter total corridor width. Render in projected meter coordinates; retain original accepted geographic samples.
- Distance sums accepted segments only. Active duration excludes pause. Revisited paths preserve the same explored area; do not award duplicate area.

Tune during an outdoor walk and keep replay fixtures for stale fixes, large jumps, pause gaps, long update gaps and stationary jitter. Do not assert percent of Luzon explored until an area denominator and coverage method exist.

## AI contract

The model extracts intent. App code finds actual places. Begin with one short turn and this proposed schema:

```json
{"durationMinutes":30,"budgetPHP":null,"categories":["park"],"moodTags":["quiet"],"travelMode":"walk","needsClarification":false}
```

Proposed initial bounds: duration 5–120 minutes or null; budget 0–10000 PHP or null; travelMode must be walk; categories allow park/cafe/museum/library/scenic/other, at most three; moodTags allow quiet/nature/curious/relax/active, at most three. Use a proposed 2 km initial straight-line search radius, adjustable explicitly up to 5 km. These are product defaults to confirm, not model capability claims. Validate bounds, enums, array sizes and types. Treat null as unknown. If needsClarification is true or the request cannot be interpreted, ask one short clarification before searching rather than fabricate preferences. Reject malformed output; one bounded repair attempt is permissible, then a clear retry/manual-filter state. Manual filters keep the app usable but are not proof of Local AI.

Use a constrained output grammar if supported by the pinned runtime, short context (initial trial 1024–2048 tokens) and bounded output (initial trial 128–192 tokens). Those are trial settings; compare quality and memory on the actual phone. Apply the model's correct chat template. Treat catalog/user text as data, not executable instructions.

Rank deterministically using supported categories, selected maximum radius and verified tags. Unknown price does not satisfy a strict price ceiling. Unknown quietness/hours remain unknown. If duration implies a reachable limit, do not equate straight-line distance with route distance; show it as approximate and avoid hard promises. A transparent suggestion card can say “Matches your park preference; 0.8 km straight-line; opening hours unverified.” That number is illustrative, not a seeded venue fact.

## Starter content and storage

Gather 15–30 real nearby places for one chosen area. Record provenance and retrieval date for every record. Missing matches must produce a useful empty state. Prepare small road/path data separately. If using OpenStreetMap-derived content, preserve source attribution and required license notices; verify dataset distribution terms. Do not scrape public map tiles for an offline pack.

Track app binary, runtime, model, map/catalog and personal photos as separate byte counts. The Qwen publisher's Qwen3-0.6B GGUF Q8 listing shows approximately 639 MB; that is model storage, not peak RAM or total app size. Prefer a smaller compatible quantization only after provenance, license and quality testing. No full Luzon storage estimate is justified until boundaries, detail level and sources are chosen.

Privacy intent: no account, analytics upload or cloud inference in this slice. No cloud-sync capability added by default. Describe OS backup behavior honestly; do not promise that device data can never enter a user's backups. Erase personal data without accidentally deleting reusable model/map assets. Provide export before wider use as a P1 protection against device loss.

## Makati and Taglish implementation update

Use config/starter-region.json for the proposed Makati CBD subset. scripts/prepare_makati.py retrieves source records and starter road geometry once during provisioning; review places before bundling. Raw OSM records are source-backed, not independently verified open/accessible venues. Treat Taglish requests as required AI inputs; see eval/taglish-cases.json. Display Taglish guidance through localized templates built from validated matches, with model intent extraction actually running on the phone. Localized templates do not replace the model inference requirement.
