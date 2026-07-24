# ADR-020: Rust Component Versioning & Release Mechanics

**Status**: Proposed
**Date**: 2026-07-21
**Author**: Tobias Rademacher (@tradem); GLM-5.2 (Zhipu, hosted by neuralwatt)
**Supersedes**: —
**Related**: ADR-001 (crate dependency direction), ADR-006 (introduced v1
  endpoints — the shipped API surface this versioning feeds), ADR-017
  (architecture-test enforcement of crate boundaries), ADR-019 (additive
  v1→v2 evolution pattern), ADR-021 (API path versioning policy)
**Source change**: tracked in GitHub issue #123

---

## Context

The workspace is `edition = "2024"`, today `version = "0.1.0"` for every
crate (`core`, `infra`, `api`, `integration-tests`, `test_support`,
`architecture`, `fuzz-targets`). Dependency direction is fixed by ADR-001
(core ← infra, core ← api) and enforced source- and dependency-level by
ADR-017 (`rust_arkitect` + `cargo-deny`). The shipped artifact is the `api`
binary Docker image; the other crates are internal libraries today but may be
reused by a future second application in the broader monorepo (not
crates.io). There is no `cargo-release`, no `cargo-semver-checks`, no `MSRV`
declared, and no per-crate version discipline: a `core` change currently
flows straight into `infra`/`api` through unversioned `path` deps with no
contract gate. The committed decision is per-crate independent versions with
explicit `version = "x.y.z"` on every workspace path dep, so a `core` change
cannot silently bump consumers — they must release and repin in lockstep.
Two release surfaces must be defined: (i) the internal crate contract
(semver discipline, not a publishing mechanism, until a second consumer
exists) and (ii) the shipped artifact = the `api` binary Docker image,
versioned by Git tag + image tag. Event payloads in SierraDB are not visible
to `cargo-semver-checks`, so event-schema evolution is a distinct risk class
that needs its own gate. A local `.patches/kameo_es` dependency can change
its public surface independently of the workspace semver.

## Decision

### D1: Per-crate independent semver; path deps carry explicit `version = "x.y.z"`

Each crate owns its version in its own `Cargo.toml`. Every workspace path
dependency is declared with an explicit `version = "x.y.z"` requirement (not
omitted). The discipline is *contract* discipline, not a crates.io publishing
mechanism; it becomes load-bearing only when a second monorepo application
reuses `core` — no migration is needed then, the discipline simply starts
paying. Workspace-wide `version = "0.1.0"` in `[workspace.package]` is
retained as the *initial* value only; crates diverge from there on individual
release.

### D2: Bump rules per crate, in dependency order `core → infra → api`

Applied per the Rust semver-compatibility rules (public API across crate
boundaries; `#[doc(hidden)]` items are *not* public API):

- **MAJOR** (per crate): removal/rename of any `pub` item; trait signature
  change (added/removed method, default removed, signature retyped); `enum`
  variant removed; `struct` field removed/made `pub`→private; `MSRV` bump;
  breaking `serde` default change (an additive field whose `serde` default
  differs from prior behaviour is **MAJOR**, not additive); removal of a
  required env var from the documented runtime contract.
- **MINOR** (per crate): additive `pub` item; new `enum` variant; new
  optional `struct` field with a backward-compatible `serde` default; new
  optional env var (env vars from ADR-018/AGENTS.md — `DATABASE_URL`,
  `MIGRATOR_DATABASE_URL`, `SIERRADB_URL`, `S3_*`, `OIDC_*`, `DEV_AUTH_*`
  — added/removed per this rule); new projection column that is nullable with
  a default (read-model additive; never rename/drop within an API deprecation
  window — see ADR-021); `MSRV` unchanged.
- **PATCH** (per crate): bug fix with no public-API change; dependency *lock*
  bumps only (workspace `Cargo.lock` advancement); non-contract doc/comment
  fixes; internal refactor with identical public surface.

### D3: Lockstep coordination rule (cascade)

A breaking `core` change is **MAJOR on `core`** and forces cascading
**MAJORs** on `infra` and `api` (they consume the broken API). Release order:

1. release `core` (tag `core-vX.Y.Z`); bump-pin `core` dep in `infra` and
   `api` `Cargo.toml`; release `infra` (tag `infra-v…`); bump-pin `infra`
   in `api`; release `api`.
2. A breaking change confined to `infra`'s public surface is **MAJOR on
   `infra`** only; `api` takes a **MINOR** if it merely consumes the new
   `infra` API additively, **MAJOR** if it consumes a removed item.
3. A local `.patches/kameo_es` breaking change to its public surface is
   **contained** — it is `MAJOR` on `infra`/`api` (the only consumers) and
   is **not** a workspace-wide MAJOR; `core` is untouched (core depends on
   no `.patches` code).

### D4: Event-schema vs. projection-schema risk classes

Two distinct gates, neither visible to `cargo-semver-checks`:

- **Event schema (SierraDB stream payloads).** A breaking event-schema change
  (field removed/retyped on an existing event variant, or a variant the
  projector no longer recognises) is **non-goal-deferred** unless a
  double-write migration plan is written and tracked. While deferred, any
  additive event field is **MINOR** and *must* be optional/`#[serde(default)]`.
  Detection/mitigation gate: a `projector_version` field on the read model +
  round-trip contract tests in `crates/integration-tests` that replay a
  captured event fixture through the *current* projector binary and assert
  the projection. A new event unreadable by a deployed older projector is a
  **deploy-order** failure caught by the contract test, gated as
  **MAJOR** + rollout-order coordination (event-store migration → projector
  redeploy → old-API-version window, per ADR-021).
