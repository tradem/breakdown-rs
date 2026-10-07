<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ADR-036: ES-native reservation streams for cross-aggregate uniqueness

**Status**: Accepted
**Date**: 2026-10-07
**Author**: Tobias Rademacher (@tradem); Co-authored-by: glm-5.3 (neuralwatt); Co-authored-by: glm-5.3-flash (opencode-go)
**Related**: ADR-002 (Event Sourcing/CQRS), ADR-015 (SierraDB event store + Postgres projections), ADR-031 (HTTP error surface), ADR-035 (B4: uniqueness keys tenant-prefixed)
**Source change**: GitHub issue #586 (`openspec/changes/586-es-native-reservation-streams`), doctrine basis issues #404/#37, surfaced by PR #584 (issue #581)

---

## Context

The #404 doctrine fixes cross-aggregate invariants (uniqueness) with three
layers: an **advisory API-edge 409 pre-check** (the handler is the only
legitimate read-model consumer), the **authoritative projection unique
constraint** as race backstop, and **projector failure behavior** (the #404
savepoint-skip for the four authoritative constraints — never dead-lettered;
the generic #37 dead-letter path for everything else).

The documented residual gap (#586): **the pre-check-to-append window is racy.**
Two concurrent creates with the same key both pass
`find_by_series_and_number`/`find_by_pair` before either projection row exists,
then append separate aggregate streams with the same key. The projector
savepoint-skips the losing duplicate `*Created` by design, so the client that
already received 2xx holds an aggregate id the read model will never surface;
in the AI-apply path the worker dispatched the group's scenes onto that id.

The known ES-native remedy, sketched in AGENTS.md §1 as *"design follow-up,
ADR-worthy — do not adopt ad hoc"*: a reservation event written to a synthetic
key stream with `ExpectedVersion::Empty` before the aggregate append; a
competing command fails the version condition **in the event store**
(`ErrorCode::WrongVer` — verified permanent/non-retryable in sierradb-protocol
0.3.1) and maps to a clean 409 *before* touching the aggregate stream.

## Decision

**Accepted — all four #404 invariants migrate to reservation streams at once**
(episode numbering `(series_id, number)`, season numbering `(series_id,
number)`, block numbering `(series_id, number)`, scene_shoot pair-uniqueness
`(scene_id, shooting_day_id)`), on both write paths for episodes (manual
`POST /episodes` and the AI-apply `create_episode_reserved`), via the shared
command adapters. Compensation follows the **release event + reaper** design.

### 1. Reservation streams

Synthetic SierraDB streams, category `reservation` (so the `kameo_es` projector
pipeline matches them via a dedicated pseudo-entity; no aggregate projector is
disturbed), one stream per invariant key:

| Invariant | Reservation stream id | Key payload |
|---|---|---|
| Episode numbering | `reservation-epnum-{series_simple}-{number}` | `{ aggregate_id }` |
| Season numbering | `reservation-seasnum-{series_simple}-{number}` | `{ aggregate_id }` |
| Block numbering | `reservation-blocknum-{series_simple}-{number}` | `{ aggregate_id }` |
| SceneShoot pair | `reservation-sspair-{pair_hash24}` | `{ aggregate_id }` |

`{series_simple}` is the compact (dash-less, 32-char) `Uuid::simple()` hex
form of the tenant-scoped series id; `{pair_hash24}` is a truncated SHA-256
over `(scene_id, shooting_day_id)` (12 bytes = 24 hex chars) — SierraDB caps
stream ids at 64 characters, so the dashed 36-char UUID forms and the raw
pair would overflow. Key payloads are unchanged.

Keys carry the tenant-scoped container id first (ADR-035 B4 — today the tenant
seam is `series_id`; the `Project` rename change renames the stream ids with
the same sweep).

### 2. Claim lifecycle

Events on a reservation stream (CBOR payloads, mirroring the `kameo_es`
envelope convention; event names `ReservationReserved`, `ReservationReleased`,
`ReservationConsumed`):

- `ReservationReserved { aggregate_id }` — a claim.
- `ReservationReleased { aggregate_id }` — the holder gave the key back.
- `ReservationConsumed { aggregate_id }` — the reaper observed the claim has
  become permanently true (the aggregate stream exists).

**Reserve** (raw `EAPPEND` on the `sierradb-client` connection pool — the
`kameo_es` `CommandService` actor machinery is aggregate-only):

1. Try `EAPPEND ... ExpectedVersion::Empty`.
2. On `WrongVer`: the error message carries the parsed `CurrentVersion`
   (`kameo_es::error::parse_stream_version_string`). Read the stream
   (`escan`) and branch on the last event:
   - `ReservationReleased` → **re-reserve by CAS**: `EAPPEND` with
     `ExpectedVersion::Exact(last_version)`; a competing re-reserver's CAS
     fails and the loop re-reads with a bounded retry budget (3), then maps to
     the registered 409.
   - `ReservationReserved { aggregate_id == ours }` → the claim is our own
     retry's (crash between reserve and aggregate append; idempotent AI-apply
     recovery, mirroring issue #182) → proceed holding it.
   - `ReservationConsumed { aggregate_id == ours }` → the reaper consumed our
     claim after the aggregate was realized (it can run between a crashed
     attempt and its worker re-drive) → proceed holding it the same way; the
     consumed key stays non-releasable (§3.2: the reaper only ever acts on
     `Reserved` claims), and §3.3's holder-convergent retry guarantee extends
     across consumption.
   - `ReservationReserved { other }` / `ReservationConsumed { other }` →
     `DomainError::Conflict` with the invariant's registered problem code →
     409 before any aggregate append.

The winner's `stream_version` (its own `ReservationReserved` event) is the
release token.

**Aggregate create** proceeds exactly as today (`ExecuteExt` with
`ExpectedVersion::Empty`).

**Release** (create-failure compensation): `EAPPEND reservationreleased` with
`ExpectedVersion::Exact(own_reserved_version)` — CAS-guarded so only the
holder releases and only while its claim is still the top of the stream.

### 3. Compensation — no orphaned claims (release event + reaper)

The reserve→append gap is not atomic (SierraDB offers no cross-stream
transaction and the two streams partition differently), so three compensation
paths exist:

1. **Create-failure (in-process):** the adapter releases with its CAS token
   before propagating the original error. Best-effort: if the release itself
   fails, the reaper cleans up via the TTL path below.
2. **Crash orphan (reaper):** the key would be blocked forever. The reaper
   worker (config-gated, default on; TTL default 600 s — the aggregate append
   happens seconds after the reserve, so any older un-realized claim is
   orphaned) treats every claim older than the TTL as a candidate and resolves
   it **against the event store itself** (never projections, so projector lag
   cannot cause a false release):
   - probe the claimed aggregate's stream (`esver`): version > 0 → the number
     is legitimately taken from here to eternity (numbers/pairs are not
     releaseable in today's domain — there are no delete commands; #533 keeps
     archived seasons' numbers reserved) → append `ReservationConsumed`;
   - version absent → orphaned claim → append `ReservationReleased` (CAS on
     the observed stream version; a lost race is retried next pass).

 After a consume, a competing reserve fails with 409 forever — correct, the
   key is owned by the realized aggregate. After a release, the key is
   claimable again via the CAS re-reserve path.
3. **Holder-convergent retry:** a claim by the *same* `aggregate_id` never
   blocks its own retry ( recovery case above).

### 4. Reservation projector

`projection_number_reservation` (migration) mirrors the claim lifecycle for
**observability and reaper candidate selection only**: key (PK),
`reservation_kind`, `aggregate_id`, `stream_version` (last observed), state
(`reserved` / `released` / `consumed`), `reserved_at`. It runs through the
standard `kameo_es` PostgresProcessor pipeline (checksums, #37 DLQ, runbook
health). The reaper *candidates* from this table but always re-reads the
authoritative event store before acting, so a lagging projector can never
cause a wrong release.

### 5. Problem-code surface, pre-checks, and the backstop — unchanged

- The atomic race maps to the same registered codes as the pre-check
  (`episode.number-already-exists`, `season.number-already-exists`,
  `block.number-already-exists`, `scene-shoot.pair-already-exists`). Clients
  keep branching on stable codes; no new registry entries.
- The API-edge pre-checks stay (cheap, fail fast before reservation round
  trips) — they are advisory as always.
- The four #404 projector savepoint-skips **remain** as the last-line backstop
  and are not removed (defense in depth if a deployment runs without the
  reaper or with reservations disabled).

## Alternatives considered

- **Status quo with documented race** (reject): the losing client's 2xx
  phantom aggregate is user-visible data loss in the read model — rejected.
- **Abandoned-stream scheme** (per-attempt keys, no release events, no reaper):
  simpler compensation, but it cannot converge a retried claim onto the same
  key without duplicates, and orphan streams are invisible garbage rather than
  queryable state — rejected in favor of release + reaper.
- **Postgres-side serialization** (advisory locks / serializable transactions
  around reserve+append): cannot span Postgres and SierraDB atomically —
  rejected.
- **Only episode numbering** (phased migration): the four invariants are one
  mechanism built once in a shared module; migrating only one leaves three
  documented race windows — rejected by decision (all four at once).

## Consequences

### Positive

- Cross-aggregate uniqueness is enforced **atomically at the write boundary**
  in the event store for all four invariants — the 2xx-phantom-aggregate race
  window is closed on both episode write paths.
- The loser receives a registered 409 with the same problem code as the
  advisory pre-check — no client contract change, no OpenAPI drift.
- Compensation is explicit, durable, and queryable (claim lifecycle is real
  projectable state, runbook-visible), instead of relying on the projector
  skip as the silent arbiter.
- Only pre-existing SierraDB primitives are used (`EAPPEND` expected-version
  CAS + `WrongVer` parse + `escan`/`esver`) — no server feature requests.

### Negative

- One extra SierraDB stream (and up to three events during its life) per
  created entity — storage/latency overhead of one append round trip per
  create.
- A crash between reserve and aggregate append blocks the key until the reaper
  TTL elapses (default 600 s). The reaper is therefore a required companion
  deployment (documented; enabled by default).
- The `WrongVer` message-parsing contract (`parse_stream_version_string`) is
  upstream-controlled; a format change would need a patch in the vendored
  `kameo_es` (same maintenance class as the existing vendored patch points).
- Reservation streams are a hidden dimension of the event store: new
  contributors must understand that `reservation-*` streams are bookkeeping,
  not domain events, and must never be replayed into domain aggregates.
