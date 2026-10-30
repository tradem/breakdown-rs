<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (758-ai-import-scene-reconciliation)

## ADDED Requirements

### Requirement: A chunk that extracts no scenes never loses its scene
The script worker SHALL treat a chunk whose extraction returns an empty `scenes`
array as a data-loss event, never as an empty result. Because `extract_scenes`
yields exactly one chunk per detected heading (after duplicate-heading merging),
zero rows for a chunk always means a scene the document has and the preview does
not.

For such a chunk the worker SHALL:
- log a `warn` line carrying the job id, the chunk index/total and the heading;
- push a preview row rebuilt from the deterministic heading — `scene_number`,
  `mood`, `episode` and `shooting_day` as parsed by `extract_scenes`, every
  content field (`location`, `summary`, `characters`, `outfits`, `script_day`)
  empty;
- attach a `DroppedRow` uncertainty with `field = "extraction"` and
  `scene_index` pointing at the rebuilt row.

The job SHALL still reach `succeeded`: the extraction is already paid for and the
reviewer must be able to apply the preserved scene set. The uncertainty kind is
non-blocking by contract, so it never gates the apply.

A chunk that returns one or more rows SHALL NOT be reconciled further: a merged
"index + body" heading pair legitimately yields a single row.

#### Scenario: An empty chunk is rebuilt, not dropped
- **WHEN** a two-chunk script's first chunk extraction returns `scenes: []`
- **THEN** the stored preview carries two rows, the first built from the heading
  (`scene_number`, `mood`, `episode`, `shooting_day`) with empty content
- **AND** the job succeeds

#### Scenario: The degradation is code-keyed and non-blocking
- **WHEN** a row is rebuilt from its heading
- **THEN** the preview carries exactly one `DroppedRow` uncertainty with
  `field = "extraction"` for that row
- **AND** `blocks_apply()` is false for it, so the apply is not gated

#### Scenario: A healthy run synthesizes nothing
- **WHEN** every chunk returns at least one row
- **THEN** `scenes_synthesized = 0` and no `extraction` uncertainty exists

### Requirement: A script preview states detected vs extracted vs rebuilt scenes
`ScriptContext` SHALL carry three additive, `serde(default)` counters, stamped by
the worker at the storing boundary (never taken from the model's answer):
`scenes_detected` (deterministic headings), `scenes_extracted` (rows the model
returned, excluding rebuilt rows) and `scenes_synthesized` (rows rebuilt from a
heading). `scenes.len()` SHALL equal `scenes_extracted + scenes_synthesized`.

A payload stored before the fields existed SHALL still deserialize, with `0` for
each counter meaning "not recorded".

#### Scenario: A shortfall stays visible even when no scene is lost
- **WHEN** a 57-heading document yields 4 model rows and 53 rebuilt rows
- **THEN** the preview exposes `scenes_detected = 57`, `scenes_extracted = 4`,
  `scenes_synthesized = 53`
- **AND** a client can render the shortfall from the payload alone

#### Scenario: Pre-existing previews keep loading
- **WHEN** a preview blob without the counters is read
- **THEN** it deserializes with all three counters `0`

### Requirement: AI-import job telemetry records the scene reconciliation
`Telemetry` and `JobTelemetrySummary` SHALL carry the same three counters, and the
queue SHALL persist them as additive `NOT NULL DEFAULT 0` columns on
`ai_import.ai_import_job`. The owner-fenced worker telemetry write SHALL record
them; the unfenced apply-path write SHALL NOT touch them (the completion-time
telemetry snapshot is immutable). Schedule and merge jobs SHALL record zeros.

#### Scenario: The counters survive the round trip
- **WHEN** a worker records `scenes_detected = 57`, `scenes_extracted = 4`,
  `scenes_synthesized = 53`
- **THEN** the columns hold those values and the job's
  `JobTelemetrySummary` exposes them

#### Scenario: A single divergent job is greppable
- **WHEN** the model's row count differs from the detected heading count
- **THEN** the worker logs one `warn` line naming `scenes_detected`,
  `scenes_extracted`, `scenes_synthesized` and the preview row count
