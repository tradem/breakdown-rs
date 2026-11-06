<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Design — 829-script-derived-import-target

## D1 — A block-less upload is authorized by its declared season

The block is **not** the authorization scope today; it only *selects* one.
`authorize_ai_block` (`backend/crates/api/src/handlers/mod.rs:6226`) loads the
block and then calls `authorize_season_result` with `block.season_id`
(`crates/api/src/auth/authorization.rs:82`), which evaluates
`has_active_costume_role_in_season`. Removing the block therefore removes no
authorization information — it removes only the *selector*.

So: `X-Active-Block` becomes optional. When absent, `X-Declared-Season` is
**required** and the identical predicate runs on it. Upload matrix:

| `X-Active-Block` | `X-Declared-Season` | Result |
|---|---|---|
| present | absent | today's behaviour: block scope, target snapshot with a block |
| present | present, same season | today's behaviour |
| present | present, other season | `409 ai-import.scope-mismatch` (unchanged, #771) |
| absent | present | **new**: season scope, `block_id = NULL`, target without a block |
| absent | absent | `400` (`domain.validation`) — a client bug, the message widened |
| present | any | `404` for an unknown block, `403 ai-import.forbidden` on denial (unchanged) |
| absent | present | `404 season.not-found` for an unknown season, `403 ai-import.forbidden` on denial |

*Rejected — a new "any costume-dept season" capability
(`has_active_costume_role`-style).* That method already exists for credential
roles and answers "do you hold the role *somewhere*", which is exactly the
weaker question this upload must not ask: it would let a caller import a
document with no season assertion at all and would silently permit a target
season the caller only learns about at attach time.

*Existence oracle.* No new disclosure: `GET /v1/seasons`
(`handlers/mod.rs:1055`) is `Authenticated`-only and not membership-filtered, so
every authenticated caller can already enumerate season ids and numbers. The
`403`/`404` pair for a caller-supplied season id therefore reveals nothing the
read model does not. (The block path already distinguishes "unknown block" from
"foreign block" the same way; block ids are uuidv7 and unguessable, so that has
never been treated as a leak either.)

## D2 — The attach is a job-scoped, set-once write

```
PUT /v1/ai-import/jobs/{id}/target
{ "block_id": "<uuid>" }            ->  200 AiImportJob (the updated view)
```

Why job-scoped rather than apply-carried: the apply's write context
(`project_id`, `season_id`, the parent block of episodes it creates) comes from
the **request's `episode_id`** — `apply_ai_import` resolves the episode, then its
block, then the season (`handlers/mod.rs:7846-7860`); `job.block_id` is used
*only* by the CWE-639 guard. A job-carried target therefore costs the apply
nothing and keeps one value on the wire, while an apply-carried target would
leave the preview with nothing to render, nothing to compare against #827's
script block, and nothing for the client's in-preview episode creation to anchor
on. It also keeps the "one visible target, one sent value" rule of #771/#828.

Contract details:

| Aspect | Rule |
|---|---|
| Semantics | set-once. The same block repeated is `200` and writes nothing (idempotent); a *different* block once one is set is `409 ai-import.target-immutable` |
| Atomicity | `block_id` and `target_block_number` are written in the **same** UPDATE, so the guard value and the displayed value cannot drift |
| `PUT` vs `POST` | `PUT` because the operation is idempotent and replaces a sub-resource; the divergence refusal is a conditional-write conflict, not a new resource |
| Allowed states | `succeeded` only (`409 domain.conflict`, the established precedent from `apply_ai_import`'s status check). `pending`/`running` have no preview yet; `failed`/`dead_letter` must be retried, not re-targeted |
| Applied jobs | `409 ai-import.target-immutable` with the S1 extension `applied: true` — an apply already recorded rows bound to the old block. The guard reads the persisted `accept_as_is IS NOT NULL` column (the source of the derived `AiImportJob.applied`, `queue.rs:1536`), never the mutable apply-progress slot |
| Authorization | `authorize_ai_job(Action::Write)` — owner **and** costume-dept role in the **new** block's season. A caller who may not write in the target season cannot move the job into it |
| Response | the full `AiImportJob` view: the client learns the new `block_id` *and* the new target without a second read |
| Dedup | untouched. `user\|kind\|format\|digest` has no block, so a blind upload and a later attach cannot create a duplicate job. A duplicate upload returns the **existing** job and never re-targets it — the client renders that job's target with the attach action instead |

*Rejected — a `target` field in the apply request.* Two sources of truth for a
security-relevant guard; every "which one won?" bug becomes a silent mis-write.
The preview could not show what the apply will do, which is the defect #771
exists to prevent.

## D3 — A job's authorization scope is its target season

`authorize_ai_job` (`handlers/mod.rs:6345`) currently wraps the season policy in
`if let Some(block_id) = job.block_id`, so a block-less job passes with an owner
check alone. After this change a job always knows a season:

- block-scoped upload → `target.season_id` is the block's season (today's value);
- block-less upload → `target.season_id` is the declared season;
- attach → the target season is unchanged (the attached block must belong to it;
  a block of another season is refused by the same comparison `check_declared_ai_season`
  makes today, answering `409 ai-import.scope-mismatch`).

`authorize_ai_job` therefore always evaluates the season policy on
`target.season_id`, and the `Option` arm disappears. Pre-#829 rows with a target
snapshot keep working; a pre-#771 row with `target = NULL` keeps today's
behaviour (owner-only) because its season genuinely is unknown — documented, not
silently assumed.

**Blast radius (graph-verified):** `trace_path(authorize_ai_job, inbound)` finds
7 callers — `get_ai_import_job`, `list_ai_import_jobs`, `get_ai_import_preview`,
`apply_ai_import`, `delete_ai_import_job`, `stream_ai_import_job_events`,
`stream_ai_import_apply_events` — so the single change in that helper reaches
every job-scoped operation, which is exactly why the fix belongs there rather
than in each handler.

## D4 — An apply requires an attached block

`apply_ai_import` refuses while `job.block_id` is `None` with the registered
`409 ai-import.target-missing` (S1 extension `season_id`, so the client can offer
"Zielblock wählen" for the right season). Two reasons:

1. It closes F1 by construction rather than by adding a second, weaker guard
   mode: the CWE-639 check stays "the target episode's block MUST equal
   `job.block_id`", with no skip branch.
2. It keeps one place where the target is chosen (the target card). A blind
   upload whose target is never named would otherwise apply by guessing from the
   episode picker — which is precisely the class of mistake #771 was filed for.

*Rejected — a season-scoped fallback apply* ("no block attached ⇒ accept any
episode in the target season"). It is safe *after* D3, but it reintroduces two
guard modes, and the episode the reviewer picks at apply time would silently
become the target — the very ambient resolution the reporter objects to.

## D5 — The target freezes at the first group-episode resolution

The in-preview episode creation (`ensureGroupEpisodeResolved`,
`frontend-flutter/lib/features/ai_import/import_jobs/apply_controller.dart:1589`)
writes a **real** episode row into the job's block during review, then adopts it
as a group target. Those ids are block-bound: if the target moved afterwards,
the apply's guard would answer `403` and the created rows would sit in the wrong
block.

Rule: **attach is a pre-review action.**

- Client: once any group has been resolved to an existing episode (adoption or
  in-preview creation), the target card renders read-only with the reason
  ("Ziel blockiert, weil das Vorschau-Episoden-Ziel bereits gewählt ist") instead
  of the adopt/switch/create affordances.
- Server backstop is what it can actually observe: `applied` jobs refuse attach
  (`409 ai-import.target-immutable`, `applied: true`). The server cannot see
  client-side adoptions (they are local until apply), and does not pretend to: a
  client that ignores the client rule gets an honest `403` at apply, never a
  silent mis-write.

*Rejected — invalidate the resolutions on attach.* It leaves real episode rows
behind in the old block, which then collide with the re-create
(`409 episode.number-already-exists`, recoverable only through #705's
block-switch recovery). "Rows created by accident in a block nobody chose" is a
worse outcome than one extra tap before the review starts.

*Rejected — remove the eager creation entirely.* It would remove the whole class,
but it needs a new apply shape for "a group creates an episode with no prior
primary episode", renumbers the reservation path and re-opens the 294.pdf
empty-picker flow. Recorded as a possible later change, not folded in here.

## D6 — The target snapshot may name a season without a block

`AiImportTarget.block_number` becomes `Option<i32>`;
`season_id`/`season_number` stay required. One field, honest absence —
never `block_number: 0`, never a placeholder.

- **No migration.** The three `target_*` columns are already nullable
  (`crates/infra/migrations/20261101000001_ai_import_job_target.up.sql:23-25`);
  only the column `COMMENT` for `target_block_number` widens its meaning. The
  existing "all three written together, whole snapshot degrades to `NULL`"
  discipline becomes "season pair written together; block number written when the
  block is known".
- **Wire compatibility.** Making a required field nullable is additive in the
  read direction (`null` where a number used to be) and breaks no old frame; the
  generated Dart accessor becomes `int?`, which is a client compile fix in the
  same PR series, not a wire break.
- A block-scoped upload behaves exactly as today (`block_number` is `Some`), so
  nothing about #771's snapshot changes for existing usage.

## D7 — The block-less dispatch suppresses the ambient header

`ActiveBlockInterceptor` (`frontend-flutter/lib/src/network/active_block_interceptor.dart`)
attaches `X-Active-Block` to **every** request and never overwrites a caller-set
value. A block-less upload therefore cannot be expressed by "not setting" the
header. Options considered:

- *send a sentinel/blank value* — rejected: a blank header is a malformed-header
  `400` on the block-scoped routes and a wire value that means nothing;
- *per-request opt-out* — **chosen**: `Options.extra['noActiveBlock'] = true`
  makes the interceptor skip attachment for that call. It is an explicit,
  greppable seam (one `extra` key, one branch), it cannot leak into other calls,
  and the repository still sends `X-Declared-Season` explicitly.

The client's in-preview creation then anchors on the job's **effective** target
block (`job.block_id` after an attach — the wire already carries it) rather than
on whatever the upload happened to carry: `aiJobBlockInfo`
(`import_jobs/job_status_controller.dart:220`) returns `null` for a block-less
job, so the creation state is "no target chosen yet" (disabled with the reason)
instead of a hidden failure. The attach response refreshes that provider, so the
creation becomes available without a manual reload.

## Consequences to the apply the issue asks about

- **A group creating an episode** (`EpisodeTarget::Create` →
  `PlannedEpisode::New`, then `create_episode_reserved` in
  `crates/infra/src/ai/workers.rs:2298`) already takes the parent block from the
  request's target episode. No change is needed: after an attach, the reviewer's
  episode picker is anchored to the attached block, so the created episodes land
  there by construction. The preview's client-side creation is the only piece
  that reads the job's block, and D7 re-anchors it.
- **`409 episode.number-already-exists` stays a real outcome** — adopted blocks
  may not hold the episode the preview expects, and numbers are project-unique.
  That is the existing #705 contract (the refusal names the conflicting episode's
  home block so the scope-switch recovery can be offered); this change does not
  touch it.
- **The job list/stream re-renders the target** from the same `AiImportJob` view
  the attach returns (no new wire field). The SSE frame is not required for
  correctness: the attach response already carries the updated job, and the
  cached Drift row is replaced by it.

## Risks / limits

- **Two-device race.** A second client can attach a different block before the
  first one's attach lands: the loser gets `409 ai-import.target-immutable` with
  `existing_block_id` and re-renders the winner's target. No write is lost or
  merged.
- **A frozen target is a real dead end.** A reviewer who resolves a group
  episode in the wrong block must start a new import (or switch the scope and
  re-upload — the dedup key returns the *existing* job, so the honest path is a
  fresh upload of a differently-named copy, or a delete of the failed job). This
  is the price of D5; the alternative (silent invalidation) creates rows nobody
  asked for.
- **`target.season_id` for pre-#771 rows is unknown.** Those jobs keep the
  owner-only gate. They are terminal in practice (the feature has not shipped
  against `/v1`), and D3 does not backfill a season it cannot reconstruct.
- **Block-less jobs have a weaker error surface at attach time**: the client must
  resolve the block number → block id mapping itself (from the season's block
  list, which #828's card already fetches for the picker). A block number the
  season does not have is a client-side "create it first" state, never a server
  guess.
