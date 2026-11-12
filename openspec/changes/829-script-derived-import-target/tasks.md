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

- [x] 1.1 `core/ai/views.rs`: `AiImportTarget.block_number: Option<i32>`
      (`None` = "no target block chosen yet", never `0`); doc comment widened.
- [x] 1.2 **landed in PR 2** `core/ai/views.rs`:
      `AiImportTargetRequest { block_id: BlockId }` — the type exists for the
      attach route, which PR 2 adds; introducing it in PR 1 would ship an unused
      request type.
- [x] 1.3 `core/error_registry.rs`: `ai-import.target-missing` (`409`, S1
      `season_id`) — **re-split into PR 1** after the review of this PR: merging
      it alone would have left a live authorization hole on `main`, so the code
      that refuses that hole travels with the upload that creates the state (see
      1.12 + 1.13). `ai-import.target-immutable` stays in PR 2, next to the attach
      that emits it.
- [x] 1.4 `api/handlers/mod.rs`: split `authorize_ai_block` into
      `authorize_ai_upload_target` returning
      `AiUploadTarget::{Block(BlockView), Season(SeasonView)}`:
      `X-Active-Block` present → today's path verbatim (block load, season
      policy, `check_declared_ai_season`); absent → declared season required,
      season resolved, `authorize_season_result(Action::Write)` on it, both
      `// AUTHZ-GATE:`-commented.
- [x] 1.5 `api/handlers/mod.rs`: both-absent answers today's `400` (message
      widened); unknown declared season answers the established season-not-found
      surface.
- [x] 1.6 `api/handlers/mod.rs`: `enqueue_ai_upload` stores
      `block_id: None` + the season-only target for the season arm;
      `resolve_ai_import_target` gains the season-only variant.
- [x] 1.7 `api/handlers/mod.rs`: utoipa — `X-Active-Block` documented optional,
      `X-Declared-Season` documented as required when it is absent, `400` on
      the routes (the two new codes follow with PR 2).
- [x] 1.8 `infra/ai/queue.rs`: the enqueue binding already persists what it is
      given (`target.as_ref().map(|t| t.block_number)` binds `NULL` for a
      season-only target) — relax the stated "all three columns stay NULL
      together" discipline to "the season pair stays together, the block number
      is written when the block is known", and widen the `target_block_number`
      column `COMMENT` in a comment-only migration (no schema change: the three
      `target_*` columns are already nullable).
- [x] 1.8a `decode_import_target` re-stated to season-pair-together (`infra`
      decodes a snapshot whose block number is NULL; the all-or-nothing season
      rule is kept).
- [x] 1.9 **landed in PR 2** de/en Fluent copy + golden problems for the two new
      codes.
- [x] 1.10 Tests: matrix from `design.md` D1 (block-less enqueue, 400 on neither/blank
      header, 403 without a role, 404 on an unknown season, unchanged block path
      incl. `409 ai-import.scope-mismatch`) in
      `crates/api/tests/handler_ai_import_ports.rs`; `AiImportTarget` wire test in
      both directions (`Some` → `null`) via the regenerated contract.
- [x] 1.12 **re-split out of PR 2 (design D3)** `api/handlers/mod.rs`:
      `ai_job_scope_season` + `authorize_ai_job` gate on the job's TARGET season.
      The policy used to sit inside `if let Some(block_id)`, and `apply_ai_import`
      calls that helper as its only authorization — so this PR could not merge
      without it.
- [x] 1.13 **re-split out of PR 2 (design D4)** `api/handlers/mod.rs`:
      `apply_ai_import` refuses an unattached target with
      `409 ai-import.target-missing` (+ `season_id`), so the CWE-639 guard never
      needs a skip branch.
- [x] 1.14 `api/handlers/mod.rs` (CodeRabbit review): a PRESENT but unreadable or
      unparsable `X-Active-Block` is a `400`, never a silent fall-through to the
      declared-season arm.
- [x] 1.11 `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 … openapi_drift`),
      Dart client regenerated (`CLIENT_VERSION` 1.2.0) **and the Flutter tree
      kept compiling in the same commit** — the `target.blockNumber` widening to
      `int?` is a compile-level adoption, never a behaviour change (the UI
      adoption is PR 3), so no PR leaves `main` red. Version bumps + CHANGELOGs
      (`core` 0.59.0, `infra` 0.69.0, `api` 0.57.0, dependent pins).

## 2. Backend: the attach write, the job scope, the apply precondition — size M

- [x] 2.1 `core/ai/ports.rs`: queue port method
      `set_target_once(job_id, block_id, block_number) -> TargetAttachOutcome`
      (`Attached` / `Unchanged` / `AlreadySet { existing_block_id }` /
      `Applied` / `NotFound`); default impl keeps unrelated fakes compiling.
- [x] 2.2 `infra/ai/queue.rs`: adapter as ONE conditional `UPDATE` —
      `SET block_id = $2, target_block_number = $3, updated_at = now()
      WHERE id = $1 AND block_id IS NULL AND accept_as_is IS NULL` — plus the
      reads that distinguish `AlreadySet` / `Applied` from `NotFound`. Note
      `applied` is a **derived** view over `accept_as_is IS NOT NULL`
      (`queue.rs:1536-1542`), not a column; the guard uses the column directly.
      No partial write, no migration.
- [x] 2.3 `api/handlers/mod.rs`: `put_ai_import_job_target` (route
      `PUT /ai-import/jobs/{id}/target`, utoipa, 200 → `AiImportJob`) enforcing
      D2: `authorize_ai_job(Action::Write)` in the **new** block's season, status
      `succeeded`, same-season block (`409 ai-import.scope-mismatch`),
      `AlreadySet`/`Applied` → `409 ai-import.target-immutable`.