- **Projection schema (Postgres migrations).** A migration requiring both a
  new event *and* a backfill is **MAJOR**; rollout is coordinated by the
  release owner (infra) in the order: ship additive migration (nullable
  column + default) → ship projector that writes the new column → backfill
  → only then make the column `NOT NULL`. Drop/rename of a column consumed
  by an open API version is forbidden until that version's deprecation window
  (ADR-021) has elapsed.

### D5: Release toolchain (CI vs. local; triggers)

- **`cargo-release`** workspace flow, **local-initiated** by the release
  owner: per-crate release tag (`core-v…`, `infra-v…`, `api-v…`),
  `--dependent` to bump-lock dependents, CHANGELOG entry generated from
  conventional commits. Not a cron/PR job.
- **`cargo-semver-checks`** in **CI, gated on PR**, baseline = last tag of
  the changed crate (detected via `git` range). Fails the PR on a MAJOR drift
  with no version bump.
- **`cargo-deny`** advisories on a **cron schedule** (weekly) + on PR touching
  `Cargo.toml`/`Cargo.lock`. Bans enforced per ADR-017.
- **MSRV** declared per crate via `rust-version = "…"`. MSRV bump = MAJOR
  (D2). `cargo-hack` `--rust-version` job runs on PR for the MSRV floor.

### D6: Shipped binary image version scheme (independent of crate semver)

The `api` Docker image is tagged by **Git tag** of the form `api-vX.Y.Z`,
where `X.Y.Z` is the `api` *crate* version at the release commit.
Image tags published: `api-vX.Y.Z` (immutable, SHA-pinned digest),
`api-vX.Y` (moves to latest patch), `api-vX` (moves to latest minor). Rolling
`:latest` is **not** published (no mutable latest tag — clients pin by
`api-vX.Y.Z`). Rationale: the image is the deployed *product* artifact; the
crate version is the *contract*; binding image tag to crate semver keeps one
source of truth, while forbidding `:latest` prevents accidental drift in
deployed runtimes. A runtime/security-fix-only release with no crate-API
change is a crate **PATCH** → new `api-vX.Y.Z` image.

### D7: Update-trigger policy (separate dep updates from crate releases)

- **Dependency *version* updates** (`Cargo.lock` bumps from Dependabot /
  Renovate, advisory-driven patches) are **PATCH-level bookkeeping**, *not*
  a product release. They land via PR + `cargo-deny` + `cargo-semver-checks`;
  they do **not** cut a crate tag or image tag unless they ship a behaviour
  change to the `api` runtime (then PATCH release).
- **Crate releases** (a new `api` image tag that clients track) are cut by the
  release owner via D5/D6, on demand, gated by merged semver-checks + a green
  Tier-4 integration run (ADR-016).
- The two streams must never be conflated: a weekly `cargo-deny` advisory fix
  that lands on `main` does not, by itself, push a new image tag.

### D8: 1.0.0 graduation criterion

`0.1.0 → 0.2.0` is this proposal's first graduation step (additive contract
refinements under the same major zero). `1.0.0` is reserved until the
**Stable API contract** (ADR-021's `/v1` path version) is signed off by all
first-party clients (Flutter app, Svelte web app) against a frozen read-model
contract; `1.0.0` is *not* gated on code maturity alone.

## Alternatives Considered

- **Single workspace version (one `version` bumped in lockstep for all
  crates).** Rejected — collapses the contract between `core`, `infra`,
  `api`; a `core` additive change would force an `api` image bump, hiding
  the real deployable change behind bookkeeping and defeating the second-
  consumer reuse goal.
- **`cargo-semver-checks` as the *only* gate, no event-schema contract
  tests.** Rejected — it cannot see SierraDB event payloads or Postgres
  migration shapes (D4), so it cannot detect the highest-impact breakages.
- **Crates.io publishing now.** Rejected — there is no second consumer yet;
  publishing adds release ceremony (yanks, advisory disclosure SLAs, public
  MSRV commitments) with no payoff. Per-crate semver starts paying the day a
  second consumer appears, with no migration.
- **`:latest` rolling image tag.** Rejected — mutable tags break
  reproducible rollbacks and conflict with the SHA-pin discipline already
  applied to GitHub Actions in AGENTS.md.

## Consequences

Positive: every cross-crate change is gated and traceable; the `api` image
version is a single, immutable, semver-ordered deployable; event-schema
breakage is detected by contract tests + `projector_version` instead of being
discovered in production; second-consumer reuse of `core` costs zero
migration. Negative: release owner bears a real lockstep-coordination burden
(D3); `cargo-release` + `cargo-semver-checks` + MSRV CI must be wired and
maintained; discipline on a project with one consumer can feel ceremony-heavy
until the second consumer arrives. Operational impact: a new
`projector_version` column on each read-model projection + a fixture-replay
contract test in `crates/integration-tests` (extends ADR-014/ADR-016). CI
adds a PR-gated `cargo-semver-checks` job and a weekly `cargo-deny` schedule.
Cross-links: feeds ADR-021 (image `api-vX.Y.Z` is what an API path-version
deprecation window is served from); tightens ADR-001/ADR-017 boundary
enforcement with a version gate, not just a structural one.
