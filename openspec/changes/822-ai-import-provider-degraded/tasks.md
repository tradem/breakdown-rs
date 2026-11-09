<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 822

## 1. Core — the provider code

- [x] 1.1 `problem_codes!`: new entry `AI_IMPORT_LLM_PROVIDER_UNAVAILABLE`
      (`ai-import.llm-provider-unavailable`, 503, no extensions);
      `PROBLEM_CODE_COUNT` 112 → 113.
- [x] 1.2 `DomainError::llm_provider_unavailable(reason)` — reuses the
      `ServiceUnavailable` shape so `is_retryable()` and the 503 status are
      unchanged; doc states why it is not `dependency.auth-failed`.
- [x] 1.3 `AiImportAttempt::code` doc names the provider code as the
      attribution signal.
- [x] 1.4 Unit tests: the constructor's code/status, and that it stays in the
      retryable set.

## 2. Infra — emit the code, populate list attempts

- [x] 2.1 `classify_http_status_with_detail`: 429/5xx →
      `llm_provider_unavailable` (detail suffix preserved).
- [x] 2.2 `classify_transport_error`: timeout/connect →
      `llm_provider_unavailable`; redirect/other stay validation.
- [x] 2.3 Mapping DB, pricing, catalog, payload storage keep
      `service_unavailable` (documented, asserted where a test already exists).
- [x] 2.4 `ListAttempts` batch read: `list_for_user` fills `attempts` for the
      page in ONE query (windowed newest-N per job), `get` unchanged.
- [x] 2.5 Tests: the classifiers' code, and a list-read test proving attempts are
      populated for every row of a page.

## 3. API — surface the new code

- [x] 3.1 Fluent bundles `de`/`en`: `problem-ai-import-llm-provider-unavailable`.
- [x] 3.2 Golden problem snapshot
      `tests/golden/problems/ai-import.llm-provider-unavailable.json`.
- [x] 3.3 `x-code-registry` regenerated (`UPDATE_OPENAPI=1`) and committed.
- [x] 3.4 API test pinning the code the client branches on: an attempt recorded
      through the worker path after a provider 503 carries the provider code
      (fake queue + classifier, no live provider).

## 4. Client — one derivation, two surfaces

- [x] 4.1 `import_state.dart`: provider code constant + `aiJobFailureReason` arm
      (transient provider narrative).
- [x] 4.2 New pure `aiProviderDegradation` (consecutive-newest rule, `>= 2`,
      count/window/next attempt/budget-spent).
- [x] 4.3 Job-status screen: degraded banner on the retryable card and on the
      terminal card; terminal copy keyed on code AND terminal status.
- [x] 4.4 Jobs row: compact degraded line from the same derivation.
- [x] 4.5 ARB `de`/`en` keys + `flutter gen-l10n`; `formatClock` helper for the
      window.
- [x] 4.6 Unit tests: fires at 2, not at 1, stops at a non-provider code,
      window/next-attempt values, budget-spent flag.

## 5. Client tests

- [x] 5.1 Widget: repeated provider failure → banner with count, window, next
      attempt.
- [x] 5.2 Widget: single provider failure → no banner, transient reason only.
- [x] 5.3 Widget: `dead_letter` after provider failures → no "next attempt may
      succeed" copy anywhere on the card.
- [x] 5.4 Widget: jobs row renders the compact line for the same job.
- [x] 5.5 Existing job-status/jobs-list tests still pass (no copy regression).

## 6. Regeneration, versions, artifacts

- [x] 6.1 `bash scripts/regen-client.sh` (doc-comment/registry drift only) —
      commit the diff or record that it is empty.
- [x] 6.2 Crate versions + CHANGELOGs (core → infra → api), Flutter
      `pubspec.yaml` + `CHANGELOG.md`.
- [x] 6.3 `dart format`, `flutter analyze`, `flutter test`,
      `cargo fmt`/`clippy`/targeted tests, `openspec validate`.
