<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ADR-039: A Target-Less AI Import — Declared-Season Upload, Set-Once Target Attach, and the Target Season as the Job Scope

**Status**: Proposed
**Date**: 2026-11-06
**Author**: Tobias Rademacher (@tradem); deepseek-v4.1-flash (opencode-go)
**Related**: ADR-005 (Axum), ADR-006 (utoipa OpenAPI), ADR-030 (AI Import Bounded Context), ADR-031 (HTTP Error Surface), ADR-035 (production-kind-flexible hierarchy), ADR-038 (AI import SSE progress)
**Source change**: tracked in GitHub issue #829 (`openspec/changes/829-script-derived-import-target/`)

---

## Context

Since the AI import exists, its write target has been "the block that is active
right now": `X-Active-Block` is **required** on both upload routes, the job
stores that block in `ai_import.ai_import_job.block_id`, and the apply pins
itself to it (the CWE-639 cross-block guard). Issue #771 made the target
*visible* and refused a contradicting `X-Declared-Season`; issue #827 published
the block the **document** states; issue #828 made the target switchable and
creatable before an upload.

The reporter's remaining request — *"the target should also be takeable from the
script"* — is not a UI change. A target can only be taken from the script
**after** extraction, so the upload must be allowed to exist without a block, and
the block must be attachable later. Three things made that a contract change
rather than a client change:

1. `authorize_ai_block` (`api/src/handlers/mod.rs`) requires the header, loads the
   block, and evaluates the **season** policy on `block.season_id`
   (`api/src/auth/authorization.rs`, `has_active_costume_role_in_season`).
2. The job's block drives everything downstream — the apply's cross-block guard,
   the parent block of episodes a group creates, and `authorize_ai_job`.
3. The data model already tolerated a block-less job (`block_id` is nullable and
   the apply handler documented "a block-less job stays unguarded by design"),
   but **no path produced one**, and that documented state turned out to be an
   authorization hole (see "Finding" below).

## Finding: the documented "unguarded by design" was an IDOR

`authorize_ai_job` wrapped the season policy in `if let Some(block_id)`, and
`apply_ai_import` calls it as its **only** authorization check. A block-less job
would therefore have passed with an ownership check alone, letting any
authenticated caller apply AI-extracted scenes into an episode of a season they
hold no role in — while the handler's own comment claimed the opposite. The state
was unreachable only because nothing created such a job; this change is exactly
what would have made it reachable. Closing it is therefore a prerequisite of the
feature, not a follow-up.

## Decision

**D1 — A block-less upload is authorized by its declared season.**
`X-Active-Block` becomes optional. When it is absent, `X-Declared-Season` becomes
required and `authorize_season_result(Action::Write)` runs on it: the *identical*
season-typed predicate the block path evaluates on the block's owning season. The
block was never the authorization scope — it selected one — so the block-less arm
grants no reach the block path did not. Missing both headers is a `400`; an
unknown season answers the established `season.not-found`; a season without the
costume-dept role answers `403 ai-import.forbidden`.

*No new existence oracle:* `GET /v1/seasons` is `Authenticated`-only and
membership-**unfiltered**, so every authenticated caller can already enumerate
season ids and numbers. A `403`/`404` pair on a caller-supplied season id
discloses nothing the read model does not.

