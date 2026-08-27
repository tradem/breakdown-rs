## Context

`crates/infra/src/projectors/mod.rs` spawns four projector subscription loops via the `run_projection_stream!` macro. Each macro expansion builds a SierraDB `subscription_manager`, an `event_handler_stream`, and `tokio::spawn`s `stream.run(&mut actor_ref)`. The spawned future is fire-and-forget: on error it only emits a `tracing::error!` and then the task ends. There is no in-process recovery until the whole API process is restarted and re-enters `main.rs`'s boot sequence. This is the resilience gap recorded in GitHub issue #30.

ADR-015 already guarantees correctness on recovery — per-processor SierraDB checkpoints plus idempotent projection upserts mean replay is always safe. What is missing is *liveness*: a per-loop supervisor that restarts the subscription within the running process so a transient SierraDB blip or a panic does not silently stall a projection until the next deploy/restart.

The surviving `kameo::ActorRef<PostgresProcessor>` stays valid across stream restarts — the actor is independent of the subscription task; only the `subscription_manager` + `event_handler_stream` are rebuilt on each restart, which is what the macro already does once per spawn.

## Goals / Non-Goals

**Goals:**
- On task death (error return from `stream.run()` or task panic), the subscription loop is restarted from its SierraDB checkpoint within the same process, with backoff.
- Restart attempts are bounded with a retry budget so a permanently-broken projector does not spin forever; budget exhaustion is a loud, observable signal.
- Per-projector health is observable via structured `tracing` spans (category, attempt count, last error, backoff delay) so a dead projector is visible in logs/metrics without a new HTTP port.
- All changes live in `crates/infra`; no `core` port and no `api` change.

**Non-Goals:**
- A new HTTP liveness/readiness endpoint or Prometheus scrape surface in the API. The health signal is `tracing`-based for v1; a future change can expose it if needed.
- Cross-projector coordination (e.g. "if all four are down, restart the API") or global backpressure.
- Changes to the `PostgresProcessor` actor lifecycle, checkpoint table, or projection migrations.
- Subscribing/replaying in a different order — restart reuses the existing `event_handler_stream` builder unchanged.

## Decisions

### Decision 1: Supervisor as a per-loop `tokio::spawn` wrapper, not a new actor
Wrap the existing macro body in a `loop { ... }` that, on `Err`/panic of `stream.run`, sleeps with exponential backoff + jitter, then rebuilds the `subscription_manager` + `event_handler_stream` and re-runs. Implement as a small `supervisor.rs` helper module (`run_with_restart`) rather than introducing a new `kameo::Actor` for supervision.

**Why over alternatives:** A dedicated supervisor actor would add a second actor system concept with no benefit — the supervised unit is a single future, and `tokio` task supervision is the idiomatic fit. Keeping it as a helper preserves the existing `spawn_*_projector` signatures.

**Alternatives considered:**
- New `kameo::Actor` `ProjectorSupervisor` that owns the stream: rejected — duplicates kameo actor lifecycle.
- `tower` retry / `backoff` crate: rejected — adds a dependency for a ~40-line loop; `tokio::time::sleep` + a jitter function is sufficient and dependency-free.

### Decision 2: Exponential backoff with cap and jitter, plus a bounded retry budget
On each failure, wait `min(base * 2^attempt, max_delay) + rand_jitter` then retry. After `max_attempts` consecutive failures within a `reset_window`, stop retrying and emit a `tracing::error!` at `ERROR` level with the category and last error; a single subsequent success resets the attempt counter.

Sensible defaults (tunable via constants, not env vars for v1): base = 500ms, max_delay = 30s, max_attempts = 10, reset_window = 5min. A successful `stream.run` epoch (the stream ran longer than `reset_window`) clears the consecutive-failure counter.

**Why:** Unbounded retry masks a permanently-broken projector (e.g. a deleted projection table) as quiet churn; a bounded budget forces a loud, observable terminal state that ops can alert on, matching the issue's "liveness probe" acceptance criterion.

**Alternatives considered:**
- Unlimited retry: rejected — silently spinning backoff is worse than a dead-but-flagged projector.
- Reset budget on every success regardless of duration: rejected — a stream that dies every 100ms forever would never trip the budget. The `reset_window` reset condition avoids that.

### Decision 3: Health signal via `tracing`, no new port
Emit `tracing::warn!` (category, attempt, delay) on each restart, `tracing::error!` on budget exhaustion, and a `tracing::info!` on successful (re)start. Fields use the standard `projector.category`, `projector.attempt`, `projector.delay_ms` names so the existing OpenTelemetry tracing (see `opentelemetry-tracing` spec) can surface them.

**Why over alternatives:** The repo already standardises on `tracing` + OpenTelemetry (ADR-015 references, `opentelemetry-tracing` capability). A dedicated metrics/health port in `infra` would re-implement what `tracing` already provides and would risk crossing the "no projector abstraction in core" / "api does not invoke projectors" boundary from `persistence-projections`.

### Decision 4: Bullet/Catch panics with `AssertUnwindSafe` + `catch_unwind`
`stream.run()` is `!UnwindSafe`. Because the supervisor owns the future across restarts, wrap the per-epoch run in `std::panic::catch_unwind(AssertUnwindSafe(...))` so a panic in projection handling does not tear down the supervisor task — instead it is treated as a failure and fed to the same backoff/restart path.

**Why:** Parity between `Err`-return and panic-kill paths. Without this, a panic in one projector's `handle` re-kills the supervisor on every restart and there is no recovery until process restart — exactly the gap being closed.

**Trade-off:** `AssertUnwindSafe` asserts no shared-mutable-state soundness issue across a panic; acceptable because each epoch rebuilds its own `subscription_manager` and the `actor_ref` is `Clone`able, and the alternative (let panics propagate) is the current broken behavior.

## Risks / Trade-offs

- **[Risk] `AssertUnwindSafe` hides a panic-induced invariant violation** → Mitigation: emit the panic payload + backtrace in the restart `tracing::warn!`; the bounded budget turns recurring panics into a loud terminal `error!`.
- **[Risk] HMS/constant defaults are wrong for production** → Mitigation: keep them as named `const`s in `supervisor.rs` (not magic numbers, not env vars), trivially adjustable in a follow-up; documented in `tasks.md`.
- **[Risk] Tight backoff wipes a flapping SierraDB harder** → Mitigation: cap at 30s with jitter; the budget will trip on true flapping and surface it.
- **[Trade-off] No HTTP liveness endpoint** → acceptable for v1 per the issue's "or" acceptance (restart + observability covers it); future change can add an endpoint reading the `tracing`-equivalent health if needed.
- **[Trade-off] Per-loop restart does not heal a corrupted checkpoint** → out of scope; checkpoint corruption is a process-restart/postgres-recovery concern under ADR-015.

## Migration Plan

No data migration. Behaviour change only.

- Deploy: drop-in. `spawn_*_projector` signatures and return types are unchanged; `api/main.rs` calls compile unchanged.
- Rollback: revert the change; projectors return to the current fire-and-forget behavior (issue #30 re-opens). No schema/ADR change to undo.
- Observability transition: after deploy, watch for `projector.attempt` warnings; tune `const`s if a category flaps in real traffic.

## Open Questions

- Do we want the retry-budget `const`s surfaced as env vars (`PROJECTOR_MAX_ATTEMPTS`, etc.) in a follow-up? Decided **no** for this change; deferred until real production data justifies tunability.
- Should successful-but-old checkpoints eventually alert? Out of scope here; left to the future liveness-endpoint change if it is ever needed.
