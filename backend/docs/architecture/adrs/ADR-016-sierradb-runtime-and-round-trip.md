<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# ADR-016: SierraDB runtime & round-trip (image path, dev/prod runtime, Tier-4 tests)

**Status**: Accepted
**Date**: 2026-06-26
**Author**: Tobias Rademacher (@tradem)
**Supersedes**: the "SierraDB container image availability unknown" note in ADR-015
**Related**: ADR-011 (observability / OpenTelemetry), ADR-014 (Testcontainers), ADR-015 (SierraDB event store + Postgres projections), ADR-036 (ES-native reservation streams), issue #901 (append-latency baseline)
**Source change**: `openspec/changes/sierradb-runtime-and-round-trip`

---

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
remain excluded from `cargo-mutants` (`.cargo/mutants.toml`).

### 5. Historical deviation — Tier-4 bypassed `CommandService` (issue #25, resolved)

**Resolved (2026-09-21, issue #25):** the deviation is closed. A Tier-4 variant
(`command_service_create_scene_round_trips_via_escan` in
`crates/integration-tests/tests/sierradb_round_trip.rs`) now drives a real
`CreateScene` + `UpdateSceneDetails` command through the production
`SceneCommandsImpl` adapter onto the live write path (`CommandService` →
`EntityActor` → `on_start`/`resync_with_db` → append), verifies the persisted
events via raw `ESCAN` reads, and asserts the projector catch-up through the
read adapter — the exact chain the `sierradb-round-trip-testing` spec mandates.

**Resolution note:** the upstream bug never received an upstream fix — v0.3.1
remains the latest `tqwewe/sierradb` tag (verified 2026-09-21). The
`PartitionUnavailable` / `broken pipe` failure on the `EntityActor`'s
`resync_with_db` read no longer reproduces because the *client stack* moved:
vendored `kameo_es` 0.2.0 (path-patched under `.patches/kameo_es`),
`sierradb-client` 0.3.1, and `redis` 1.7. Empirically re-verified against the
pinned `tqwewe/sierradb:0.3.1` container with 5/5 stable runs.

**Historical context:** as shipped by PR #24, the Tier-4 tests appended events
directly to SierraDB via `EAPPEND` (cborium-CBOR-encoded `SceneEvent`
payloads) and only verified the `projector → Postgres projection → read query`
segments against the real tiers — a deliberate workaround for the then-failing
read path. The `EAPPEND`-based tests are retained as additional projector
idempotency/redelivery coverage (the idempotency-under-redelivery variant requires
raw appends by design).

### 6. Append latency — sync scheduling and the per-event confirmation fsync (issue #901)

Measured 2026-11-12 on the dev host (btrfs on NVMe), throwaway container, raw RESP3
one connection, 1 KB payload, `EMAPPEND` with strict versioning. Root cause of the
reported "one append costs ~50 ms" has **two layers**; both are measured and
source-anchored, and the second one is configurable — which is why this section is
a deployment decision, not a note.

**Baseline (committed, reproducible):** `scripts/bench-sierradb-append.py` — raw
RESP3, no `redis-cli`, asserts the RESP3 map reply shape before counting a sample
(an `INVALIDARG` error reply is fast and would otherwise look like a great number).
Run against a throwaway container, never the dev store:

```bash
docker run -d --rm --name bench-sierradb -p 19090:9090 \
    tqwewe/sierradb:0.3.1 --dir /app/data
scripts/bench-sierradb-append.py --iterations 300 --parallel-rounds 20
```

Pinned image at its **default** config (300 samples/case, ms):

| Case | min | p50 | p95 |
|---|---|---|---|
| 1 event, isolated (100 ms idle gap) | 3.60 | 5.36 | 54.28 |
| 5 events, isolated | 9.84 | 10.77 | 58.40 |
| 20 events, isolated | 31.77 | 41.20 | 91.39 |
| **1 event, back-to-back (no gap)** | 3.70 | **49.97** | 54.95 |
| 8 appends in flight (burst wall) | 38.67 | 53.05 | 56.53 |
| 16 appends in flight (burst wall) | 29.74 | 50.29 | 56.95 |
| sustained, 8 connections | 3865 appends / 6 s → **639 appends/s** | | |

With the adopted setting (`SIERRA_SYNC.IDLE_INTERVAL_MS=4`, same recipe):

| Case | min | p50 | p95 |
|---|---|---|---|
| 1 event, isolated | 3.63 | 4.24 | 11.12 |
| 5 events, isolated | 9.95 | 10.87 | 18.02 |
| 20 events, isolated | 33.38 | 43.10 | 49.35 |
| **1 event, back-to-back (no gap)** | 6.64 | **9.12** | 10.25 |
| 8 appends in flight (burst wall) | 10.15 | 15.54 | 18.07 |
| 16 appends in flight (burst wall) | 15.27 | 20.67 | 23.54 |
| sustained, 8 connections | 4748 appends / 6 s → **790 appends/s** | | |

**Layer 1 — the ack is gated on a durable write, and a single event costs *two*.**
`writer_thread_pool.rs` sends the reply only after
`sync_rx.wait_for(write_offset)` resolves, i.e. after the segment's
`File::sync_data()`. On top of that, the cluster write path runs a
"Phase 5: Write Confirmation" (`sierradb-cluster/src/write/transaction.rs`) that
calls `set_confirmations` for **every event offset**; each of those rewrites the
commit record's header and syncs again (`seglog::read::replace_header_with` →
`file.sync_data()`), on a reader thread, before the ack. `strace` on the pinned
image: 1 event → **2** `fdatasync` on `…/data.evts`, 5 events → **6**. So one
append is `1 + N` fsyncs (`N` = events in that append). That is the floor: a
20-event append cannot be faster than 21 syncs, and it is why the 20-event case
stays ~40 ms even after tuning.

