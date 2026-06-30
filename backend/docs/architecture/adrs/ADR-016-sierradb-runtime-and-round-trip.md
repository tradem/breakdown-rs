# ADR-016: SierraDB runtime & round-trip (image path, dev/prod runtime, Tier-4 tests)

- **Status:** Accepted
- **Date:** 2026-06-26
- **Supersedes:** the "SierraDB container image availability unknown" note in ADR-015
- **Related:** ADR-011 (observability / OpenTelemetry), ADR-014 (Testcontainers), ADR-015 (SierraDB event store + Postgres projections)
- **Source change:** `openspec/changes/sierradb-runtime-and-round-trip`

## Context

`persistence-layer-v1` (ADR-015) shipped the Postgres projection schema, read
adapters, write ports, and API wire-up, and `main.rs` already boots a real
`CommandService` over a RESP3 connection plus the four `PostgresProcessor`
projectors. But it deliberately deferred three things:

1. Whether SierraDB publishes a container image (ADR-015 left this unknown).
2. A runnable dev/prod runtime compose covering both tiers.
3. An end-to-end Tier-4 round-trip test (`command → SierraDB → projector → Postgres projection → read query`).

This ADR records the decisions that close those gaps.

## Decision

### 1. Container image path — use the upstream `tqwewe/sierradb` image

Investigation result (task 1.1 of the change): SierraDB **does** publish an
upstream Docker image — **`tqwewe/sierradb`** on Docker Hub
(https://hub.docker.com/r/tqwewe/sierradb). SierraDB's own README recommends
`docker run -p 9090:9090 tqwewe/sierradb`. The image is built from the upstream
`sierra-db/sierradb` repo's `Dockerfile` (multi-stage `rust:1.91` build →
`debian:bookworm-slim` runtime, exposes port 9090, RESP3).

**Pinned tag:** `tqwewe/sierradb:0.3.1` — the latest SierraDB release tag
(`v0.3.1` on GitHub), matching the ADR-015 "v0.3.x" note and the `kameo_es` /
`sierradb-client` Cargo pins in use:

- `kameo_es` → `git+https://github.com/sierra-db/kameo_es?branch=main` (commit `89f200d`)
- `sierradb-client` → crates.io `0.1.0`
- `redis` → `0.32.7` (RESP3 transport)

Because an upstream image exists, the build-from-source `Dockerfile` task (1.2)
is **N/A**. If a future `kameo_es`/SierraDB pin diverges from a published
`tqwewe/sierradb` tag, build-from-source instructions are documented below as a
fallback (maintenance cost: rebuild on every SierraDB release; the upstream
`Dockerfile` is self-contained).

**Fallback build-from-source** (only if the upstream image is unavailable for a
required tag): clone `sierra-db/sierradb` at the matching tag and run
`docker build -t sierradb:<tag> .` using the repo's `Dockerfile`. Maintenance
cost: one rebuild per SierraDB release; no CI publishing required for dev/prod
since the upstream image is the default.

### 2. Dev runtime

Extend `backend/docker-compose.dev.yml` with a `sierradb` service pinned to
`tqwewe/sierradb:0.3.1`, exposing RESP3 on host port `9090`, with a named volume
for `/app/data`. `main.rs` already reads `SIERRADB_URL` from the environment
(default `redis://127.0.0.1:6379`); the documented dev value is
`redis://127.0.0.1:9090` (RESP3).

### 3. Production runtime — docker-compose

Production runtime artifact is **docker-compose** (chosen over k8s manifests
for v1 simplicity; upgradeable to k8s later). The production compose
(`docker-compose.prod.yml`) covers Postgres + SierraDB with:

- Pinned tags: `postgres:16-alpine` and `tqwewe/sierradb:0.3.1`.
- Persistent named volumes for both tiers.
- Healthchecks for both tiers.
- Backup/recovery runbooks (pg_dump for Postgres; volume snapshot / `--dir` copy
  for SierraDB) documented in the runbooks section of `backend/docs/operations/`.
- OpenTelemetry trace export (ADR-011): OTLP trace export via `tracing-opentelemetry`
  is implemented — the API binary exports spans when `OTEL_EXPORTER_OTLP_ENDPOINT` is
  configured. Metrics export remains deferred (the env vars are declared but
  non-functional until a follow-up change). Both tiers expose health endpoints
  consumed by the compose healthchecks.

### 4. Tier-4 round-trip test

Extend the ADR-014 testcontainers harness (in `crates/integration-tests`) with a
small local `testcontainers::Image` impl for `tqwewe/sierradb:0.3.1` (no upstream
testcontainers module exists; one-harness rule preserved). The Tier-4 test
starts both containers, builds a `CommandService` over SierraDB, spawns the four
projectors, issues a `CreateScene` command, and polls the `projection_scene`
read adapter until the row appears (bounded-retry eventual consistency). A
second variant (`eappend_character_assigned_twice_is_idempotent` in
`crates/integration-tests/tests/sierradb_round_trip.rs`) verifies projector
idempotency under event redelivery — appending a `CharacterAssigned` event
twice with identical payload and asserting the projection row remains
unchanged (no duplicate `assigned_characters` entries, no version drift).
This test was implemented as part of the `add-idempotency-redelivery-test`
change, closing task 4.3 of the original `sierradb-runtime-and-round-trip`
change. Tier-4 tests
remain excluded from `cargo-mutants` (`.mutants.toml`).

## Alternatives Considered

- **Build-from-source `Dockerfile` as the default:** rejected — upstream image
  exists and is maintained by the SierraDB community; rebuilding adds cost.
- **k8s manifests for production:** deferred — docker-compose is sufficient for
  v1 and keeps the dev/prod surface symmetric; k8s can replace compose later
  without changing the pinned-tag/policy decisions.
- **Separate test-infrastructure crate for SierraDB tests:** rejected per
  ADR-014's one-harness rule; extend the existing `crates/integration-tests`.

## Consequences

- ADR-015's "image unknown" note is **superseded**; the pinned tag is
  `tqwewe/sierradb:0.3.1` for both dev and prod.
- Dev boot sequence: start both tiers → migrate Postgres → run the API binary
  (documented in `backend/AGENTS.md` and the repo `README.md`).
- CI must have Docker available to run the Tier-4 suite; the ADR-014
  integration-test workflow is extended to start both containers.
- **RESP3 ≠ Redis caveats:** SierraDB speaks RESP3 only (`version` → 3); it is
  **not** a Redis-cluster node and does not implement every Redis command. Use a
  RESP3-capable `redis::Client` (`protocol = 3`); do not point Redis-cluster
  tooling at it. See the runbooks in `backend/docs/operations/`.
- Upgrading SierraDB requires bumping the tag in dev compose, prod compose, the
  testcontainers helper, and re-pinning `kameo_es`/`sierradb-client` in
  `Cargo.toml`; the Tier-4 test guards compatibility.
