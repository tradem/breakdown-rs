## Why

Vault-backed photo storage (PR #164) fails closed permanently when Vault is
unavailable at API boot: the `OpenDalPhotoStorage` adapter holds no operator
until the next restart, so a transient Vault outage disables all photo
operations for the process lifetime. Additionally, the patched `kameo_es`
event-handler can acknowledge a SierraDB cursor *before* the photo sagas have
finished processing that event, so a transient `ServiceUnavailable` failure can
silently drop thumbnail or bytes-cleanup work.

## What Changes

- Replace the boot-time-only Vault SSE-C key resolution with a **recoverable,
  lazily-resolved** key path: when Vault is unreachable the photo storage stays
  fail-closed (`503`) but automatically retries key resolution on subsequent
  operations, resuming normal photo I/O once Vault recovers — no API restart.
- Make the photo thumbnail and bytes-cleanup sagas **retry transient
  `ServiceUnavailable` errors with backoff inside the processing loop** instead
  of crashing the subscription epoch, so a transient outage cannot permanently
  drop saga work.
- Change the patched `kameo_es` event-handler acknowledgement behavior so the
  SierraDB cursor is **acknowledged only after successful handler processing**
  (per-event post-processing ack, replacing the pre-processing batch ack).
- Add **deterministic unit tests** for Vault recovery (lazy key re-resolution
  succeeds after the key source recovers) and for failed-event redelivery
  (a failed handler does not advance the acknowledged cursor).
- **BREAKING (ops semantics):** the `photo-sse-c-encryption` spec's
  "unavailable until the next restart" behavior changes to "recovers without
  restart". Fail-closed remains: the implementation never falls back to
  plaintext or SSE-S3 storage.

## Capabilities

### New Capabilities
<!-- none -- this is a reliability change to existing capabilities -->

### Modified Capabilities
- `photo-sse-c-encryption`: Vault outage now recovers without an API restart
  (lazy, retried key resolution) while remaining fail-closed; saga
  acknowledgements advance only after successful event processing.

## Impact

- `backend/crates/api/src/main.rs` — composition root: construct the
  recoverable storage adapter (no longer `unavailable()` on Vault failure).
- `backend/crates/infra/src/photo/storage.rs` — `OpenDalPhotoStorage` gains a
  recoverable lazy operator; Vault key resolution is retried on demand.
- `backend/crates/infra/src/vault.rs` — expose a retryable/lazy key source used
  by the storage adapter.
- `backend/crates/infra/src/photo/sagas/thumbnail.rs` and
  `bytes_cleanup.rs` — transient `ServiceUnavailable` retry-with-backoff.
- `backend/.patches/kameo_es/src/event_handler.rs` — ack only after successful
  processing; add deterministic tests.
- Photo storage and event-handler tests (`crates/infra`, `crates/integration-tests`).
- OpenSpec delta specs for `photo-sse-c-encryption`.
