<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 771 — Tasks

## 1. Server backstop (backend first commit)

- [x] 1.1 Register `ai-import.scope-mismatch` (`409`, no extensions) in
      `crates/core/src/error_registry.rs` and bump `PROBLEM_CODE_COUNT`.
- [x] 1.2 `ApiError::AiImportScopeMismatch` renders it from the single problem
      builder.
- [x] 1.3 Fluent copy in `crates/api/locales/{de,en}/errors.ftl`; golden file
      `crates/api/tests/golden/problems/ai-import.scope-mismatch.json`
      (`UPDATE_GOLDEN=1 cargo test -p api --test contract problem_golden`).
- [x] 1.4 `authorize_ai_block` returns the resolved `BlockView`;
      `check_declared_ai_season` refuses a well-formed declaration that does not
      own the block, degrading absent/empty/unparsable values to "no
      declaration".
- [x] 1.5 `resolve_ai_import_target` snapshots `{season_id, season_number,
      block_number}` at the API edge, degrading to `None` on a failed season
      read (the upload keeps working).
- [x] 1.6 `AiImportTarget` in `crates/core/src/ai/views.rs`;
      `AiImportJob.target` (additive, `serde(default)`);
      `AiImportEnqueueRequest.target`.
- [x] 1.7 Migration `20261101000001_ai_import_job_target` (three nullable
      columns + comments, no backfill); queue INSERT + `map_job_row` decode
      (`decode_import_target`).
- [x] 1.8 utoipa: `X-Declared-Season` header + `409` response on both upload
      routes; `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`).
- [x] 1.9 Handler tests: target snapshot with a DISTINCT season number, 409
      refusal with no job row AND no stored source document left behind,
      unparsable declaration ignored.
- [x] 1.10 Version bumps `core 0.48.0 → 0.49.0`, `infra 0.57.0 → 0.58.0`,
      `api 0.47.0 → 0.48.0` (+ dependents' path-version pins) and the
      `CHANGELOG.md` `[Unreleased]` entry.

## 2. Dart client

- [x] 2.1 `scripts/regen-client.sh` — `AiImportTarget` model + the optional
      `xDeclaredSeason` parameter, no other diff.
- [x] 2.2 `AiImportRepository.upload{Schedule,Script}` accept `declaredSeasonId`
      and send `kDeclaredSeasonHeader`; the header map also carries the document
      name (one map, both metadata headers).

## 3. Screen — visible and resolved target

- [x] 3.1 `import_target.dart`: `aiImportSeasonContext` (the ONE season seam:
      explicit entry season, else ambient scope), `aiImportSeasonNumber`
      (cache-only), `aiImportResolvedScope`.
- [x] 3.2 `_ImportTargetCard`: target line + hint, inline multi-block picker,
      no-block / no-season / loading / fetch-failure states, all keyed.
- [x] 3.3 The submit action is disabled while no target is resolved.
- [x] 3.4 ARB keys de+en (`aiImportTarget*`, `aiImportScopeMismatch`) and
      regenerated l10n.

## 4. Dispatch guard + job view

- [x] 4.1 `submit` refuses `seasonId != active block's season` with
      `ai_import.scope_mismatch` before the gate/capability fetch (zero calls).
- [x] 4.2 The upload declares the target season (`X-Declared-Season`).
- [x] 4.3 `aiUploadErrorCopy` maps the scoped server code and the client code to
      one narrative.
- [x] 4.4 Job status screen: `_JobTargetCard` from `job.target`, with the
      cause-neutral "not recorded" arm (a pre-#771 row and a fresh upload whose
      season read degraded to `null` are indistinguishable there).

## 5. Tests

- [x] 5.1 Widget: target line above the submit action; single-block
      auto-adoption + declared dispatch; multi-block picker (disabled → pick →
      enabled); no-block blocked; no-season blocked.
- [x] 5.2 Controller: mismatch refusal (`409`, zero calls), matching target
      declares, ambient-only dispatch declares the ambient season.
- [x] 5.3 Repository: `X-Declared-Season` on both routes; absent when no target.
- [x] 5.4 Job status: recorded target line, cause-neutral "not recorded" arm,
      goldens re-baselined (`--update-goldens`, layout reviewed).
- [x] 5.5 Submit screen target goldens (review): resolved, multi-block picker and
      blocked states, dark + android, German template locale.
- [x] 5.6 Refusal test also asserts NO source document was stored (the in-memory
      payload store's test-only handle count).

## 6. Docs & validation

- [x] 6.1 New screen spec `docs/design/screens/ai-import-submit.md`; job-status
      target section in `docs/design/screens/ai-import-jobs.md`; new copy keys in
      the glossary ARB inventory; `check-design-diagrams.sh` green.
- [x] 6.2 `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test` (full suite), `dart run build_runner build`.
- [x] 6.3 Backend: `cargo check --workspace --all-targets`,
      `cargo test -p api --test contract` (drift + golden + bundle coverage),
      `cargo test -p api --test handlers_ai`.
- [ ] 6.4 Postgres tier tests for the new columns run in CI (`ai-import`
      integration harness); the migration is additive and nullable, so no
      existing tier needs a change.
