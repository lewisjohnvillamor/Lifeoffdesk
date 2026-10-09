# Accessibility facts and safety — implementation contract

Decision: 2026-10-09. This is planned MVP evidence handling, not a verified dataset, route engine or safety certification. The 1.7B model interprets functional requests; deterministic code decides what the available evidence supports.

## Scope and semantics

Do not add a global `isAccessible` or `isSafe` flag. Venue access, a particular entrance, a toilet, a street segment and a crossing are different subjects. Evidence for one does not establish the others. The MVP cannot verify an accessible journey because walking routing is deferred.

Start with step-free entrance and reported wheelchair access as separate facts, plus pedestrian access restrictions. Preserve source claims for toilets, steps, surface, smoothness, incline, kerbs, width and lighting where present; support a filter only after its typed domain and evidence rules exist. No tag means unknown, not “no” or “yes”. OSM's [wheelchair definitions](https://wiki.openstreetmap.org/wiki/Key:wheelchair) distinguish yes, limited and no. [Access tags](https://wiki.openstreetmap.org/wiki/Key:access) describe access rules; retain mode-specific and conditional values rather than flattening them into one public/private guess.

## Data contract

Add a versioned evidence sidecar keyed by existing stable place IDs and, where applicable, stable entrance/segment IDs. Suggested resources: `place-facts.json` and `road-evidence.json`, both included in region manifest checksums. Missing sidecars on older packs decode as an empty evidence set. Keep the current raw `sourceAccess` and other `source*` fields; never promote them through a blanket place-level verification flag.

Each `EvidenceFactV1` needs:

| Field | Meaning |
| --- | --- |
| `id`, `schemaVersion`, `subjectID`, `subjectKind` | Stable fact and exact place/entrance/street/crossing scope |
| `kind`, typed `value`, `unit?` | Enumerated boolean-like access domain (`yes/no/limited/unknown`) or field-specific numeric/text domain; reject mismatched units/types |
| `sourceType`, `sourceURL`, `sourceRecordID`, `sourceVersion?`, `license` | OSM, venue operator or documented field observation and traceable provenance |
| `retrievedAt`, `observedAt?` | Download date is distinct from when someone observed the condition |
| `reviewStatus`, `reviewedAt?`, `reviewerID?` | `sourceOnly`, `reviewed`, `conflicted`; reviewed means documented review, not legal certification |
| `validUntil?`, `conditions`, `supersedesID?` | Explicit validity, access limits and retained history; missing validity cannot establish current hard eligibility |

Derive `stale` at evaluation time using a captured clock; do not rewrite historical records merely because time passed. Keep conflicting source records until a documented review resolves them. Avoid distributing personal reviewer names or field photos; a nonpersonal reviewer identifier and private evidence reference suffice. `reviewedAt` alone must never refresh an old observation.

## Provisioning and review workflow

1. Extend source import to retain raw access tags, source IDs/versions and entrance/road relations. Preserve OSM attribution and license notices. Review the source distribution requirements before shipping a derived pack.
2. Review a small subset of the existing 15–30 starter places, beginning with a proposed 5–10 specific entrances in Makati CBD/Muntinlupa. This is a collection target, not a claim they have been checked. Use an operator source or documented field check; record the exact condition, date and scope. Existing unreviewed records remain usable only with unknown facts displayed.
3. Define validity per fact during review. Structural observations and temporary closures must not share an arbitrary universal lifetime. Until a defensible validity policy is set, show the dated observation and leave current hard eligibility unknown. Even within validity, describe evidence as recorded rather than guaranteeing present conditions.
4. Validate schema, subject references, units, provenance, dates and conflicts in the pack builder. Human review is still required; passing JSON validation does not verify physical access.
5. Ship the small reviewed sidecar and keep an offline source/date panel. Provide a local “information may be outdated” state; automatic updates or user-report publishing are future work.

## Deterministic eligibility

