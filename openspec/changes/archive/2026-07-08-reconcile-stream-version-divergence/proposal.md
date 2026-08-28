## Why

There are two divergent version notions in the write/projection path: the
**domain** version (`AggregateVersion::INITIAL = 1`, incremented 1-based with
every mutation, carried in every event payload) and the **SierraDB stream
version** (`stream_version = 0` for the first event, 0-based). The infra write
adapter returns `AggregateVersion(stream_version)` (0-based) to callers and uses
the 0-based stream version for optimistic concurrency, while the event payload
and the aggregate state carry the 1-based domain version. A client that reads a
projection row (or the create reply) and feeds the version back into the next
write can therefore hit a spurious `VersionConflict`, because the version it
holds does not round-trip through `ExpectedVersion::Exact` consistently. This
divergence is invisible in the current Tier-4 tests because they bypass
`CommandService` (see #25). Tracked in GitHub issue #31.

## What Changes

- Establish a **single canonical version contract**: the domain
  `AggregateVersion` is 1-based (`INITIAL = 1`, incremented per mutation) and is
  the only version notion exposed across the `*Commands` port boundary, returned
  to callers, stored in projection rows, and accepted on the next write.
- The SierraDB `stream_version` becomes an **infra-internal storage detail**.
  The write adapter SHALL translate between the domain version and the SierraDB
  stream version at the port boundary, so that the round-trip
  `create → reply version → update with that version` never yields a spurious
  conflict.
- The projectors SHALL store the **domain** version (event payload
  `version`/`AggregateVersion`), not the raw 0-based `stream_version`, into the
  `projection_*.version` columns, so a projection version is directly reusable
  as the next command's expected version.
- **BREAKING** for any consumer depending on `AggregateVersion::INITIAL` being
  reflected verbatim as a SierraDB stream position: the value returned by
  `*Commands::create` changes from `0` to `1`, matching the projection row.
  `AggregateVersion::INITIAL` itself is unchanged (stays `1`).
- Add a **Tier-4 OCC round-trip test** that drives
  `create → read version → update with that version` through the real
  `CommandService` against ephemeral SierraDB + Postgres containers and asserts
  no spurious `VersionConflict` (depends on #25 lifting the
  `CommandService` bypass in Tier-4).

## Capabilities

### New Capabilities

- `aggregate-version-semantics`: the canonical `AggregateVersion` contract —
  1-based domain version with `INITIAL = 1`, the rule that the domain version
  equals `stream_version + 1`, and the requirement that translation happens
  exclusively at the infra port boundary.

### Modified Capabilities

- `persistence-write-ports`: the `*Commands` port boundary SHALL expose only the
  canonical domain version on both the reply path (create/update return values)
  and the OCC input path (`ExpectedVersion` translation), removing the current
  passthrough of raw SierraDB `stream_version`.
- `persistence-projections`: the `projection_*.version` columns SHALL mirror the
  canonical domain version carried in the event payload, not the raw
  `stream_version`.
- `sierradb-round-trip-testing`: add a Tier-4 variant that exercises the live OCC
  path end-to-end through `CommandService` (create → read version → update with
  that version → no spurious conflict), unblocking the gap left by #25.

## Impact

- `crates/core/src/shared.rs` (`AggregateVersion`) — documentation of the
  canonical contract; `INITIAL` unchanged.
- `crates/infra/src/event_store/command_adapters.rs` —
  `map_executed_result` / `version_from_current` / `version_from_expected` and
  the `ExpectedVersion::Exact(version.0)` call sites require 1-based↔0-based
  translation at the boundary.
- `crates/infra/src/projectors/*.rs` — projectors currently bind
  `event.stream_version as i64`; switch to the payload domain version so the
  projection mirrors the canonical version. Existing Tier-1–3 and Tier-4
  assertions asserting `AggregateVersion(0)` / `version == 0` must be updated to
  the 1-based canonical value.
- `crates/integration-tests` — new Tier-4 OCC round-trip test (blocked on #25
  for the `CommandService` wiring in the harness).
- Follow-ups referenced: #25 (CommandService in Tier-4), PR #24 (author comment
  item #6).
