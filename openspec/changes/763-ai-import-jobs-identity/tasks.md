<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks: AI-import jobs list identity (issue #763)

## 1. Backend — terminal progress reset (bug)

- [x] 1.1 Clear `progress` in `mark_succeeded`, in `mark_failed` when the same
  statement dead-letters the job, and in `mark_payload_unavailable`; keep the
  retryable `failed` branch and the claim-time reset untouched.
- [x] 1.2 Extend the `AiImportJob::progress` doc to state that a terminal job
  never carries progress.

## 2. Backend — source file name

- [x] 2.1 Migration `20261016000001_ai_import_job_identity`: additive
  `source_file_name TEXT` + `applied_episodes JSONB` on `ai_import.ai_import_job`
  (both nullable, no backfill).
- [x] 2.2 `sanitize_source_file_name` in `core::ai::source_name` (basename only,
  control characters removed, whitespace collapsed, length cap, empty ⇒ `None`)
  with unit tests.
- [x] 2.3 Accept the percent-encoded UTF-8 `X-Document-Filename` header on both
  upload handlers, decode at the API edge, sanitize, and carry it on
  `AiImportEnqueueRequest`; the dedup hit keeps the existing row's name.
- [x] 2.4 Persist the column in `PgAiImportQueue::enqueue` and decode it in
  `map_job_row`.
- [x] 2.5 Expose `source_file_name` on `AiImportJob` (`serde(default)`).

## 3. Backend — imported episode(s)

- [x] 3.1 New `AppliedEpisode { id, number, name, applied_count }` view type.
- [x] 3.2 `ScriptApplyResult.applied_episodes` computed by the apply worker from
  the plan's resolved episodes (per-episode row counts); the API edge supplies
  the identities it already resolves for the target episode and for existing
  episode-group targets.
- [x] 3.3 `AiImportQueue::record_applied_episodes` (owner-agnostic terminal
  write, `updated_at` + hub notify) and its persistence.
- [x] 3.4 Expose `applied_episodes` on `AiImportJob` and on
  `ApplyAiImportResponse` (`serde(default)`).

## 4. Wire + client regen

- [x] 4.1 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1`).
- [x] 4.2 Regenerate the vendored Dart client (`scripts/regen-client.sh`) and
  commit the diff.

## 5. Flutter — cache + controller

- [ ] 5.1 Drift: `sourceFileName` + `appliedEpisodesJson` columns, schema v17,
  additive migration in the same PR.
- [ ] 5.2 `AiImportJobRowView` gains `sourceFileName` + `appliedEpisodes` with
  equality/hash/`toString`; both mappers (wire + cache) fill them.
- [ ] 5.3 Repository: send the picked document name on upload (percent-encoded
  UTF-8 header), never as a fabricated value.

## 6. Flutter — screen

- [ ] 6.1 Stage/episode block renders only for `jobStatusInProgress(status)`;
  episode labels render **with values**.
- [ ] 6.2 Title = file name (2 lines, ellipsized) with `kind · date` secondary;
  unnamed rows keep the `kind · date` title.
- [ ] 6.3 Subtitle names the imported episode (`299 Erlösung`, multi-episode
  `299 Erlösung (+2)`), and a succeeded applied job shows the outcome counts.
- [ ] 6.4 New `de`/`en` ARB keys (template `de`); `flutter gen-l10n`.

## 7. Tests

- [ ] 7.1 Backend: sanitizer unit tests; upload header test (named + unnamed +
  malformed); apply records the target episodes (single + multi); terminal
  transitions clear progress.
- [ ] 7.2 Flutter: mapper tests (wire → row, cache → row with `null` name);
  widget tests for terminal-without-stage, named row, unnamed row,
  multi-episode row; golden refresh where the row shape changed.

## 8. Verification

- [x] 8.1 Backend: `cargo test` for the touched crates, `cargo clippy`,
  `openapi_drift`.
- [ ] 8.2 Flutter: `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test`, `flutter gen-l10n` drift, OpenAPI client drift check.
