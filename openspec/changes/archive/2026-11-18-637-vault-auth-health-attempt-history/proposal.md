<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Vault auth-failure classification, token renewal, and import observability (issue #637)

## Why

Two related defects surfaced while importing screenplays:

1. **Root cause of the failed imports.** The dev/runtime Vault app token had
   expired. Every Vault KV read answered `403 Forbidden`, and
   `VaultClient::fetch` mapped *any* non-2xx to `DomainError::ServiceUnavailable`.
   The AI-import worker treats `ServiceUnavailable` as retryable, so it burned
   the whole retry budget against a permanent misconfiguration and dead-lettered
   jobs with the unhelpful summary
   `service unavailable: Vault unavailable: KV read returned 403 Forbidden`.
   Nothing renewed the 24 h periodic token in-process, so a long-running API
   lost Vault access once the bootstrap-created token lapsed.
2. **Missing observability.** `AiImportJob` exposed neither `next_attempt_at`
   (the column existed) nor per-attempt failure history, so neither the UI nor
   operators could explain a stalled import. `last_error` is overwritten by
   every attempt, discarding the reason earlier attempts failed.

## What changes

### A. Vault lifecycle + failure classification

- `VaultClient::send` classifies `401`/`403` centrally as a new
  `DomainError::DependencyAuthFailed` (registered code `dependency.auth-failed`,
  HTTP 503) instead of the generic `ServiceUnavailable`.
- `DomainError::is_retryable()` centralises the worker policy: only
  `ServiceUnavailable` is retryable, so a rejected credential fails fast
  (dead-letters) rather than consuming the retry budget. `worker_loop` and
  `merge_worker` use it.
- `VaultClient::spawn_token_renewal` renews the periodic app token in-process at
  `VAULT_TOKEN_RENEW_INTERVAL_SECS` (default 12 h, clamped `60`–`82800` (23 h)); the
  composition root keeps the task alive.
- A public, unauthenticated `GET /v1/health` renders a .NET-shaped
  `HealthReport` (Vault reachable **and** token valid, Postgres, SierraDB,
  Garage): `200` for `Healthy`/`Degraded`, `503` for `Unhealthy`.

### B. Retry + failure observability

- `AiImportJob` gains `next_attempt_at` and `attempts` (`AiImportAttempt`:
  `attempt_no`, `status`, `error_summary`, `retryable`, `created_at`).
- Migration `20261010000001_ai_import_job_attempt`; `mark_failed` /
  `mark_payload_unavailable` append a history row in the same statement as the
  lifecycle write; `AiImportQueue::get` populates the history.
- `backend/openapi.yaml` regenerated.

## Non-goals

- No change to the retry budget or backoff curve.
- No auto-re-issue of a fully lapsed token (the bootstrap seed path already
  repairs it; the runbook documents the procedure).
- No new business events — the queue stays operational Postgres state.
