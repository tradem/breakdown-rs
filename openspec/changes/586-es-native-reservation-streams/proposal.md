<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 586 — ES-native reservation streams: atomic cross-aggregate uniqueness at the write boundary

## Why

The shipped #404/#37 doctrine enforces every cross-aggregate invariant with an
advisory API-edge 409 pre-check plus the authoritative projection unique
constraint. The pre-check-to-append window is racy: two concurrent creates with
the same key both pass the pre-check, both append their aggregate events, and
the projector savepoint-skips the losing duplicate — the client that got 2xx
holds an aggregate id the read model never surfaces (exactly what the CodeRabbit
thread on PR #584 documented for `(series_id, number)` episode numbering).

## Decisions (user-confirmed)

1. **Accept the ES-native reservation-stream design** (ADR-036) and migrate all
   four #404 invariants at once, not only episode numbering.
2. **Compensation = release event + reaper**: on create-failure the command
   appends a CAS-guarded `ReservationReleased` event to its reservation stream;
   a reaper worker handles crash orphans (released/consumed markers), keeping
   the four #404 projector savepoint-skips as documented backstop.

## Design (ADR-036 summary)

- **Synthetic reservation streams** in SierraDB, category `reservation`,
  one stream per invariant key: `reservation-epnum-{series}-{n}`,
  `reservation-seasnum-{series}-{n}`, `reservation-blocknum-{series}-{n}`,
  `reservation-sspair-{scene}-{day}`.
- **Reserve = raw `EAPPEND` with `ExpectedVersion::Empty`** — a competing
  command fails in the event store (`ErrorCode::WrongVer`) and maps to a clean
  registered 409 *before* touching the aggregate stream. After a
  `ReservationReleased` the stream can be re-reserved via CAS
  (`ExpectedVersion::Exact(last)`); a claim whose payload matches the same
  `aggregate_id` is owned by the retry itself (idempotent AI-apply recovery,
  mirroring issue #182).
- **Command flow (all four adapters):** reserve → aggregate execute → on
  aggregate failure release (best-effort) → on success leave the claim held
  (numbers/pairs are not releaseable in today's domain: no delete commands,
  archives keep their number reserved).
- **Reservation projector** (`projection_number_reservation`, category
  `reservation`) observes claim/release/consume events for observability and
  reaper candidate selection; the reaper itself always re-reads the
  authoritative event store before acting.
- **Reaper (crash-orphan compensation):** for every `reserved` claim older than
  a TTL, probe the claimed aggregate's event stream (`esver`): exists → append
  `ReservationConsumed` (claim is permanently true); absent → append
  `ReservationReleased` (orphan released, key becomes claimable again). All
  writes CAS-guarded on the observed stream version.
- **Problem-code surface unchanged**: both pre-check 409 and atomic-race 409
  reuse the registered codes (`episode.number-already-exists`,
  `season.number-already-exists`, `block.number-already-exists`,
  `scene-shoot.pair-already-exists`) — clients keep branching on stable codes.
- **Backstop retained**: the four #404 savepoint-skips stay in place
  (documented, not removed) — the projection unique constraints remain the last
  authority.

## Scope

| Area | Change |
|---|---|
| `core` | No domain change (problem codes reused; ports unchanged) |
| `infra` | `reservations` module (event/store/reaper), reservation projector + migration, adapter integration for the four creates |
| `api` | Composition-root wiring (projector + reaper spawns), no handler changes |
| Docs | ADR-036, AGENTS.md §1 doctrine update, runbook section, CHANGELOGs |

## Acceptance Criteria (mapped from issue #586)

- [ ] ADR-036 written and accepted, compensation trade-offs spelled out.
- [ ] `CreateEpisode` (manual + AI apply) enforces `(series_id, number)`
      atomically at the write boundary; a racing command answers 409 with a
      registered problem code.
- [ ] Same guarantee for `CreateSeason`, `CreateBlock`, `PlanSceneShoot`.
- [ ] No orphaned reservations: release on create-failure, reaper consumes
      realized claims and releases crash orphans — specified and tested.
- [ ] The four #404 projector savepoint-skips remain as documented backstop.
- [ ] Integration test: two concurrent creates with the same target number —
      exactly one succeeds, the loser gets 409, and no scenes reference an
      unprojected episode.