**D2 — The target is attached by one job-scoped, set-once write.**
`PUT /v1/ai-import/jobs/{id}/target` (`{block_id}`) answers the updated job. The
adapter performs it in ONE conditional statement
(`SET block_id, target_block_number, updated_at WHERE id = $1 AND block_id IS
NULL AND accept_as_is IS NULL AND target_season_id IS NOT NULL`), so no
read-then-write window exists, the guard value and the displayed number cannot
drift, and a job whose apply already landed rows is frozen. The same block
repeated is an idempotent `200` **in every state, including after an apply** — a
retry asks for nothing that is not already true; a different block is
`409 ai-import.target-immutable` (`existing_block_id`); an applied job with a
different block is the same code with `applied: true`. Only `succeeded` jobs
accept a target, only a block of the job's target season (`409
ai-import.scope-mismatch`), and only a job that carries a target season at all
(`NoTargetSeason` -> `409 domain.conflict`: the season is the attach's scope and
the snapshot's other half, so a block number stored without it would leave a
target that no longer decodes). The statement is covered by a real-Postgres
suite rather than only by the in-memory fake — the review of the change found
that the predicate could otherwise be dropped without a red test.

Job-scoped rather than an apply-request field, because the apply's write context
(`project_id`, `season_id`, the parent block of created episodes) already comes
from the request's `episode_id` — `job.block_id` is used *only* by the guard. One
value on the wire keeps the preview, the client's in-preview episode creation and
the apply consistent; an apply-carried target would leave the preview with
nothing to render or compare.

**D3 — A job's authorization scope is its target season.**
Every job-scoped operation (status, preview, both event streams, apply, attach,
delete) gates on `AiImportTarget.season_id`; the block's season remains the
fallback for a pre-#771 row whose target genuinely is unknown (documented
owner-only behaviour). `authorize_ai_job` therefore never degrades to an
ownership-only check.

**D4 — An apply requires an attached target block.**
`409 ai-import.target-missing` (S1 `season_id`) while `block_id` is `NULL`, so the
CWE-639 guard keeps exactly one meaning instead of gaining a "matches when known"
skip branch.

**D5 — The target freezes at the first group-episode resolution.**
The in-preview episode creation writes real episode rows into the job's block;
those ids are block-bound. The preview therefore renders the locked state once a
group points at an existing episode, and the server's own backstop is the
applied-job refusal (`D2`). A client that ignores the client-side rule gets an
honest `403` at apply — never a silent mis-write.

**D6 — The target snapshot may name a season without a block.**
`AiImportTarget.block_number` is `Option<i32>` (`None` = "no target block chosen
yet", never `0`); the season pair stays all-or-nothing. No migration: the three
`target_*` columns were nullable from the start, only their documented meaning
widens.

**D7 — A block-less dispatch suppresses the ambient header per request.**
`ActiveBlockInterceptor` attaches `X-Active-Block` to every request and never
overwrites a caller value, so "no target" needs an explicit
`Options.extra['noActiveBlock'] = true` opt-out. A blank or sentinel header was
rejected: a blank header is a malformed-header `400` on the block-scoped routes
and a wire value that means nothing.

## Consequences

### Positive

- The reporter's flow exists end to end: upload a script without a target,
  extract, take the block from the document (or create it), apply.
- The block-less state has a real authorization owner (the declared season)
  instead of a documented-but-unenforced exemption.
- One visible target, one sent value, one guard meaning — across the upload, the
  preview, the in-preview episode creation and the apply.
- The failure modes are branchable problem codes (`target-missing`,
  `target-immutable` with `existing_block_id`/`applied`), so the client renders
  copy instead of retrying blindly.

### Negative

- A frozen target is a real dead end: a reviewer who resolved a group episode in
  the wrong block starts a new import. The alternative (silent invalidation)
  leaves episode rows in a block nobody chose.
- Two modes of uploading (block-bearing and block-less) meet in one handler; the
  `AiUploadTarget::{Block, Season}` enum keeps them apart, but it is one more
  branch to keep honest.
- `authorize_ai_job` now reads the target rather than the block, so a pre-#771
  row's scope depends on a fallback that must not be quietly assumed.

## Alternatives Considered

- **A new "any costume-dept season" capability.** It answers the weaker question
  ("do you hold the role somewhere") and removes the season assertion from the
  upload entirely — a strictly larger grant for the same user gesture.
- **An apply-carried target field.** Two sources of truth for a security-relevant
  guard, and the preview could not show what the apply will do — the defect #771
  exists to prevent.
- **A season-scoped fallback apply** (no block attached ⇒ any episode in the
  target season). Safe after D3, but it reintroduces two guard modes and lets the
  apply-time episode pick silently *become* the target.
- **Removing the eager in-preview episode creation.** It would remove the whole
  "row created in the wrong block" class, but it needs a new apply shape for "a
  group creates an episode with no prior primary episode" and re-opens the
  294.pdf empty-picker flow. Recorded as a possible later change.
- **A blank/sentinel `X-Active-Block` for the block-less upload.** A blank header
  is a malformed-header `400` on the block-scoped routes; a sentinel is a wire
  value with no meaning.

## Notes

- Duplicate detection is untouched: the dedup key is
  `user|kind|format|digest|` + no block, so a blind upload and a later attach
  cannot create a second job — and a duplicate re-upload **never** re-targets the
  existing job (the client offers the attach for that job instead).
- Pre-#771 rows (`target = NULL`) keep an ownership-only scope: their season
  cannot be reconstructed and is not invented.
- Screen-level behaviour lives in `docs/design/screens/ai-import-submit.md` and
  `docs/design/screens/ai-import-jobs.md`.
