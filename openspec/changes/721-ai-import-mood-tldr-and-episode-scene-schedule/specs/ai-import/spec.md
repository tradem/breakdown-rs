<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Deterministic set-shorthand mood extraction and costume-focused Dispo TL;DR
`extract_scenes` SHALL deterministically parse interior/exterior and time-of-day tokens from German and English scene headings into canonical set shorthand (`I/T`, `A/T`, `I/N`, `A/N`, `I/D`, `A/D`, `I/M`, `A/M`, `I/AB`, `A/AB`, `I/A/T`) on `SceneChunk.mood`, where `I/A/T` is the single three-component value for a combined `INT/EXT` heading with a time token. When the LLM omits `DraftScene.mood` on the first scene of a chunk, `ScriptImportWorker` SHALL backfill it from `SceneChunk.mood`. The default script extraction prompt SHALL instruct the model to emit a concise 1–2 sentence Dispo TL;DR in `summary` covering core physical action, costume continuity triggers, and grounded cross-department interfaces (hair/make-up, sound, props) without retelling dialogue.

#### Scenario: German short-form heading backfills canonical mood
- **WHEN** a chunk heading is `"12 I/N - WERKSTATT"` and the LLM returns `mood: null`
- **THEN** `SceneChunk.mood` is `Some("I/N")`
- **AND** the resulting `DraftScene.mood` is backfilled to `Some("I/N")`

#### Scenario: English heading maps to canonical set shorthand
- **WHEN** a chunk heading is `"EXT. STREET - NIGHT"`
- **THEN** `SceneChunk.mood` is `Some("A/N")`

#### Scenario: Combined INT/EXT heading maps to the three-component canonical value
- **WHEN** a chunk heading is `"INT/EXT. WORKSHOP - DAY"`
- **THEN** `SceneChunk.mood` is `Some("I/A/T")`

#### Scenario: Episode mismatch leaves the schedule row unmatched
- **WHEN** Episode 295 provides no matching scene for a row with `episode_number = Some(295)` and `scene_number = Some(10)`
- **AND** Episode 294 contains a Scene 10
- **THEN** `merge_schedule_to_scenes` leaves the row unmatched (it SHALL NOT attach it to Episode 294's Scene 10)

### Requirement: Dot-separated Episode.Scene schedule notation and episode-aware merge
Both native CSV schedule parsing and LLM schedule extraction SHALL accept `<Episode>.<Scene>` references (e.g., `"294.10"`, `"03.05"`) and split them deterministically as integer components into `ShootingScheduleRow.episode_number` and `ShootingScheduleRow.scene_number` without decimal float truncation. When `ShootingScheduleRow.episode_number` is present and `MergeInput` provides episode numbers for applied scenes, `merge_schedule_to_scenes` SHALL match rows by `(episode_number, scene_number)`. If no pair matches, it SHALL leave the row unmatched. It SHALL use `scene_number`-only matching only when episode context is unavailable.

#### Scenario: Trailing zero in Episode.Scene is preserved as scene 10
- **WHEN** a schedule row carries scene reference `"294.10"`
- **THEN** it parses to `episode_number = Some(294)` and `scene_number = Some(10)` (never scene 1)

#### Scenario: Multi-episode block schedule merges by episode and scene number
- **WHEN** a block contains applied Scene 10 in Episode 294 and Scene 10 in Episode 295
- **AND** a schedule row carries `episode_number = Some(295)` and `scene_number = Some(10)`
- **THEN** `merge_schedule_to_scenes` attaches the row to Episode 295's Scene 10
