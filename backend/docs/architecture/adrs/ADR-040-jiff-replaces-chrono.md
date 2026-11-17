<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ADR-040: `jiff` replaces `chrono` as the workspace time library

**Status**: Accepted
**Date**: 2026-11-18
**Author**: Tobias Rademacher (@tradem); Co-authored-by: glm-5.3 (neuralwatt)
**Related**: ADR-002 (Event Sourcing, no history rewriting), ADR-006 (code-first OpenAPI via `utoipa`), ADR-015 (SierraDB event store + Postgres projections), ADR-017 (cargo-deny supply-chain gate), ADR-020 (versioning), ADR-031 (HTTP error surface), ADR-035 (layer 2: persisted wire keys are load-bearing)
**Source change**: GitHub issue #929

---

## Context

`RUSTSEC-2026-0543` declares `chrono` unmaintained. The advisory covers **every**
published version, offers no safe upgrade, and recommends `jiff` or `time`. Because
`backend/deny.toml` runs with `unmaintained = "all"` (fail-closed, issues #70/#95),
the gate went red for the whole workspace the moment the advisory was published.

`chrono` was not a transitive nuisance but a **direct** workspace dependency reachable
from six crates (`core`, `infra`, `api`, `test_support`, `fuzz-targets`,
`integration-tests`) plus three downstream integration points:

| Surface | How chrono entered |
|---|---|
| Domain types | `core` DTOs/events carry `DateTime<Utc>` (~306 references, ~490 sites) |
| Postgres | `sqlx` feature `chrono` maps `timestamptz`/`timestamp`/`date` |
| OpenAPI | `utoipa` feature `chrono` renders `format: date-time` / `format: date` |
| Event store | `kameo_es` (vendored patch) declares `Event::timestamp` / `Context::time` |

The temporary local action (the PR that hit the advisory) was an
`[advisories] ignore` entry with a justification comment. It unblocked the gate, but
it left the crate that serializes **every persisted aggregate timestamp** without
upstream maintenance — acceptable only until the migration has an owner.

### The four contracts a migration must not break

A time-library swap is not a `sed`, because four surfaces have to stay
byte-compatible at the same time:

1. **Persisted event payloads.** Events are serialized with `ciborium` (CBOR) over
   `serde`. chrono rendered `DateTime<Utc>` as RFC 3339 with `SecondsFormat::AutoSi`
   and a `Z` suffix — `2026-11-17T12:49:25Z`, or with exactly 3, 6 or 9 fractional
   digits when the value carries sub-second precision. A different rendering is a
   *replay-breaking* change for the whole event store, and — because
   `projection_audit.event_key` is derived from the **re-serialized** payload
   (ADR-035 layer 2) — it would also duplicate every audit row on replay.
2. **Postgres columns.** `timestamptz`/`timestamp`/`date` must keep their native
   column type and their sqlx mapping. Emulating them as text would lose range,
   ordering and index behaviour.
3. **The OpenAPI contract.** `format: date-time` / `format: date` are consumed by
   the Flutter client's generated models; `openapi.yaml` is a reviewed artifact
   and the drift test is the gate (ADR-006).
4. **bson** was suspected as a fourth surface (the vendored `kameo_es` patch has an
   optional `bson` dependency with a `chrono-0_4` feature). It is **not** in the
   graph: the `mongodb` feature is unused, and the store payloads are CBOR, not
   bson. Dropping the `chrono-0_4` feature keeps it that way.

## Decision

**The workspace uses `jiff` 1.x as its single time library**, with `jiff-sqlx` 1.x as
the sqlx bridge, and `chrono` is removed from the dependency graph entirely (no
`[advisories] ignore` in `deny.toml`).

Mapping:

| chrono | jiff |
|---|---|
| `DateTime<Utc>` | `jiff::Timestamp` |
| `Utc::now()` | `Timestamp::now()` |
| `NaiveDate` | `jiff::civil::Date` |
| `NaiveDateTime` | `jiff::civil::DateTime` |
| `Duration` / `TimeDelta` | `jiff::SignedDuration` |
| `sqlx` feature `chrono` | `jiff-sqlx` wrapper types via `infra::db_time` |
| `utoipa` feature `chrono` | `utoipa` feature `jiff_0_2` (type-name based) |

### Why `jiff` and not `time`

The deciding property is the **serializer**, and it was measured, not assumed:
`jiff::Timestamp`'s serde rendering is byte-identical to `chrono::DateTime<Utc>` for
every value shape chrono could produce (whole second, 3, 6 and 9 fractional digits,
pre-epoch instants), and jiff parses chrono's output back losslessly.

`time::OffsetDateTime` is not: its human-readable serde form is
`2026-11-17 12:49:25.123456789 +00:00:00` (space separator, always-present fraction,
numeric offset), and its `well_known::Rfc3339` formatter emits `+00:00` rather than
`Z`. Choosing `time` would therefore have meant a `#[serde(with = …)]` wrapper on
every persisted timestamp — the same migration plus a hand-written RFC 3339 writer on
the most safety-critical field in the system. `jiff` is also the advisory's first
recommendation, models the same instant/civil split chrono had, and its serde
rendering is documented behaviour, not an accident.

`sqlx` 0.9 has **no** `jiff` feature, and Rust's orphan rules forbid implementing
`Type`/`Encode`/`Decode` for `jiff::Timestamp` in this workspace (trait, type and
`Postgres` are all foreign). The companion crate `jiff-sqlx`, published from the
`jiff` repository and tracking `sqlx ^0.9`, supplies the wrapper types; `infra`
exposes exactly one bridge module (`crates/infra/src/db_time.rs`) so that no call
site depends on the wrapper crate directly.

`utoipa` 6 (the version pinned in lockstep with `utoipa-swagger-ui` 10) ships only a
`jiff_0_2` bridge. It resolves schemas by **type name** (`Timestamp`, `Date`,
`Zoned`), which `jiff` 1.0 keeps, so the feature is enabled as-is; the `openapi_drift`
test is the proof (see Consequences). `jiff::civil::DateTime` is **not** covered —
those fields carry an explicit `#[schema(value_type = Option<String>, format = DateTime)]`.

### The vendored `kameo_es` patch

`kameo_es` (`.patches/kameo_es`) owns `Event::timestamp`, `Context::time` and
`AppendedEvent::timestamp`, so it had to move too. Two details are deliberate:

- Its chrono→`SystemTime` conversions were `From`; jiff's are `TryFrom` (a `Timestamp`
  spans ±9_999 years, `SystemTime`'s range is platform-defined). They became two small
  fallible helpers feeding the already-existing `InvalidTimestamp` variant — never a
  silent clamp, because a folded append timestamp would corrupt stream ordering.
- The rate-limiter's `command_history` stays on `SystemTime`: it is compared against
  `SystemTime::now()` only, so converting it would have added a lossy hop for nothing.

## Consequences

### Positive

- `cargo deny check advisories` is green **without** any ignore for `RUSTSEC-2026-0543`,
  and `cargo tree -i chrono` is empty — the gate is fully closed again instead of
  carrying a permanent exception for a direct dependency.
- One time library, one mapping point for the database (`infra::db_time`), one place
  to change if `sqlx` ever grows native jiff support.
- The wire format is proven, not assumed: `crates/integration-tests/tests/event_fixture_contract_tests.rs`
  gained `pre_migration_timestamps_round_trip_byte_identically` (JSON **and** CBOR, six
  instant shapes) and `legacy_offset_spellings_still_replay` (`+00:00` and lower-case `z`
  still decode; the writer stays canonical). Both are container-free, so they run in
  the pure-serde gate on every PR.
- `openapi.yaml` is **byte-identical** across the migration (the drift test sees zero
  diff), so the generated client models need no coordination.
- jiff's civil types make the naive/absolute distinction explicit at the type level,
  which is what the `SceneShoot` start/end DTOs were already doing implicitly.

### Negative

- Two crates instead of one (`jiff` + `jiff-sqlx`), and the latter exists only because
  of the orphan rule. Accepted: it is first-party-adjacent (same repository as jiff) and
  small.
- `utoipa`'s `jiff_0_2` feature name is now a version lie. It is resolved by type name,
  so `jiff` 1.x works — but a future `utoipa` release could gate it, and the drift test
  is the only thing that would catch a regression. Noted in `backend/Cargo.toml` next to
  the feature.
- `jiff::civil::DateTime` needs a manual `#[schema(...)]` override wherever it appears
  in an API DTO (two fields today). utoipa's rule (`openapi-value-type-nullable`) also
  requires the `Option<…>` form of the override.
- The vendored `kameo_es` patch diverges further from upstream than before. Restoring
  it is part of any future kameo_es upgrade.

## Alternatives Considered

- **`time` + sqlx's native `time` feature** — rejected: no serde rendering matches
  chrono's, so every persisted timestamp would need a hand-written RFC 3339 writer
  (see above).
- **Hand-written `Type`/`Encode`/`Decode` impls in `infra`** instead of `jiff-sqlx` —
  technically feasible on a local newtype, but it re-implements the
  `timestamptz`-binary (µs since 2000-01-01) encoding and its text-format fallback by
  hand. Rejected as more code and more risk than a maintained first-party bridge.
- **Keep chrono and keep the advisory ignore** — rejected by the issue: it leaves the
  crate that serializes every persisted timestamp unmaintained, and the ignore list is
  meant to hold transitive/dev-only crates (it is the first entry that was a *direct*
  workspace dependency).
- **`unmaintained = "none"`** — rejected outright: it would silently re-open every
  other unmaintained advisory, defeating issues #70/#95.
- **`bson`-based event payloads migration** — not applicable; the store uses CBOR.

## Notes

- `serde`-level equality is verified against chrono's own output, not against prose:
  the comparison that led to this decision covered 0/3/6/9-digit fractions, pre-epoch
  instants and both directions of parsing.
- Precision: PostgreSQL `timestamptz` is microsecond-precision and `jiff::Timestamp`
  is nanosecond-precision, so a store round trip truncates to the same microsecond
  bucket chrono's mapping used. `infra::db_time` has unit tests for exactly this.
- Removing the migration's temporary `RUSTSEC-2026-0543` ignore is part of the change,
  and `deny.toml` documents why the entry is gone rather than silently deleting it.
- `Cargo.lock` still *lists* `chrono` (and a second `jiff` 0.2.x) because `serde_with`,
  which `testcontainers` pulls as a **dev**-dependency, records both as optional
  feature-gated dependencies. They are not in the build graph: `cargo tree -i chrono`
  prints nothing, and `cargo deny check advisories` (which resolves the enabled graph)
  is green without an ignore. A lockfile entry for an unenabled optional dependency is
  not a supply-chain signal — the graph is.