- [x] 2.4 **landed in PR 1** (1.12): `authorize_ai_job` gates on
      `target.season_id`; a `target = NULL` pre-#771 row keeps the documented
      owner-only behaviour.
- [x] 2.5 **landed in PR 1** (1.13): `apply_ai_import` refuses
      `block_id == None` with `409 ai-import.target-missing` + `season_id`.
- [x] 2.6 Tests: attach happy path / idempotent repeat / different block /
      applied job / foreign season / denied season (403, job unchanged); job
      scope without a role (403 on preview); apply without a target writes
      nothing; golden problems for both codes.
- [x] 2.6a Real-Postgres suite for the adapter
      (`integration-tests/tests/ai_import_job_target.rs`): attach, second
      block, frozen-after-apply, idempotent-after-apply, unknown job, and
      the target-less row — the predicate is no longer only tested by the
      in-memory fake. Review of `#856` also moved the same-block check
      before the applied state, made the statement total
      (`target_season_id IS NOT NULL`), added `NoTargetSeason`, and pulled
      the client's `Block unknown` guard into this PR.
- [x] 2.7 `openapi.yaml` + Dart client regenerated; version bumps + CHANGELOGs
      (`core` 0.60.0, `infra` 0.70.0, `api` 0.58.0).

## 3. Flutter: adopt from the script, attach, and the effective anchor — size M

- [x] 3.1 `src/network/active_block_interceptor.dart`: per-request opt-out
      (`Options.extra['noActiveBlock'] = true` skips attachment; a caller-set
      header still wins) + interceptor unit test.
- [x] 3.2 `data/ai_import_repository.dart`: `attachTarget(jobId, blockId)`
      (`PUT …/target`, `Result`-typed, `ProblemError` code mapping) and the
      upload's `sendActiveBlock: false` path sending `X-Declared-Season` only.
- [x] 3.3 `import_jobs/job_status_controller.dart`: `aiJobBlockInfo` (220)
      returns the job's **effective** target block; a block-less job returns
      `null`; the attach response replaces the cached row so the provider
      re-renders without a reload.
- [x] 3.4 `import_submit_screen.dart` `_ImportTargetCard` (289): the adopt
      affordance from #827's script block, the "create block" fallback with the
      number prefilled, the attach call, and the frozen state with its reason.
- [x] 3.5 `import_jobs/apply_controller.dart` (`ensureGroupEpisodeResolved`,
      1589) + `apply_screen.dart`/`preview_screen.dart`: creation anchored on
      the effective target, disabled with the reason while none is attached;
      the freeze rule set at the first group resolution.
- [x] 3.5a Review fixes on the preview card: the actions render independently of
      the summary line (a block-less SCHEDULE preview has neither block number,
      so the early returns hid the picker and apply could never unblock), the
      rebuilt scope keeps `targetSeasonId`/`applied`, an attached target still
      states the locked reason, the apply surface localizes both target codes,
      and the block-less choice cannot enable a dispatch without a season.
- [x] 3.5b Review fixes on the preview card's picker (CodeRabbit, PR #860): the
      script block number reaches the shared create form's field for real
      (`showCreateBlockSheet(… initialNumber:)` — `_create` accepted the number
      and dropped it, so the form asked back for the value its own button named),
      and a failed block list (an `Err` or a thrown read) is surfaced with a
      retry instead of opening a picker that reads exactly like an empty season
      (`aiImportTargetBlocksUnavailable`).
- [x] 3.6 `import_jobs/import_state.dart`: localize `ai_import.target_missing`
      and `ai_import.target_immutable` (extension-driven block naming); apply
      unavailable while no target, with a route to the target card.
- [x] 3.7 de/en ARB (`aiImportTargetAdoptScriptBlock`, `aiImportTargetFrozen`,
      `ai_import.target_missing`, `ai_import.target_immutable`, …) + regenerated
      l10n; key-parity check green.
- [x] 3.8 `vendor/breakdown_api/` regenerated (from 1.11/2.7); `int?` block
      number adopted at every call site.
- [x] 3.9 Tests: unit (attach result mapping, effective anchor resolution,
      freeze predicate), widget + golden (adopt, create-first, frozen, target
      missing), integration smoke (blind upload → attach → apply).
- [x] 3.10 `pubspec.yaml` version bump + `CHANGELOG.md` entry.
- [x] 3.11 **Follow-up (live report):** the adoption no longer waits for a tap.
      `_PreviewTargetActions` adopts the script's block on its own — the existing
      block when the season has that number, otherwise a block created with the
      script's number and **no dates** — once per card, through the same attach
      seam; a manual picker interaction ends the automation so a failed silent
      create keeps the shared form (prefilled) as the fallback.
- [x] 3.12 **Follow-up (live report):** the block-less dispatch no longer needs a
      confirmation tap. `_SubmitButton` derives it from the season's (empty) block
      list, so a season with no block can be imported into immediately; the
      `blockLessImportProvider` session flag and its undo affordance are gone, and
      a season WITH a block still dispatches that block.

## 4. Docs: the decision, the screen, the copy — size S

- [x] 4.1 ADR: "Authorization scope of a target-less AI import" — the four
      decisions, F1 and its closure, the existence-oracle answer.
- [x] 4.2 `docs/design/screens/ai-import-submit.md`: the adopt/create/frozen
      target states + Salt wireframe update.
- [x] 4.3 `docs/design/screens/ai-import-jobs.md` + the preview section: the
      "target block not chosen yet" state and the attach action.
- [x] 4.4 `docs/design/glossary.md`: the new copy keys and any new label/icon.
- [x] 4.5 `backend/docs/operations/runbooks.md`: one operator note — a job that
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
