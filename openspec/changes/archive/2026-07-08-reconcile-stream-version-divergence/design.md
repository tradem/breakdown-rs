## Context

Two version notions coexist on the write/projection path:

- **Domain version** — `AggregateVersion` (`crates/core/src/shared.rs`), `INITIAL = 1`,
  incremented 1-based with every mutation and carried in every event payload's
  `version: AggregateVersion` field and in the aggregate state's `version` field.
- **SierraDB stream version** — `stream_version`, assigned 0-based by SierraDB
  (`stream_version = 0` for the first event in a stream), surfaced via
  `kameo_es::Event.stream_version` and `ExecuteResult`.

Current wiring (`crates/infra/src/event_store/command_adapters.rs`,
`crates/infra/src/projectors/*.rs`):

- `map_executed_result` returns `AggregateVersion(e.stream_version)` (0-based) to
  callers of `*Commands::create` / `update_*`.
- OCC input passes the caller's domain version straight through as
  `ExpectedVersion::Exact(version.0)` — i.e. it is treated as a stream version
  even though it is a domain version.
- All four projectors bind `event.stream_version as i64` into the
  `projection_*.version` columns.
- `version_from_current(CurrentVersion::Empty)` returns `AggregateVersion::INITIAL`
  (1), while `CurrentVersion::Current(v)` returns `AggregateVersion(v)` — an
  inconsistent empty/non-empty mapping.

Net effect: the value a client receives from `create` (0) and the value stored
in the projection row (0) do not equal the event-payload / aggregate version
(1). Because OCC input is `Exact(domain.0)` against a 0-based store, a round-trip
`create → reply 0 → update with 0` happens to match today, but a client using the
domain/version-payload notion (1) — or any future path that reads the payload —
hits a spurious `VersionConflict`. The Tier-4 tests cannot catch this because
they bypass `CommandService` (issue #25). Issue #31 tracks this.

Constraint: `core` must not depend on SierraDB types (ADR-017), so the
translation MUST live in `infra` at the port boundary.

## Goals / Non-Goals

**Goals:**

- Establish one canonical version notion across the port boundary, the projection
  rows, and the OCC path: the 1-based domain `AggregateVersion` with
  `INITIAL = 1`.
- Make `create → reply version → update with that version → read projection
  version` produce identical, conflict-free values through the real
  `CommandService`.
- Add a Tier-4 test that exercises the live OCC path end-to-end so the
  divergence cannot regress silently.

**Non-Goals:**

- Changing `AggregateVersion::INITIAL` to `0` (rejected alternative, see
  Decisions). The domain constant and its public meaning stay unchanged.
- Re-modelling `AggregateVersion` to carry an optional/empty state, or
  introducing a separate `StreamVersion` type in `core`.
- Fixing issue #25 (the `CommandService` bypass in Tier-4); this change depends
  on it for the new test but does not implement it.
- Migrating existing stored projection rows in any persistent environment — the
  dev/test runtimes are ephemeral and recreated per test.

## Decisions

### Decision 1: Keep the domain 1-based; translate at the infra port boundary

`AggregateVersion::INITIAL` stays `1` and the event payload keeps carrying the
1-based domain version. The SierraDB `stream_version` becomes an infra-internal
storage detail and is translated exactly at the `*Commands` port boundary:

```
domain_version  =  stream_version + 1
stream_version  =  domain_version - 1   (for ExpectedVersion::Exact on updates)
```

**Why over the alternative** ("align `INITIAL = 0`"): aligning INITIAL with the
0-based stream version would also remove the divergence, but it breaks the
existing public meaning of `INITIAL = 1` (the "first version" assigned on
creation), requires touching every aggregate's `version` handling and every
event-payload consumer, and makes the domain model less intuitive. The
port-boundary translation is a localized change in one `infra` module plus the
projectors, keeps `core` pure, and the mapping is a trivial `±1`.

**Alternatives considered:**

- *Align `INITIAL = 0`*: rejected as above.
- *Store `stream_version` everywhere and redefine the domain version as the
  stream position*: rejected — it conflates a storage position with a domain
  invariant and leaks SierraDB semantics into `core`.

### Decision 2: Projectors bind the event payload version, not `stream_version`

Each projector switches from `event.stream_version as i64` to the domain
`version` carried in the decoded `event.data` payload (e.g. the `version:
AggregateVersion` field already present on every `*Event` variant). This makes
the projection row a direct source of truth for the canonical domain version with
no extra translation, and removes the silent 0-based drift from the read model.

**Why:** the payload version and `stream_version + 1` are nominally equal today,
but relying on the payload binds the projection to the domain contract rather
than to a storage-position detail that is only coincidentally related.

### Decision 3: Reject `AggregateVersion(0)` on the OCC input path

Because domain version `0` is not a valid expected version for an existing
aggregate (`INITIAL = 1` after creation), the write adapter SHALL treat a caller
supplied `version.0 == 0` on any `update_*` port method as a client error
(`DomainError::VersionConflict`) rather than underflowing to
`ExpectedVersion::Exact(u64::MAX)` via saturating subtraction or panicking on
checked subtraction. `Create*` continues to use `ExpectedVersion::Empty`, which
needs no translation.

### Decision 4: Empty-stream mapping is reported as the canonical "pre-creation" value

On the OCC error and idempotent reply paths, `CurrentVersion::Empty` (no events)
SHALL map to `AggregateVersion(0)` conceptually (a stream that has had no events
has no domain version yet), reported in `DomainError::VersionConflict` as
`current = 0`. This replaces the current `INITIAL` (1) mapping, which falsely
claimed a version for a nonexistent stream. The create path is unaffected (it
succeeds via `Empty` and returns `1` from the first event's `stream_version
+ 1`).

### Decision 5: New Tier-4 OCC round-trip test depends on #25

A new `crates/integration-tests` Tier-4 test drives
`create → read returned version → update_* with that version` through the real
`CommandService` against ephemeral SierraDB + Postgres containers and asserts
success (no `VersionConflict)`. This is the regression guard for the divergence.
It is gated on #25 making `CommandService` available in the Tier-4 harness; the
test is written behind that wiring and marked `#[ignore]`/TODO until #25 lands.

## Risks / Trade-offs

- **Stale stored projection rows** — any non-ephemeral environment that already
  has rows with `version = stream_version` (0-based) would read back one lower
  than the next write's expected version. → Mitigation: dev/test runtimes are
  ephemeral; before any persistent deployment, a one-shot
  `UPDATE projection_* SET version = version + 1` migration is issued. Tracked as
  a migration step, not part of this code change.
- **Translation bugs** — a future refactor touching the `±1` mapping could
  re-introduce the off-by-one. → Mitigation: centralize the translation in
  small named helpers in `command_adapters.rs` (e.g.
  `stream_to_domain` / `domain_to_stream`) covered by unit tests, plus the
  Tier-4 round-trip test as the end-to-end guard.
- **Tier-4 test blocked on #25** — the regression guard cannot run until #25 is
  resolved. → Mitigation: the test is authored now and wired to run as soon as
  the `CommandService` seam is in place; the unit tests for the translation
  helpers ship immediately and protect the mapping in the meantime.
- **Projectors coupling to payload field name** — switching to the payload
  `version` requires every `*Event` variant to expose a `version` field. → All
  existing variants already do; an exhaustive `match` keeps it enforced.
