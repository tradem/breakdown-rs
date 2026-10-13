<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Vault auth-failure classification, token renewal, and import observability (issue #637)

## 1. Vault classification + lifecycle

- [x] 1.1 Add the `dependency.auth-failed` problem code and
  `DomainError::DependencyAuthFailed` + `dependency_auth_failed` constructor.
- [x] 1.2 Classify `401`/`403` centrally in `VaultClient::send`.
- [x] 1.3 Add `DomainError::is_retryable()` and use it in `worker_loop` /
  `merge_worker`.
- [x] 1.4 Add `VaultClient::token_valid`, `renew_token`,
  `spawn_token_renewal` and the `VAULT_TOKEN_RENEW_INTERVAL_SECS` parser.
- [x] 1.5 Spawn the renewal task in the composition root.

## 2. Health surface

- [x] 2.1 Add the `health` module (registry, `.NET`-shaped report, checks for
  Postgres, SierraDB, Vault, Garage).
- [x] 2.2 Register the public `GET /v1/health` route and exempt it from the
  auth/authz middleware via `Requirement::Public`.
- [x] 2.3 Wire the checks in `main.rs`; add `AppState::with_health`.

## 3. Import observability

- [x] 3.1 Add `AiImportJob.next_attempt_at` and `attempts`; add
  `AiImportAttempt` and `AiImportQueue::list_attempts`.
- [x] 3.2 Migration `20261010000001_ai_import_job_attempt`; append history in
  `mark_failed` / `mark_payload_unavailable`; populate it in `get`.
- [x] 3.3 Regenerate `backend/openapi.yaml`.

## 4. Verification

- [x] 4.1 Vault 403 → `DependencyAuthFailed`, 500 → `ServiceUnavailable`.
- [x] 4.2 `is_retryable` unit test; health-registry aggregation unit test.
- [x] 4.3 Contract suite green (openapi drift, route coverage, bundle
  coverage, golden problems).
