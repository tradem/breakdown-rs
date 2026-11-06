<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 829 — Tasks

Design stage only: the issue forbids code before the authorization decision is
written down. Decisions are recorded in `design.md` (D1-D7) and encoded in the
delta specs; nothing below is implemented yet.

Four PRs, stacked in this order. Each lands green on its own; PR 3 can ship
after PR 1 + PR 2 only, and PR 4 may ride along with PR 2.

## 1. Backend: the block-less upload (contract + authorization) — size M

- [ ] 1.1 `core/ai/views.rs`: `AiImportTarget.block_number: Option<i32>`
      (`None` = "no target block chosen yet", never `0`); doc comment widened.
- [ ] 1.2 `core/ai/views.rs`: `AiImportTargetRequest { block_id: BlockId }` for
      the attach route (additive type, no reuse of the snapshot).
- [ ] 1.3 `core/error_registry.rs`: two registered codes —
      `ai-import.target-missing` (`409`, S1 extension `season_id`) and
      `ai-import.target-immutable` (`409`, S1 extensions `applied`,
      `existing_block_id`); registry-count test updated.
- [ ] 1.4 `api/handlers/mod.rs`: split `authorize_ai_block` (6226) into
      `authorize_ai_upload_target` returning
      `AiUploadTarget::{Block(BlockView), Season(SeasonView)}`:
      `X-Active-Block` present → today's path verbatim (block load, season
      policy, `check_declared_ai_season`); absent → declared season required,
      season resolved, `authorize_season_result(Action::Write)` on it, both
      `// AUTHZ-GATE:`-commented.
- [ ] 1.5 `api/handlers/mod.rs`: both-absent answers today's `400` (message
      widened); unknown declared season answers the established season-not-found
      surface.
- [ ] 1.6 `api/handlers/mod.rs`: `enqueue_ai_upload` (6397) stores
      `block_id: None` + the season-only target for the season arm;
      `resolve_ai_import_target` gains the season-only variant.
- [ ] 1.7 `api/handlers/mod.rs`: utoipa — `X-Active-Block` documented optional,
      `X-Declared-Season` documented as required when it is absent; the two new
      codes on the upload routes.
- [ ] 1.8 `infra/ai/queue.rs`: the enqueue binding already persists what it is
      given (`target.as_ref().map(|t| t.block_number)` binds `NULL` for a
      season-only target) — relax the stated "all three columns stay NULL
      together" discipline to "the season pair stays together, the block number
      is written when the block is known", and widen the `target_block_number`
      column `COMMENT` in a comment-only migration (no schema change: the three
      `target_*` columns are already nullable).
- [ ] 1.8a Verify the pre-existing test that asserts all-or-nothing target
      persistence is re-stated as season-pair-together, not deleted.
- [ ] 1.9 de/en Fluent copy + golden problems for the two new codes.
- [ ] 1.10 Tests: matrix from `design.md` D1 (block-less enqueue, 400, 403 on a
      foreign season, 404 on an unknown one, unchanged block path, unchanged
      `409 ai-import.scope-mismatch`); `AiImportTarget` wire test in both
      directions (`Some` → `null`).
- [ ] 1.11 `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 … openapi_drift`),
      Dart client regenerated (`CLIENT_VERSION` 1.2.0), version bumps + CHANGELOGs
      (`core` 0.59.0, `infra` 0.69.0, `api` 0.57.0, dependent pins).

## 2. Backend: the attach write, the job scope, the apply precondition — size M

- [ ] 2.1 `core/ai/ports.rs`: queue port method
      `set_target_once(job_id, block_id, block_number) -> TargetAttachOutcome`
      (`Attached` / `Unchanged` / `AlreadySet { existing_block_id }` /
      `Applied` / `NotFound`); default impl keeps unrelated fakes compiling.
- [ ] 2.2 `infra/ai/queue.rs`: adapter as ONE conditional `UPDATE` —
      `SET block_id = $2, target_block_number = $3, updated_at = now()
      WHERE id = $1 AND block_id IS NULL AND accept_as_is IS NULL` — plus the
      reads that distinguish `AlreadySet` / `Applied` from `NotFound`. Note
      `applied` is a **derived** view over `accept_as_is IS NOT NULL`
      (`queue.rs:1536-1542`), not a column; the guard uses the column directly.
      No partial write, no migration.
- [ ] 2.3 `api/handlers/mod.rs`: `put_ai_import_job_target` (route
      `PUT /ai-import/jobs/{id}/target`, utoipa, 200 → `AiImportJob`) enforcing
      D2: `authorize_ai_job(Action::Write)` in the **new** block's season, status
      `succeeded`, same-season block (`409 ai-import.scope-mismatch`),
      `AlreadySet`/`Applied` → `409 ai-import.target-immutable`.
