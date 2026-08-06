<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Release runbook — per-crate versions & the `api` image (ADR-020 / ADR-021)

This runbook is the operational companion to
[ADR-020](../architecture/adrs/ADR-020-rust-component-versioning.md) (per-crate
semver + release mechanics) and
[ADR-021](../architecture/adrs/ADR-021-api-versioning.md) (HTTP API path
versioning & deprecation lifecycle). The release owner follows it for every
release; the two streams below must **never be conflated** (ADR-020 D7).

## 0. The two release streams

| Stream | Trigger | Artifact | Tag |
|--------|---------|----------|-----|
| Dependency bookkeeping | Dependabot / advisory PRs | `Cargo.lock` bump only | **none** (PATCH-level, ADR-020 D7) |
| Crate release | Release owner, on demand | per-crate Git tag + `api` image | `core-v…`, `infra-v…`, `api-v…` |

A weekly advisory fix that lands on `main` does **not** push an image tag by
itself (ADR-020 D7).

## 1. Prequisites for a release

- `cargo-semver-checks` green on the release PR (CI: `.github/workflows/semver-checks.yml`,
  baseline = last tag of the changed crate).
- Tier-4 integration run green (`cargo test -p integration-tests`).
- `cargo-deny check advisories bans licenses sources` green (ADR-017).
- MSRV job green (`rust-version = 1.94`, ci.yml).

## 2. Cut a per-crate release (local, `cargo-release`)

`cargo-release` is configured workspace-wide (`[workspace.metadata.release]`):
`shared-version = false`, tag name `{{crate}}-v{{version}}`, and only `core`,
`infra`, `api` opt in via `[package.metadata.release] release = true`.

Breaking changes cascade in dependency order **`core → infra → api`**
(ADR-020 D3) and must be released in that order, re-pinning each consumer:

```bash
cargo release -p breakdown_core --dependent   # tag core-vX.Y.Z
cargo release -p infra --dependent            # tag infra-vX.Y.Z
cargo release -p api --dependent              # tag api-vX.Y.Z
```

- A breaking `core` change is MAJOR on `core` **and** forces cascading MAJORs
  on `infra` and `api` (D3).
- A `.patches/kameo_es` public-surface break is contained: MAJOR on
  `infra`/`api` only, `core` untouched (D3).
- The CHANGELOG entry is generated from conventional commits by the release
  process and must name every moved route plus its `/v{n+1}` replacement when
  a path version ships (ADR-021 D4.3).

## 3. Publish the `api` image

Pushing the `api-vX.Y.Z` Git tag triggers
`.github/workflows/release-image.yml`, which builds the Dockerfile and pushes:

- `ghcr.io/<org>/<repo>:api-vX.Y.Z` — immutable, SHA-pinned digest
- `ghcr.io/<org>/<repo>:api-vX.Y` — moves to the latest patch
- `ghcr.io/<org>/<repo>:api-vX` — moves to the latest minor

There is **no `:latest`** (ADR-020 D6). Clients pin by `api-vX.Y.Z`.

A runtime/security-fix-only release with no crate-API change is a crate PATCH
→ new `api-vX.Y.Z` image; the path version stays put (ADR-021 D2).

## 4. HTTP API path versioning (ADR-021)

- The API path version lives in the URL prefix (`/v1/…`, mounted in
  `crates/api/src/routes/mod.rs`) and in the OpenAPI `info.version` +
  context-path prefixing (`crates/api/src/lib.rs::api_doc`).
- **Path version major** = count of breaking wire revisions since `/v1`; the
  `api` crate version is independent and ≥ path-version major (ADR-021 D2).
- A **MINOR/additive** wire change keeps the path version. Anything that
  removes/renames a route, field, status code, auth requirement, or shifts a
  `serde` default is **MAJOR** → new `/v{n+1}` (ADR-021 D3/D5).

### Deprecation window (minimum 8 weeks)

When `/v{n+1}` ships:

1. `/v{n}` stays served concurrently for **≥ 8 weeks** (longer until every
   first-party client has cut a release against `/v{n+1}`).
2. Register the deprecated `/v{n}` prefixes with their `Sunset` HTTP-date in
   `DeprecationRegistry` (`crates/api/src/versioning.rs`) — every response of
   a deprecated route then carries `Deprecation: true` and `Sunset: <date>`.
3. At most the two most recent path majors are served concurrently; `/v{n-1}`
   is removed when `/v{n+1}` ships and `/v{n}`'s window has elapsed.

### Read-model additivity during the window (ADR-021 D6)

- Projection migrations within an open window are **strictly additive**: new
  columns nullable with a default. **Never rename or drop** a column consumed
  by an open API version.
- A drop/rename is deferred until the version sunsets, then executed as a
  follow-up MAJOR migration (ADR-020 D4).
- The wire-contract fixture-replay tests
  (`crates/integration-tests`, `wire_contract_fixture_tests`) gate `serde`
  shape drift per `/v{n}` route: a `serde`-default-differs change is MAJOR
  (ADR-021 D5) and fails the PR.
- The event-schema fixture-replay tests
  (`crates/integration-tests`, `event_fixture_contract_tests`) replay captured
  event fixtures through the current projectors and assert the projection
  including `projector_version` (ADR-020 D4) — a new event unreadable by a
  deployed older projector is a deploy-order failure.

## 5. Deploy-order coordination for a breaking wire/event change

1. Ship the additive projection migration (nullable column + default).
2. Ship the projector that writes the new column (bump `PROJECTOR_VERSION`).
3. Backfill; only then make the column `NOT NULL` (ADR-020 D4).
4. Ship `/v{n+1}` + the deprecation headers; keep the prior image deployable
   until the sunset date (ADR-021 cross-link).
