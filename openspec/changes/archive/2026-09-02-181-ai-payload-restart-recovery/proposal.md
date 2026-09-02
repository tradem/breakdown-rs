<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->

# Proposal: Restart-recovery semantics for AI import payloads (Issue #181)

## Drift check

Issue #181 was filed against PR #169, before #174/#198/#199/#201 landed. Three
of its "required changes" are already implemented:

- `OpenDalAiPayloadStorage` (S3/Garage via OpenDAL) exists and implements
  `AiPreviewStore`, `AiDocumentStore` and `AiDocumentSource`.
- It is wired into `ProductionPorts` in `main.rs` whenever `AI_PAYLOAD_S3_*`
  is configured, and `main.rs` **fails to start** when `AI_IMPORT_ENABLED=true`
  without it.
- A terminal-job GC worker (`ai::payload_cleanup`) with retention, dry-run and
  advisory locking exists.

What is **not** implemented, and is the scope of this change:

1. `MemoryAiPreviewStore` is still constructed in `main.rs` on the
   AI-import-disabled path — i.e. it *is* in the production composition root.
2. There is no explicit non-resumable state. A job whose durable payload is
   gone is failed as if the failure were transient: `merge_worker` marks a
   missing preview `retryable = true`, and the script/schedule workers derive
   retryability from `ServiceUnavailable` only. Retries then burn the whole
   `max_retries` budget re-discovering that the bytes are gone.
3. The GC sweep treats `status = 'failed'` as terminal, but `failed` is exactly
   the *retryable* state — cleanup can delete the source document of a job that
   is still scheduled for a retry, manufacturing the missing-payload case.
4. Restart behaviour per status is nowhere stated or tested.

## Decision

Add a distinct terminal status `JobStatus::PayloadUnavailable`
(`"payload_unavailable"`), chosen over an extra boolean column or an
error-string convention: the state is genuinely a *different terminal
outcome* from "the work failed", and operators/dashboards must be able to
separate "the model or the document was bad" from "we lost the bytes".

## Restart-recovery semantics (the contract this change establishes)

| Status at restart | Behaviour |
|---|---|
| `pending` | Runnable. Claimed by the next worker; source document is loaded from durable storage. |
| `running` | Its worker is gone; the claim lease (#177) expires and another worker reclaims it, releasing the orphaned permit (#180). |
| `failed` | Runnable once `next_attempt_at` is due. The claim predicate ignores `retries`, so this holds even for an exhausted budget — its payloads are **never** GC'd. |
| `dead_letter` | Terminal. Payloads are GC-eligible after the retention grace period. `mark_failed` lands a budget-exhausted job here directly. |
| `succeeded` | Preview is served from durable storage; apply reloads it. GC-eligible after retention. |
| `payload_unavailable` | Terminal and **non-resumable**. Never claimed, never retried; payloads GC-eligible. |

A worker that cannot load a payload because it is *absent*
(`DomainError::NotFound`) transitions the job to `payload_unavailable`
immediately, bypassing the remaining retry budget. A worker that cannot load
it because storage is *unreachable* (`ServiceUnavailable`) still fails
retryably — that is a transient condition, not a lost payload.

## Changes

### core (0.7.0, unreleased)

- `JobStatus::PayloadUnavailable` + `JobStatus::is_terminal()` /
  `is_non_resumable()`.
- `AiImportQueue::mark_payload_unavailable(id, worker_id, error_summary)`,
  **defaulted** (delegates to `mark_failed(..., retryable = false)`) so
  in-memory/test queues need no change.

### infra (0.12.0, unreleased)

- Migrations `20260812000001_ai_import_payload_unavailable` (add the widened
  `CHECK` as `NOT VALID`, then commit) and
  `20260812000002_ai_import_payload_unavailable_validate` (validate + swap
  names). The split is required: `ADD CONSTRAINT` holds ACCESS EXCLUSIVE until
  commit and sqlx wraps each file in one transaction, so validating in the same
  file would run the scan under that lock and block every job write.
- `PgAiImportQueue::mark_payload_unavailable` — owner-fenced, clears
  claim/lease/permit/`next_attempt_at`; `parse_status` learns the new value.
- Claim predicates are unchanged and therefore already exclude the new status.
- `ScriptImportWorker` / `ScheduleImportWorker`: a `NotFound` from
  `source.load` → `mark_payload_unavailable`.
- `QueueMergeWorker`: a missing preview blob → `mark_payload_unavailable`
  (was: retryable failure).
- `payload_cleanup`: sweep exactly `succeeded`, `dead_letter` and
  `payload_unavailable`. `failed` is excluded unconditionally — **not** merely
  while it has budget left. The claim predicates never consult `retries`, so an
  exhausted `failed` row is still claimable; conditioning retention on
  `retries >= max_retries` would reintroduce the very bug this fixes. Nothing
  leaks, because `mark_failed` dead-letters a job in the same statement that
  exhausts its budget.
- `UnconfiguredAiPayloadStore`: a null-object adapter returning
  `ServiceUnavailable` for every operation, for the composition root when AI
  import is disabled.

### api (0.6.1, unreleased)

- `main.rs` wires `UnconfiguredAiPayloadStore` instead of
  `MemoryAiPreviewStore`; `MemoryAiPreviewStore` is no longer imported.
- Apply already rejects any non-`Succeeded` job with `409`, so a
  `payload_unavailable` job cannot be applied.

## Tests

- core: status string round-trip, terminal/non-resumable classification.
- infra: worker missing-payload → `payload_unavailable` (not a retryable fail);
  merge worker missing preview → `payload_unavailable`;
  `UnconfiguredAiPayloadStore` returns `ServiceUnavailable`.
- integration-tests (Postgres): `mark_payload_unavailable` is owner-fenced and
  clears `worker_id`/`lease_expires_at`/`permit_id`, the job is not re-claimable
  afterwards, the GC sweep spares both a retryable **and** a budget-exhausted
  `failed` job (asserting the latter is still claimable, which is *why* it is
  spared) while sweeping `succeeded`/`dead_letter`/`payload_unavailable`, and a
  freshly terminal job survives its retention window.
