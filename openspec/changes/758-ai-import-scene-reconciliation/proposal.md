<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Proposal: AI-import scene reconciliation — no silent shortfall between detected headings and applied scenes (issue #758)

## Why

A real production import of the script **299 "Erlösung"** (57 script scenes)
produced an episode with **4 scenes**, and the job reported `succeeded`. The
pipeline has no reconciliation anywhere:

- **Extraction.** `extract_scenes` splits the document deterministically and its
  chunk count is persisted as `chunk_count`, but the preview rows are **only**
  what the model returned (`for (index_in_chunk, mut scene) in
  partial.scenes.into_iter()`). A model answer with an empty `scenes` array
  silently removes that chunk's scene: no log, no counter, no failure — the job
  still reaches `succeeded` with a short preview.
- **Preview/job view.** The only observable number is `scenes.len()` (the model's
  row count). Nothing states how many scene headings the *document* had, so a
  reviewer cannot notice — let alone explain — a 57 → 4 loss.
- **Apply.** Per-target-episode counts are already shipped (issue #763,
  `applied_episodes`), so the loss was *not* hideable at apply time; it happened
  before, invisibly, during extraction.

## What Changes

- **Per-chunk reconciliation (authoritative).** After each chunk's extraction the
  worker compares the deterministic chunk expectation with
  `partial.scenes.len()`. A chunk always corresponds to at least one detected
  heading, so **zero rows is unambiguously a loss** (a chunk may legitimately
  yield one row for an "index + body" heading pair, so "fewer rows than headings"
  is not a defect and is deliberately not treated as one).
  A zero-row chunk now:
  1. logs `warn` with `job_id`, chunk index/total and heading;
  2. **rebuilds the row from the deterministic heading** — `scene_number`,
     `mood`, `episode` and `shooting_day` are already parsed by `extract_scenes`
     — with every content field empty, so the reviewer still sees the scene and
     can apply it;
  3. attaches a **non-blocking** `DroppedRow` uncertainty
     (`field = "extraction"`), so the degradation is code-keyed and visible
     instead of implied. A blocking kind would make the whole preview
     unappliable, which is the opposite of preserving the data.

  Dropping the row is no longer a possible outcome.
- **Per-job reconciliation counters.** `scenes_detected` (deterministic headings),
  `scenes_extracted` (model rows, deliberately excluding rebuilt ones) and
  `scenes_synthesized` (rebuilt rows) are stamped on the stored
  `ScriptContext`, recorded on `Telemetry`, persisted on three additive job
  columns and exposed on `JobTelemetrySummary`. `scenes_extracted <
  scenes_detected` therefore stays visible even when the rebuilt rows preserve
  every scene. A job-level `warn` names any divergence.
- **Wire additions only** (`serde(default)`, `NOT NULL DEFAULT 0`): previews,
  jobs and payloads stored before this change keep loading, and older clients
  keep deserializing. No breaking change, no `/v2`.

## Non-goals

- **No bounded LLM retry for a zero-row chunk.** The retry path is already
  billed; recovering the content by re-asking is a separate, cost-bearing
  feature.
- **No apply-side change.** Per-target-episode application counts and the
  "row X went to episode Y" explanation shipped with issue #763
  (`ApplyAiImportResponse.applied_episodes`, `AiImportJob.applied_episodes`).
- **No UI change in this PR.** The Flutter preview header
  ("`57 erkannt · 4 extrahiert`") and the jobs-list degradation line land in the
  stacked Flutter PR on top of the regenerated client.

## Impact

- `core`: `ScriptContext` (+3 counters), `Telemetry`/`JobTelemetrySummary` (+3).
- `infra`: script worker reconciliation + synthesis, telemetry persistence,
  migration `20261017000001_ai_import_scene_reconciliation`.
- `api`: regenerated `openapi.yaml`; Dart client regenerated in
  `frontend-flutter/vendor/breakdown_api`.
- No projector, no aggregate, no event change: the AI import pipeline is
  operational state (a Postgres queue), not event-sourced business truth.
