<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Tasks: AI import job status — retry ETA and why earlier attempts failed (issue #639)

## 1. Backend — the attempt history carries the problem `code`

- [x] 1.1 Add `DomainError::code()` returning the variant's registry entry.
- [x] 1.2 Migration `20261011000001_ai_import_attempt_error_code`: add the
  `error_code` column to `ai_import.ai_import_job_attempt`.
- [x] 1.3 Thread `error_code: Option<&str>` through `AiImportQueue::mark_failed`
  / `mark_payload_unavailable`; persist it in the Postgres adapter.
- [x] 1.4 Expose `code: Option<String>` on the `AiImportAttempt` view and
  decode it in `list_attempts`.
- [x] 1.5 Update every caller/implementor (production workers + test seams).
- [x] 1.6 Regenerate `backend/openapi.yaml`.

## 2. Frontend — live retry ETA + code-keyed failure reason

- [x] 2.1 Regenerate the vendored `breakdown_api` client for the new field.
- [x] 2.2 Add the live "next retry in …" ticker to the retryable `failed`
  card, derived from `next_attempt_at`; honest "retry scheduled" fallback
  when absent.
- [x] 2.3 Add the code-keyed localized failure reason to the retryable card
  (and the attempt history on terminal cards), never interpolating the
  backend `detail`/`error_summary` as identity.
- [x] 2.4 Add the `de` + `en` ARB keys (template `de`, complete `en`).
- [x] 2.5 Widget tests + goldens for the retryable-with-ETA state and the
  unknown-ETA degradation; absence/unknown-code branches.

## 3. Verification

- [x] 3.1 Backend: `cargo test` for the affected crates; `openapi_drift`.
- [x] 3.2 Frontend: `dart format`, `flutter analyze`, `flutter test`.
- [x] 3.3 OpenAPI client drift check green.