- [ ] 2.4 `api/handlers/mod.rs`: `authorize_ai_job` (6345) gates on
      `target.season_id` instead of the `if let Some(block_id)` arm; a
      `target = NULL` pre-#771 row keeps the documented owner-only behaviour.
- [ ] 2.5 `api/handlers/mod.rs`: `apply_ai_import` (7501) refuses
      `block_id == None` with `409 ai-import.target-missing` + `season_id`
      extension; the CWE-639 guard keeps no skip branch (F1 closed).
- [ ] 2.6 Tests: attach happy path / idempotent repeat / different block /
      applied job / foreign season / denied season (403, job unchanged); job
      scope without a role (403 on preview); apply without a target writes
      nothing; golden problems for both codes.
- [ ] 2.7 `openapi.yaml` + Dart client regenerated; version bumps + CHANGELOGs
      (`core` 0.60.0, `infra` 0.70.0, `api` 0.58.0).

## 3. Flutter: adopt from the script, attach, and the effective anchor — size M

- [ ] 3.1 `src/network/active_block_interceptor.dart`: per-request opt-out
      (`Options.extra['noActiveBlock'] = true` skips attachment; a caller-set
      header still wins) + interceptor unit test.
- [ ] 3.2 `data/ai_import_repository.dart`: `attachTarget(jobId, blockId)`
      (`PUT …/target`, `Result`-typed, `ProblemError` code mapping) and the
      upload's `sendActiveBlock: false` path sending `X-Declared-Season` only.
- [ ] 3.3 `import_jobs/job_status_controller.dart`: `aiJobBlockInfo` (220)
      returns the job's **effective** target block; a block-less job returns
      `null`; the attach response replaces the cached row so the provider
      re-renders without a reload.
- [ ] 3.4 `import_submit_screen.dart` `_ImportTargetCard` (289): the adopt
      affordance from #827's script block, the "create block" fallback with the
      number prefilled, the attach call, and the frozen state with its reason.
- [ ] 3.5 `import_jobs/apply_controller.dart` (`ensureGroupEpisodeResolved`,
      1589) + `apply_screen.dart`/`preview_screen.dart`: creation anchored on
      the effective target, disabled with the reason while none is attached;
      the freeze rule set at the first group resolution.
- [ ] 3.6 `import_jobs/import_state.dart`: localize `ai_import.target_missing`
      and `ai_import.target_immutable` (extension-driven block naming); apply
      unavailable while no target, with a route to the target card.
- [ ] 3.7 de/en ARB (`aiImportTargetAdoptScriptBlock`, `aiImportTargetFrozen`,
      `ai_import.target_missing`, `ai_import.target_immutable`, …) + regenerated
      l10n; key-parity check green.
- [ ] 3.8 `vendor/breakdown_api/` regenerated (from 1.11/2.7); `int?` block
      number adopted at every call site.
- [ ] 3.9 Tests: unit (attach result mapping, effective anchor resolution,
      freeze predicate), widget + golden (adopt, create-first, frozen, target
      missing), integration smoke (blind upload → attach → apply).
- [ ] 3.10 `pubspec.yaml` version bump + `CHANGELOG.md` entry.

## 4. Docs: the decision, the screen, the copy — size S

- [ ] 4.1 ADR: "Authorization scope of a target-less AI import" — the four
      decisions, F1 and its closure, the existence-oracle answer.
- [ ] 4.2 `docs/design/screens/ai-import-submit.md`: the adopt/create/frozen
      target states + Salt wireframe update.
- [ ] 4.3 `docs/design/screens/ai-import-jobs.md` + the preview section: the
      "target block not chosen yet" state and the attach action.
- [ ] 4.4 `docs/design/glossary.md`: the new copy keys and any new label/icon.
- [ ] 4.5 `backend/docs/operations/runbooks.md`: one operator note — a job that
      answers `ai-import.target-missing` needs its target attached before an
      apply; the dev data reset does not resurrect it.

## Honest limits (documented, not worked around)

- The server cannot see a client-side group-episode adoption, so the freeze (D5)
  is enforced client-side; the server backstop is `applied` only. An older client
  that attaches after adopting gets an honest `403` at apply — never a mis-write.
- Pre-#771 jobs (`target = NULL`) keep an ownership-only scope: their season
  cannot be reconstructed and is not invented.
- A frozen target is a real dead end by design: the alternative creates episode
  rows in a block nobody chose (design D5).
