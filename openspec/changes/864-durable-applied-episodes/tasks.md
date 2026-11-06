<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — 864

## 1. Core — the write port goes away

- [x] 1.1 `AiImportQueue::record_applied_episodes` removed (trait method + its
      merge/accumulate contract doc): the summary is no longer written.
- [x] 1.2 `AiImportJob::applied_episodes` documents the new provenance —
      derived at the read edge, empty exactly when no row of the job is mapped
      to a projected scene, labels owned by the persisted episode.
- [x] 1.3 `ApplyStage`'s stage docs stop listing "the summary" as trailing work
      of the run (it no longer is).

## 2. Infra — derivation at the read edge

- [x] 2.1 `PgAiImportQueue::derived_applied_episodes(&[AiImportJobId])`: one
      batch query — `projection_ai_import_mapping` (kind `scene`) joined to
      `projection_scene` and `projection_episode`, `count(*)` per episode,
      ordered by episode number (id as tiebreak). Reserved mappings drop out
      because their scene is not projected.
- [x] 2.2 `get` fills the single job's summary from it; `list_for_user` fills the
      whole page from ONE query (no N+1).
- [x] 2.3 A failed derivation warms nothing and fails nothing: it logs and
      serves an empty list, like the undecodable JSONB it replaces.
- [x] 2.4 `map_job_row` no longer decodes the column; claim contexts leave the
      field empty by construction.
- [x] 2.5 Migration `20261106000003_drop_applied_episodes` drops the column
      (with a down migration that re-adds it nullable, no backfill).

## 3. API — the handler stops writing

- [x] 3.1 `apply_ai_import`'s post-apply `record_applied_episodes` call removed;
      the comment now states why the response is not a persisted summary.
- [x] 3.2 The response keeps reporting what the request dispatched
      (`ScriptApplyResult::applied_episodes`), documented as a different
      question ("what did this request do") than the job read ("where are this
      job's rows").

## 4. Backend tests

- [x] 4.1 Fakes lose the removed port method (core, infra, api harnesses).
- [x] 4.2 API handler tests keep the response assertions and drop the
      sink/`stored` assertions; the cross-block test still proves no mapping was
      written.
- [x] 4.3 Integration (`ai_import_job_identity`): the summary is derived from
      seeded `scene` mappings + scenes + episodes — two rows in episode 299
      ("Erlösung"), one in an untitled 300, so counts and labels are both
      asserted. No summary write happens anywhere in the test — that IS the
      cancelled-client criterion.
- [x] 4.4 Integration: a reserved mapping and a schedule mapping
      (`scene_shoot`/`shooting_day`) derive no target.
- [x] 4.5 Integration: `list_for_user` derives the same summary as `get`, and a
      never-applied job on the same page still answers empty.

## 5. Client — the hop reads the durable source

- [x] 5.1 `aiJobAppliedEpisodesProvider` reads the persisted summary from the
      cached job row (`appliedEpisodesFromWire`), cache-only like
      `aiJobAppliedProvider` (#800).
- [x] 5.2 `resolvePostImportTarget` falls back to it when the response names no
      episode — the re-apply case — instead of dropping to the request's episode.
- [x] 5.3 Widget test: a re-apply whose response carries an empty list still
      lands on the persisted episode (id, number, name) and publishes the report.

## 6. Housekeeping

- [x] 6.1 `backend/openapi.yaml` regenerated (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`) — the wire field is unchanged, its
      description moved.
- [x] 6.2 Version bumps `core 0.62.0 → 0.63.0`, `infra 0.72.0 → 0.73.0`,
      `api 0.60.0 → 0.61.0` (+ dependency pins, `Cargo.lock`), CHANGELOG entry.
