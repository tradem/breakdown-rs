## Context

PR #164 added Vault-backed SSE-C photo storage (spec `photo-sse-c-encryption`).
At API boot, `main.rs` resolves the Vault SSE-C key once via
`VaultClient::photo_sse_c_key()`. When Vault is unreachable, it constructs
`OpenDalPhotoStorage::unavailable(...)`, which permanently fails closed until
the next API restart.

SierraDB subscriptions used by the patched `kameo_es` `EventHandlerStream` are
**ephemeral**: a new `EPSUB * FROM LATEST` (saga `start_from()` returns an empty
`HashMap`) does not redeliver unacked events from a dropped subscription.
`EventHandlerStream::next()` currently batch-acks the *received* high-water
cursor every 8000 events **before** the events are processed. A transient
`ServiceUnavailable` from photo storage therefore crashes the saga epoch and
permanently drops the failed event. Only the Postgres-based `PostgresProcessor`
projectors have a durable checkpoint; the sagas do not.

Acceptance criteria from issue #165:
1. Vault outage at boot → photo storage resumes without an API restart once Vault recovers.
2. Transient `ServiceUnavailable` never drops thumbnail / bytes-cleanup work.
3. The SierraDB cursor advances only after successful event processing.
4. Deterministic tests for Vault recovery and failed-event redelivery.
5. Fail-closed remains: no plaintext / SSE-S3 fallback.

## Goals / Non-Goals

**Goals:**
- Lazily resolve the Vault SSE-C key on demand and cache the built operator;
  retry resolution on subsequent operations after a failure.
- Retry transient `ServiceUnavailable` inside the photo sagas with exponential
  backoff, never losing the event.
- Ack the SierraDB cursor only after successful handler processing.
- Deterministic unit tests for all three behaviors.

**Non-Goals:**
- Durable checkpoints for sagas (a separate change; the in-loop retry makes them
  unnecessary for transient storage failures).
- Retrying non-transient errors (corrupt images, S3 network errors surfaced as
  `ValidationError`, misconfiguration) — those keep the existing crash →
  supervisor-restart behavior.
- Changing the other sagas (deletion, continuity, season seeding, report
  triggers) — they do not touch photo storage.

## Decisions

### D1: Recoverable, lazy SSE-C key resolution in `OpenDalPhotoStorage`

`OpenDalPhotoStorage` gains a shared inner state:

```rust
struct RecoverableInner {
    op: tokio::sync::Mutex<Option<Operator>>,   // lazy cache
    key_source: Arc<dyn PhotoStorageKeySource>, // resolves the customer key
}

#[async_trait]
pub trait PhotoStorageKeySource: Send + Sync + std::fmt::Debug {
    async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError>;
}
```

`operator()` (made `async`) becomes: check cache → on miss, call
`key_source.resolve()`, build the SSE-C operator via
`s3_builder_with_customer_key`, cache it, return it. Resolution failures are
**not** cached, so the next operation retries automatically. Failures propagate
as `DomainError::ServiceUnavailable` (fail-closed). The operator is cached only
once, and only with SSE-C — never plaintext.

Constructors:
- `recoverable(key_source)` — production (main.rs).
- `new(op)` / `with_bucket(op, bucket)` — unchanged, test-support.
- `unavailable(reason)` — unchanged, fail-closed test/deprecated path.

`VaultClient` implements `PhotoStorageKeySource` (delegates to the existing
`photo_sse_c_key()`).

Why lazy resolution over a background heal-task? A background task adds a
periodic tick and lifecycle management; lazy resolution needs none — the first
post-recovery operation naturally rebuilds the operator, and every operation
before recovery fails closed with `503`. The issue explicitly allows
"lazy resolution or bounded retry".

### D2: Saga retry on transient `ServiceUnavailable`

A helper in `crates/infra/src/photo/sagas/mod.rs`:

```rust
pub async fn retry_transient<F, Fut>(op: F) -> anyhow::Result<()>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = anyhow::Result<()>>,
```

