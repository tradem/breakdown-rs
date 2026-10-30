<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 771 — The AI import names its target, and a contradictory target is refused

## Why

Issue #771: a user created a **new season** to isolate a second import round, ran
the import from the wizard's completion CTA — and every episode, scene and
shooting day landed in the **previous** season.

Verified root cause, both halves of it:

- **Server.** The write target is the block in the required `X-Active-Block`
  header (`enqueue_ai_upload` → `authorize_ai_block`), stored as `job.block_id`;
  the apply path pins itself to that block (CWE-639 guard) and creates the
  episode groups' episodes there. The request carries **no season field**, so
  nothing can contradict the header — not even a client that resolved a
  different season.
- **Client.** `AiImportSubmitScreen` accepted an optional `seasonId`, but the
  controller used it **only** for the client-side AUTHZ gate
  (`checkAiImportCapability`). The upload itself went out with the ambient
  `X-Active-Block` interceptor value, and the screen rendered **no** target at
  all — not even a copy key for it.

Consequence: wizard creates season B + its default block → CTA opens the import
screen with `seasonId = B` → the gate passes (the caller is a member of B) → the
upload still carries season A's stale block → the rows land in season A. The
user's only conclusion is "the episodes ignore the new season", and nothing in
the UI or on the job row contradicts them.

This also blocks the "fresh season per import test round" workflow the dev
data-reset issue depends on.

## What Changes

- **The target is visible.** The submit screen renders `Season {n} · Block {n}`
  directly above the submit action, next to the existing AI disclosure. Both
  numbers come from read DTOs — the season number CACHE-ONLY (an uncached one
  renders `Staffel unbekannt`, never a guess), the block number from the
  resolved scope. The job status screen repeats the same target from the job
  row's server-side snapshot.
- **The target is resolved deliberately, not ambiently.** The screen reuses the
  season-direct scope resolution (`blockScopeResolution`, issue #378) verbatim:
  exactly one block → adopted automatically; several → an inline picker; none →
  an honest "create a block first" state; fetch failure → the code-keyed retry.
  A pick/adoption writes the sticky scope, so the visible line and the
  `X-Active-Block` header cannot disagree. The submit action is **disabled**
  while no target is resolved, and the controller refuses the residual case
  (target season ≠ active block's season) with `ai_import.scope_mismatch`
  before any request.
- **The server refuses a contradiction (advisory backstop, #404 doctrine).**
  Uploads accept an optional `X-Declared-Season` header carrying the season the
  client resolved. The server compares it with the season owning the
  `X-Active-Block` block and refuses a mismatch with the registered 409
  `ai-import.scope-mismatch` — before a document is stored or a job row exists.
  The header stays the authoritative write target; the declaration is advisory,
  and an absent or unparsable value degrades to "no declaration" (a client that
  cannot spell a header must still be able to import).
- **The target is attributable afterwards.** `AiImportJob.target`
  (`{season_id, season_number, block_number}`) snapshots the target at dispatch,
  resolved at the API edge from the block's owning season. Additive and
  nullable; the three columns are written together and degrade the whole
  snapshot to `null` when the season read fails. Migration
  `20261101000001_ai_import_job_target` — no backfill (a pre-#771 row's intended
  target cannot be reconstructed without inventing data).

## Impact

- **Specs:** `ai-import` (ADDED: declared target + snapshot + registered 409),
  `flutter-ai-import-workflow` (ADDED: visible/resolvable target, disabled
  submit without a target, client-side mismatch refusal, job-view repetition).
- **Backend:** `core` (`AiImportTarget`, `AiImportJob.target`,
  `AiImportEnqueueRequest.target`, registry entry `ai-import.scope-mismatch` +
  count), `api` (`ApiError::AiImportScopeMismatch`, handler check + snapshot,
  utoipa header/409 docs, de/en Fluent copy, golden file), `infra` (migration +
  queue insert/row mapping). Versions `core 0.48.0 → 0.49.0`,
  `infra 0.57.0 → 0.58.0`, `api 0.47.0 → 0.48.0`; `openapi.yaml` regenerated.
- **Frontend:** `lib/data/ai_import_repository.dart` (`declaredSeasonId` →
  `X-Declared-Season`), `lib/features/ai_import/import_jobs/import_target.dart`
  (new: season context + cache-only season number + resolved-scope helper),
  `import_submit_screen.dart` (target card, picker, blocked states, disabled
  submit), `import_submit_controller.dart` (mismatch refusal + declaration),
  `import_state.dart` (code-keyed copy), `job_status_screen.dart` (target card),
  ARB catalogs de+en + regenerated l10n, `vendor/breakdown_api/` regenerated.
- **Docs:** new screen spec `docs/design/screens/ai-import-submit.md`; the
  job-status target section in `docs/design/screens/ai-import-jobs.md`; the new
  copy keys in the glossary's ARB inventory. No new icon, so no glossary icon
  row.
- **Tests:** backend handler tests (snapshot, 409 refusal, unparsable
  degradation), golden `ai-import.scope-mismatch.json`; Flutter widget tests
  (target line, single-block auto-adoption, multi-block picker, no-block and
  no-season blocked states), controller tests (mismatch refusal with zero calls,
  declared season on dispatch), repository tests (header on both routes), job
  view test + re-baselined goldens.
- **Out of scope:** the jobs-list identity issue (#763, landed), the dev
  data-reset tooling (#770), and any change to the apply path's block pinning —
  `block_id` remains the single authoritative write target.
