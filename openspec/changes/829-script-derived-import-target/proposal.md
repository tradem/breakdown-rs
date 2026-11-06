<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 829 — The import target may come from the script (block-less upload + late attach)

## Why

The reporter's fourth finding: the import target is always "the season + block
that are active right now". Switching and creating it from the submit screen is
a plain frontend change — **landed** as issue #828 (`_ImportTargetCard` at
`frontend-flutter/lib/features/ai_import/import_jobs/import_submit_screen.dart:289`).
"Take it from the script" is not a UI change: the block is a **mandatory
authorization input** at upload today, so the target cannot be *derived* unless
the upload is allowed to exist without one.

The data that would be adopted is already there — issue #827 (landed: PR 1/2
`051e1177`, PR 2/2 `03589a11`) publishes the block the script itself states as
`AiImportProgress.block_number` / `ScriptContext.block_number`. What is missing
is a contract that lets a job start **without** a block and receive one later.
Today no path can produce a block-less job: `enqueue_ai_upload`
(`backend/crates/api/src/handlers/mod.rs:6397`) always stores
`block_id: Some(...)` from the required `X-Active-Block`, although
`ai_import.ai_import_job.block_id` is already nullable and the apply handler
already documents "a block-less job stays unguarded by design".

## Finding F1 — the documented "unguarded by design" is an authorization hole

Verified while answering the issue's authorization question, and the reason this
change is a contract change rather than a UI change:

- `authorize_ai_job` (`handlers/mod.rs:6345-6367`) runs the season policy **only
  inside `if let Some(block_id) = job.block_id`**. With `block_id == None` the
  only remaining check is `job.user_id == caller`.
- A full scan of `apply_ai_import` (`handlers/mod.rs:7501-7960`) finds exactly
  one authorization call — that same `authorize_ai_job` — so with a block-less
  job **nothing** evaluates the caller's role on the target episode's season.

So "it may apply to any episode it is authorized for" is currently false: the
apply would let any authenticated user write AI-extracted scenes into an episode
of a season they hold no role in. Today this is unreachable only because no path
creates a block-less job; #829 would make it reachable. **Closing F1 is a
prerequisite of the feature, not a follow-up** (design D3 + D4).

## What changes

**Upload (contract):** `X-Active-Block` becomes **optional** on both upload
routes. When it is absent, `X-Declared-Season` becomes **required** and is the
authorization scope; the job is stored with `block_id = NULL` and a target
snapshot naming the season but no block. When it is present, nothing changes —
the established block scope and the #771 declared-season agreement stay exactly
as they are.

**Attach (contract):** a new job-scoped, set-once write
`PUT /v1/ai-import/jobs/{id}/target` (`{block_id}`) sets the job's write target
once: the block id and the target snapshot's block number are written in one
statement, so the visible target and the guard value cannot drift. Allowed only
while the job is `succeeded` and no apply has run; the same block twice is a
`200` no-op; a different block is refused. Guarded by the piece-dept role in the
**attached** block's season.

**Authorization scope (backend):** a job's scope becomes its **target season**
(always known after this change), so `authorize_ai_job` never degrades to
"owner only". Status/preview/delete/apply all inherit the fix.

**Apply (contract):** an apply requires an attached block (`409
ai-import.target-missing`), so the CWE-639 cross-block guard keeps exactly one
meaning instead of gaining an "only sometimes guarded" mode. F1 is closed by
construction.

**Client:** the target card gains "Aus Skript übernehmen — Block 2" (from
#827's field) and "Block 2 anlegen" when that block does not exist yet, both
routed through the one attach seam; a duplicate upload never re-targets; the
in-preview episode creation anchors on the **effective** target block instead of
the upload block; and the target card freezes once a group episode has been
resolved (design D5).

## Decisions taken (detail + rejected alternatives in `design.md`)

| # | Decision | Alternative rejected |
|---|---|---|
| D1 | A block-less upload is authorized by its **declared season** (`authorize_season_result(Action::Write)`) | a new "any costume-dept season" capability |
| D2 | The attach is a **job-scoped set-once write** | a `target` field in the apply request |
| D3 | A job's authorization scope is its **target season**, never a no-op | leaving the `if let Some(block_id)` arm |
| D4 | An **apply requires an attached block** (`409 ai-import.target-missing`) | a season-scoped fallback apply |
| D5 | The target **freezes at the first group-episode resolution** | silently invalidating created episodes |
| D6 | The target snapshot may name a season **without** a block (`block_number: Option<i32>`) | a second parallel field |
| D7 | The client's block-less upload **suppresses the ambient header** via an interceptor opt-out | sending a sentinel/blank header |

**Existence oracle (answered):** a season id's existence is already public to
every authenticated caller — `GET /v1/seasons` (`handlers/mod.rs:1055`) is
`Authenticated`-only and membership-*unfiltered*, so it lists every season id and
number. A block-less upload therefore discloses nothing new: it answers
`403 ai-import.forbidden` for a season the caller holds no costume role in, and
`404 season.not-found` for an id that does not exist — both already derivable
from the read model. The block path keeps today's behaviour unchanged.

## Impact

- **Specs:** `ai-import` (ADDED: block-less upload authorization, set-once
  attach, target-season job scope, apply requires a target, snapshot without a
  block), `flutter-ai-import-workflow` (ADDED: adopt/create from the script,
  effective-target anchor, frozen target, block-less dispatch).
- **Backend:** `core` (`AiImportTarget.block_number: Option<i32>`,
  `AiImportEnqueueRequest.block_id` nullable on the wire path, attach request
  view, two registry codes), `api` (optional `X-Active-Block` +
  mandatory-when-absent declared season, `authorize_ai_job` on the target
  season, new `put_ai_import_job_target` handler + utoipa, apply target
  precondition, Fluent de/en copy, golden problems), `infra` (queue port +
  adapter `set_target_once`, apply's block precondition, no schema change — the
  three `target_*` columns are already nullable), `openapi.yaml` regenerated.
- **Frontend:** `data/ai_import_repository.dart` (attach + no-header upload),
  `src/network/active_block_interceptor.dart` (opt-out), the target card in
  `import_submit_screen.dart`,
  `import_jobs/job_status_controller.dart` (effective-target anchor),
  `apply_controller.dart` (creation anchor + freeze), de/en ARB, regenerated
  l10n + `vendor/breakdown_api/`.
- **Docs:** ADR for the authorization scope of a target-less import; screen spec
  `docs/design/screens/ai-import-submit.md` (adopt/create affordances) and the
  preview/job-status sections; glossary copy-key inventory.
- **Tests:** handler tests (block-less upload, 400/403/404 matrix,
  set-once/immutable, apply-without-target, target-season job scope), golden
  problems for the two new codes, Flutter unit + widget + golden tests for the
  adopt/create/freeze states, and an integration smoke for the attach → apply
  path.
- **Out of scope:** the cross-block apply recovery (#705, landed), the target
  switch/create UI (#828, landed), reading the script's block (#827, landed),
  any offline command queue, and re-targeting an already-applied job.

## Related

- #827 — reads and publishes the script's block (precondition, landed).
- #828 — switch/create the target from the submit screen (landed).
- #771 — the explicit import target and its declared-season guard (contract this
  builds on).
- #705 — the cross-block apply recovery the guard exists for.