Implement a pure `EligibilityPolicy.evaluate(requirements, candidate, facts, now)` returning `eligible`, `ineligible` or `unknown`, plus reason/fact IDs. For a strict step-free entrance requirement, require a scoped reviewed positive fact within its explicit validity and satisfied conditions. Negative, limited, conflicting, stale and absent evidence cannot pass. Unknown conditions produce unknown. Category/radius/budget checks remain separate.

For a soft preference, clearly separate unknown candidates from matching ones. Never describe them as meeting the requirement. A strict request with no supported candidates must stay empty; changing the requirement requires user action. Model-generated facts, unsupported candidate IDs and an overall place verification flag cannot override this policy.

Route requests such as “a wheelchair-accessible walk” or “no stairs on the way” cannot be satisfied by an accessible destination. Explain that route accessibility is unavailable; offer a venue-entrance filter only if the user chooses it. A measured width/incline does not by itself justify a universal accessibility or regulatory-compliance claim.

## Road/GPS integration boundary

At `main` `55d67ba`, `RoadContext.Road` retains highway/restriction information, but the frontier call passes only coordinate arrays to `AdventureSuggester`. That loses evidence required for eligibility. Coordinate with the in-flight street-snapping work: preserve stable IDs and metadata through candidate generation, then exclude known restricted/private or prohibited pedestrian segments from suggestions before ranking. Treat ambiguous access as unknown; a line on the map does not establish public walkability. Retain mode-specific exceptions/conditions for deterministic evaluation.

An unexplored-sector centroid may fall off the street. It must not become a claimed walkable destination: select an eligible grounded segment point or show exploration context without navigation claims. GPS matching is an estimate of recorded movement, not proof a street is safe or legally accessible. Preserve original accepted samples and discontinuities. Recommendation exclusions must not rewrite actual recorded history or force the matcher onto a preferred street. No LLM-based snapping, invented connectors or route construction.

## User-facing facts and safety language

- Show “Step-free entrance: not verified” when unknown; for a reviewed fact show source, observation/review date, entrance scope and conditions. State separately “Path to this entrance: not verified.”
- Show hard requirements as visible filter chips; explain exclusions and let the user edit them. Do not hide uncertainty behind a generic accessibility icon.
- [Mapped lighting](https://wiki.openstreetmap.org/wiki/Key:lit) is not evidence that lights work now or that a place is safe at night. Do not compute a safety score or infer crime risk from neighborhood, photos or demographics.
- Offline data cannot establish current floods, closures, weather or emergency conditions. Say current conditions are unavailable where relevant; never turn absence of alerts into “no hazards”. Live advisories require a separate future provider/freshness design.
- Keep suggestions as optional outing choices, not emergency or physical-safety guidance. Generated narration must use the same approved evidence IDs/templates as cards.

## App accessibility is a separate requirement

Implement semantic VoiceOver labels/order, Dynamic Type layouts, adequate contrast, non-color-only status and accessible alternatives to map gestures according to [Apple accessibility guidance](https://developer.apple.com/documentation/accessibility) and [the brand guide](BRAND-GUIDE.md). Provide text/list access to destinations and adventure details; do not require interpreting fog or a tiny map to understand the session. Test VoiceOver, large text, reduced motion and walking controls on the actual iPhone. Accessible UI does not certify physical destinations.

## Verification fixtures

Use explicitly synthetic subjects with fixtures covering absent facts, negative/limited values, expired facts, contradictory sources, wrong entrance, unmet conditions, future dates, invalid units, orphan segment IDs and source-only wheelchair tags. Ensure none pass hard eligibility. Test erase/cancellation and malicious catalog text without exposing personal routes. Field-review the shipped positive examples separately and record evidence gaps in [build status](BUILD-STATUS.md).

External references describe source semantics; they do not verify any Manila venue. Consulted 2026-10-09. No claim of compliance with a physical-accessibility law or standard is made by this specification.
