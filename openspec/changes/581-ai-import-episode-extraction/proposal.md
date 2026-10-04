<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 581 — AI script import: extract EPISODES, apply creates/assigns episodes

## Why

`flutter-ai-import-workflow` flattens a screenplay into scenes that all land in
ONE explicitly picked episode (`plan_scene_apply` takes a single `episode_id`).
Real screenplays (German TV production scripts) span multiple episodes marked as
`Ep.: <n> (<Titel>)` — on the first page and repeated in page headers. Today the
user must pre-create every episode by hand, pick one target episode per run, and
repeat the import per episode.

## Decisions (user-confirmed)

1. **Extraction: deterministic first, LLM fallback.** The document scanner
   recognises `Ep.: 3 (Titel)` / `Ep: 3 (Titel)` markers (page headers included,
   normalized like scene-heading detection for NBSP/en-dash). The LLM prompt is
   extended to extract an `episode` field only for chunk text that itself names
   an episode in another notation; the deterministic value wins when present.
2. **Scope: backend-only PR.** The Flutter grouped apply screen follows in a
   second PR.
3. **Episode number: from the heading.** `Ep.: 3` → `CreateEpisode.number = 3`.
   A create target without a number is rejected (validation); numbers are
   pre-checked at the API edge against existing series episodes (409
   `episode.number-already-exists`, #404 doctrine — the
   `idx_projection_episode_series_number` unique index remains the
   authoritative backstop, projector savepoint-skip already shipped).
4. **The block stays fixed**: the job's `block_id` is the parent of created
   episodes; `Block:` markers are NOT extracted (the import run targets one
   block by design).

## What Changes

### core (`crates/core`)

- `ai::preview`: `SceneChunk` + `DraftScene` gain optional `episode:
  Option<DraftEpisode>` (`{ number: Option<i32>, title: Option<String> }`,
  `#[serde(default)]` — additive on the wire, old previews keep loading).
- New deterministic marker parser `episode_marker` scanning `Ep.:`/`Ep:` lines;
  `extract_scenes` stamps each chunk with the episode in effect at its heading.
- Stable group key `DraftEpisode::group_key()` (`ep:<n>` / `ep-t:<title>`).
- `plan_scene_apply` accepts per-group episode targets
  (`EpisodeGroupPlan { episode_ref, target: EpisodeTarget }`,
  `EpisodeTarget::Existing | Create { number, name }`); each
  `SceneApplyPlan` carries the resolved `PlannedEpisode`. Rows without episode
  metadata default to the explicit `episode_id` (backwards compatible).

### infra (`crates/infra`)

- `ApplyScriptRequest` gains `block_id` + `episode_groups`.
- `ApplyWorker` gains an `EpisodeCommands` port; a NEW episode is created
  idempotently via the existing mapping-reservation machinery with
  `aggregate_kind = "episode"` keyed by the group ref, before the group's
  scene rows dispatch.
- Script prompt (`config/default_ai_prompts.toml`): optional `episode` field
  rule as LLM fallback.

### api (`crates/api`)

- `ApplyAiImportRequest` gains optional `episode_groups` (absent → today's
  single-episode flow); validation: group refs must exist in the preview,
  create numbers unique per request, API-edge 409 pre-check per number.
- `ApplyAiImportResponse` gains `created_episodes: u32`.
- `openapi.yaml` regenerated (`UPDATE_OPENAPI=1`).

## EU AI Act review gate

The preview payload carries each row's draft episode, so the reviewer sees
WHICH episode every row (and every to-be-created episode) lands in before the
single explicit apply dispatch. No auto-apply.

## Risks / Notes

- CQRS boundary kept: block/series context reaches the worker via
  `ApplyScriptRequest`, resolved at the API edge — never a projection lookup
  in the write path.
- No new projection: the episode projector already exists.
- Frontend (grouped apply screen) deferred to the follow-up PR; single-episode
  flow remains fully functional.