**Layer 2 — the sync *schedule*, which is where the ~50 ms tail comes from.**
`WriterSet::should_sync()` syncs inline only if `bytes_since_sync >=
sync.min_bytes` (4096), or `unflushed_events >= sync.max_batch_size` (50), or
`last_synced.elapsed() >= sync.interval_ms` (5 ms). Otherwise the append waits for
the `writer-pool-syncer` poll, which sleeps `sync.interval_ms` (5 ms) when a write
was seen between the poll and the flag swap and `sync.idle_interval_ms` otherwise
— default `10 × interval_ms`, capped at 1 s, i.e. **50 ms**. A chatty sequential
client (create scene → assign 3 characters → 2 beats) sits in the idle regime
most of the time and pays a full tick per append; concurrent appends collapse into
one tick, which is why bursts looked healthy (16 appends in ~50 ms).

**Answers to the five questions from the issue:**

1. **Is the tail periodic?** Yes — it is one sync tick, not per-byte work. A
   *wall-clock* phase test does not see it (`ack mod 50` is uniform, mean
   resultant `R ≈ 0`), because the syncer re-bases its own grid every loop
   (`last_ran = Instant::now()`), so no absolute phase exists. The periodicity is
   visible instead as (a) one ack per tick — sequential inter-ack spacing is
   ~50 ms while the append itself needs ~4 ms — and (b) a sharp step in the
   idle-gap sweep: gap 0 ms → 48.98 ms, gap 2 ms → 52.99 ms, gap ≥ 4 ms →
   3.8–4.1 ms p50, i.e. the boundary is `sync.interval_ms` (5 ms), the difference
   between "sync inline" and "wait for the poll".
2. **How many durable writes per append?** `1 + N` fsyncs (above), counted with
   `strace -f -y -e trace=fsync,fdatasync` on the container.
3. **Is it the container filesystem?** It changes the fsync floor and which
   regime dominates, but it is not the 50 ms. At an identical config
   (`interval_ms=2`, `idle_interval_ms=1`): overlayfs (image's own `/app/data`)
   3.94 ms, host bind mount 3.09 ms, tmpfs 2.05 ms p50. At the *default* config a
   host bind mount happened to stay in the 5 ms active regime (5.04 ms p50, no
   sample ≥ 10 ms), while both overlayfs and a named volume (the shape this repo's
   compose files use) sat at 49.95–49.97 ms. We did not establish why the mount
   type flips the regime; with the adopted setting the question is moot.
4. **Is it configurable?** Yes. `sync.interval_ms`, `sync.idle_interval_ms`,
   `sync.max_batch_size`, `sync.min_bytes` are config-file / env settings with no
   CLI flags (hence absent from `--help`). Nested keys map from env as
   `SIERRA_SYNC.IDLE_INTERVAL_MS` (literal dot — verified by feeding a value the
   validator rejects). Two upstream quirks to know: (a) the validator's condition
   is inverted relative to its own message — `idle_interval_ms` must be
   **strictly less** than `interval_ms`, so 4 is the lowest accepted idle value
   while `interval_ms` stays at its default 5; (b) there is **no upstream
   release after v0.3.1** — GitHub `HEAD` is the v0.3.1 commit and Docker Hub has
   no newer tag — so this is not fixed upstream.
5. **Does it scale with data?** No. A 300 MB prefilled store (~1.1 GB on disk,
   named volume, default config) measures 50.10 ms p50 on the same case that
   measures 49.95 ms fresh. The store cost follows the sync schedule, not size.

**Decision — adopt the idle interval, keep durability exactly as it is.**
`docker-compose.dev.yml` and `docker-compose.prod.yml` set
`SIERRA_SYNC.IDLE_INTERVAL_MS=4` on the `sierradb` service. This is **not** a
durability downgrade: the store still fsyncs before it acks (Layer 1 is untouched)
— the knob only shortens how long an idle append waits for the next poll, which
removes the 50 ms regime (p50 49.97 → 9.12 on the sequential case) and raises
sustained throughput (639 → 790 appends/s) because more appends share a tick
instead of queueing behind a 50 ms backoff. The active-path batching
(`interval_ms`, `max_batch_size`, `min_bytes`) is deliberately left at its
defaults: lowering `interval_ms` to 2 as well would take the sequential case to
~4 ms, but it shortens the inline-sync window on the hot path and bought no
measurable throughput (789.7 vs 790.6 appends/s), so it is not adopted.

**Explicitly rejected:** disabling fsync / relaxing durability in production for
speed; moving writes off the event store; batching several commands into one
append at the client (ADR-015 keeps one append per state change — the cost model
now argues *for* the domain practice of one command per aggregate change with the
command's full event batch, and *against* chatty per-beat / per-figure commands).

**Consequences for write-path design:** the cost model is committed with the
baseline — see `.github/instructions/write-path-cost-model.instructions.md`. Any
change to the SierraDB pin, the two compose runtimes or the `sync.*` settings is
measured against the tables above with `scripts/bench-sierradb-append.py`.

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