It loops while the error downcasts to `DomainError::ServiceUnavailable`,
sleeping `supervisor::compute_backoff(attempt, 30s)` between attempts. There is
**no attempt budget for transient errors**: giving up would drop the saga
event permanently (ephemeral subscription). A permanent error propagates
immediately and keeps the existing supervisor-restart behavior.

Both `PhotoThumbnailSaga.process_upload` and `PhotoBytesCleanupSaga` wrap their
body in `retry_transient`. This is safe because a `ServiceUnavailable` can only
be produced while the operator cache is empty (Vault down), i.e. **no storage
operation has succeeded yet** — there is no partial progress to corrupt on
retry. The photo commands (`NormalizeOriginal`/`GenerateVariant`) are dispatched
with `ExpectedVersion::Any` only after storage succeeded, so they are never
re-dispatched in the retry path.

The sagas' storage `map_err(|e| anyhow::anyhow!("{e}"))` calls change to
`anyhow::Error::new(e)` so `downcast_ref::<DomainError>()` can find the
`ServiceUnavailable` variant in the error chain.

### D3: Ack only after successful processing (`kameo_es` patch)

`EventHandlerStream` changes:
- `next()` no longer acknowledges (remove the pre-processing batch ack).
- `UnprocessedEvent` carries the event's `cursor` (from `SierraMessage::Event`).
- `run()` / `process_next()` acknowledge the cursor **after**
  `processor.process_event(...)` succeeds.
- Batch acknowledgement is preserved for throughput: a small testable
  `AckTracker` records the high-water cursor of *processed* events and triggers
  an `acknowledge_up_to_cursor` every 8000 processed events. Because events are
  processed strictly sequentially and cursors are a monotonic per-subscription
  sequence, the processed cursor is also the high-water mark.

On handler failure the cursor is **not** acknowledged; `run()` returns the error
and the supervisor restarts. Projectors resume from their Postgres checkpoint
(redelivering the failed event — existing behavior). Sagas rely on D2's in-loop
retry for transient failures.

Rationale: per-event acking would add an `EACK` round-trip per event to every
projector and saga; the 8000-event batch keeps the flow-control window (10000)
ahead while making the ack position correct (only processed events).

### D4: Fail-closed preserved

The only way to obtain an operator remains `s3_builder_with_customer_key`
(mandatory 32-byte SSE-C key). No plaintext or SSE-S3 path is added or
reachable. The `photo-sse-c-encryption` spec's "recovers after restart"
scenario is updated to "recovers without restart".

## Risks / Trade-offs

- [Saga stalls indefinitely while Vault is down] → Intended fail-closed
  behavior: the photo stream waits, logs a backoff warning each attempt, and
  resumes automatically. Only the photo saga's own subscription is affected.
- [Retry hides a permanent `ServiceUnavailable` misconfiguration] → Loud
  backoff warnings indefinitely instead of silent event loss; operator alerting
  can key on them. This is strictly better than today's silent drop.
- [EACK per batch still leaves up to 7999 processed-but-unacked events on
  restart] → Projectors redeliver from the Postgres checkpoint; sagas never
  fail after a transient error (D2), so the window cannot contain processed
  events of interest on restart.
- [`operator()` becomes async, touching all `PhotoStorage` impl methods] →
  Mechanical change; all methods are already async.

## Migration Plan

1. Land the `kameo_es` ack change first (independent, behavior-neutral for
   projectors due to DB checkpoints).
2. Land the storage + saga retry changes together (they share the
   `ServiceUnavailable` contract).
3. Update `main.rs` to construct the recoverable adapter.
4. Sync delta specs to `photo-sse-c-encryption`.
5. Rollback: revert the PR; the old boot-time resolution returns (no data
   migration involved — key material is unchanged, only resolution timing).

## Open Questions

None — decisions follow issue #165's explicit options and the fail-closed
constraint.
