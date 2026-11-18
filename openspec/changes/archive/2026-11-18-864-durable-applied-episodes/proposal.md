<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 864 — The applied-episode summary is derived from durable apply mappings

## Why

Follow-up to #805 (PR #862), where it was observed live: after a completed apply
of the episode-300 import, the job row's `applied_episodes` was still `NULL`, so
the "land on the imported episode" hop of #759 had no summary to resolve.

The data was fine — the scene rows were committed. The **summary a later feature
reads** was not, for two independent reasons:

1. **Cancel-sensitivity.** `apply_ai_import` wrote the summary *after*
   `ApplyWorker::apply_script` returned. A client that dropped or retried the
   request cancelled the handler future: rows committed, summary not, and
   nothing retried it.
2. **Best-effort by design.** A failing write was a `tracing::warn!`, never an
   error (correct — the rows must not be rolled back), so "no summary" was
   indistinguishable from "no apply ever ran".

The consequence was display/navigation only, never corruption — but the jobs
list (#763) fell back to its kind/date copy and #759's hop to the request's own
episode id, in a state where a durable answer existed all along.

### Discovery evidence

| Question | Tool | Result |
|---|---|---|
| Where does the summary get written? | `search_code` on `applied_episodes` | `api/src/handlers/mod.rs:8189` — the apply handler, after `applied.applied_episodes` came back from `ApplyWorker::apply_script`; the port method was `AiImportQueue::record_applied_episodes` (`infra/src/ai/queue.rs:1145`, JSONB merge + `updated_at` bump). |
| Where is it read? | `trace_path` inbound on `AiImportQueue::get` | Every read surface goes through `get` (single job, SSE refresh) or `list_for_user` (jobs list); both decode the column in `map_job_row`. Claim paths also use `map_job_row` but serve no client. |
| Is the mapping a durable source? | `read` on `mapping.rs` + `workers.rs` | Yes: `projection_ai_import_mapping` has one `scene` row per applied draft row (`aggregate_id` = the scene — new or updated), confirmed per row inside the run. Episodes a run **created** additionally have an `episode` row; a run applying into an *existing* episode has none — so the episode must come from the scene. |
| Where is the scene → episode relation? | `read` on migrations | `projection_scene.episode_id` (migration `20250625000001`), labels in `projection_episode.number/name`. Read model — usable at the read edge, never on the write path (CQRS boundary, AGENTS.md §1). |
| Does a schedule apply write `scene` mappings? | `read` on `schedule_apply.rs` | No — only `scene_shoot` and `shooting_day`. The #763 decision "a schedule merge names no target episode" therefore falls out of the derivation instead of needing a special case. |
| How long do the mappings live? | `read` on `queue.rs::delete_terminal`, `payload_cleanup.rs` | Exactly as long as the job: `delete_terminal` removes mappings and job in one transaction; the payload GC never touches them. So the derivation cannot silently disappear after retention. |
| Who consumes the summary on the client? | `search_code` + `read` on `post_import_report.dart` | `pickAppliedTargetEpisode(outcome.appliedEpisodes ?? [])` only — the POST response, never the job. A re-apply of an applied preview dispatches nothing and returns an **empty** list, so the hop fell back to the request's episode although a durable summary existed. |
| Text (occurrence), not symbols | `rg` | `applied_episodes` in `backend/openapi.yaml` (contract), `CHANGELOG.md`, `openspec/changes/{758,759,763,805,863}`, Drift column `aiAppliedEpisodesJson`, tests. |
| Coverage | `check_index_coverage` on `backend/crates/**`, `frontend-flutter/lib/**` | clean. |

## Decision

**Derive the summary at the read edge from the durable apply mappings, and
delete the denormalized column (issue option (b)).**

Rejected alternatives:

- **(a) Let the worker write the ids.** Cheapest, but it only *shrinks* the
  window: a cancellation during the run — after some rows committed — still
  loses the summary, because the worker future is the handler future. The issue's
  first acceptance criterion ("reflects an apply that committed rows, even when
  the client disconnected before the response") would stay unsatisfiable.
- **(c) A join table written transactionally with the mappings.** Most work, and
  it duplicates information that already exists one join away.

The derivation is authoritative because a row's summary is a function of what
committed: `count(*)` of `scene` mappings grouped by the mapped scenes'
`episode_id`, labelled from `projection_episode`, ordered by episode number. Two
properties fall out for free, and one is a correction:

- a still-**reserved** mapping has no projected scene, so the join drops it — a
  reservation is not applied work;
- the labels are the persisted episode's own, not the request's target;
- a row reconciled onto an **existing** scene is attributed to that scene's
  episode instead of to the episode the request named (the old write path used
  the request's target for every row it dispatched, which could name the wrong
  episode).

Cost: one extra indexed query per read of the job page (`preview_id = ANY($1)`,
PK prefix), plus the removal of a port method, a column and their tests. A
derivation failure degrades to an empty list with a warn — display metadata must
never make a job unreachable, exactly like the undecodable JSONB it replaces.

The **response** of `POST /v1/ai-import/jobs/{id}/apply` keeps reporting what
that request dispatched (the worker's own result): it answers a different
question ("what did I just do") and must not wait for projector catch-up. The
two sources are documented as deliberately distinct.

The client's post-apply hop gains one fallback: when the response names no
episode, it reads the job's persisted summary from the cache
(`aiJobAppliedEpisodesProvider`) instead of dropping straight to the request's
episode. That is the re-apply case — durable by then, empty on the wire.

### What "no summary" means now

`applied_episodes` is empty **iff** no row of this job is mapped to a projected
scene. It no longer means "an apply may have run and lost its write", because
such a write no longer exists: an apply that committed rows leaves mappings, and
mappings are the source. A job that was never applied, and a job whose apply was
cancelled before its first commit, both answer an empty list — honestly.

## Risks

- **Projector lag** is now visible in the summary: a scene whose projection has
  not caught up yet counts only after it does. Acceptable (the previous summary
  named rows the projection did not show yet, which was arguably worse), and it
  self-heals on the next read.
- **Scene deletion** would shrink a count. Scenes are not deletable today; if
  that changes, the count reflects "rows whose scene still exists", which is the
  honest reading of "where this job's rows are".
- The #863 delta spec quotes `record_applied_episodes` as a *late* run-scoped
  write in one scenario's rationale. The scenario itself (owner-scoped claim
  instant) is unaffected — the write it names is simply gone; its generic wording
  ("or any other run-scoped write") still holds.
