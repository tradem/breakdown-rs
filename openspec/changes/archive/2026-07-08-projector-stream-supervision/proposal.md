## Why

The projector subscription loops spawned in `crates/infra/src/projectors/mod.rs` die silently when their `tokio::spawn`ed `stream.run()` task panics or hits a transient SierraDB/Postgres outage. ADR-015's "idempotent replay from checkpoint" guarantee only kicks in on *process* restart — within a running API a dead projector silently stops catching up, stalling the read model until the whole process is restarted (GitHub issue #30). A supervisor with backoff restart and a health signal closes this resilience gap.

## What Changes

- Wrap each projector's SierraDB subscription stream in a supervised loop that, on task error or panic, restarts the subscription from the last checkpoint with an exponential backoff (capped) and jitter.
- Surface projector health so a dead/stalled projector is observable: structured `tracing` events on restart attempts/backoff exhaustion, and a per-projector last-processed-seq/no-restart counter accessible to a future liveness probe.
- Keep all restart logic inside `crates/infra` (no new `core` port); the actor spawning API surface (`spawn_*_projector`) stays unchanged so `api/main.rs` wiring is unaffected.

## Capabilities

### New Capabilities
- `projector-supervision`: Supervised lifecycle for projector subscription loops — backoff restart on error/panic, bounded retry budget, and restart/health observability.

### Modified Capabilities
- `persistence-projections`: The existing "independent failure isolation" requirement assumed process-level restart; the per-task restart-on-death behavior is now codified as an explicit requirement of the projection runtime.

## Impact

- **Code:** `crates/infra/src/projectors/mod.rs` (the `run_projection_stream!` macro and the four `spawn_*_projector` functions); possibly a new `supervisor.rs` helper module in the same directory.
- **Dependencies:** No new crates expected — implemented with `tokio::time` for backoff and `tracing` (already in use). No changes to `kameo_es`/`sierradb-client` versions.
- **Architecture boundaries:** Stays entirely within `crates/infra`; `core` and `api` are untouched (no new port traits, no API contract change). `api/main.rs` boot sequence unchanged.
- **ADRs:** Aligns with and extends ADR-015's checkpoint-replay guarantee from "process restart" to "in-process per-loop restart". No new ADR required; a brief note in `design.md` ties this to ADR-015.
- **Testing:** New unit/integration coverage for restart-on-error, backoff progression, and budget exhaustion; no Tier-4 round-trip change.
