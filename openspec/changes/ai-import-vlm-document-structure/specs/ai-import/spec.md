<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# Delta: ai-import — zone-aware script segmentation, deterministic cast precedence, and multimodal schedule streaming

## MODIFIED Requirements

### Requirement: Deterministic set-shorthand mood extraction and costume-focused Dispo TL;DR
`extract_scenes` (and zone-aware `ScriptBody` segmentation) SHALL deterministically parse interior/exterior and time-of-day tokens from German and English scene headings — including combined slash and plus forms (`I/A`, `A/I`, `I+A`, `A+I`, `INT/EXT`, `INT./EXT.`) — into canonical set shorthand (`I/T`, `A/T`, `I/N`, `A/N`, `I/D`, `A/D`, `I/M`, `A/M`, `I/AB`, `A/AB`, `I/A/T`, `I/A/N`, `I/A/D`, `I/A/M`, `I/A/AB`) on `SceneChunk.mood`, where `I/A/<Time>` is the canonical three-component form for any combined interior/exterior heading regardless of `I`/`A` ordering or `/` vs. `+` separator. When the LLM omits `DraftScene.mood` on the first scene of a chunk, `ScriptImportWorker` SHALL backfill it from `SceneChunk.mood`. The default script extraction prompt SHALL instruct the model to emit a concise 1–2 sentence Dispo TL;DR in `summary` covering core physical action, costume continuity triggers, and grounded cross-department interfaces (hair/make-up, sound, props) without retelling dialogue.

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

#### Scenario: German plus-separated combined heading splits and normalizes cleanly
- **WHEN** a `ScriptBody` line reads `"3 A+I/T - STRASSE + KLINIKUM / EINGANG"` or `"42 I+A/T - HAUPTEINGANG"`
- **THEN** it is recognized as a valid scene heading with `scene_number = Some(3)` (or `Some(42)`)
- **AND** `SceneChunk.mood` is normalized to `Some("I/A/T")`

#### Scenario: Episode mismatch leaves the schedule row unmatched
- **WHEN** Episode 295 provides no matching scene for a row with `episode_number = Some(295)` and `scene_number = Some(10)`
- **AND** Episode 294 contains a Scene 10
- **THEN** `merge_schedule_to_scenes` leaves the row unmatched (it SHALL NOT attach it to Episode 294's Scene 10)

### Requirement: Dot-separated Episode.Scene schedule notation and episode-aware merge
Both native CSV schedule parsing and multimodal/LLM schedule extraction SHALL accept `<Episode>.<Scene>` references (e.g., `"294.10"`, `"03.05"`) as well as shot-suffixed `<Episode>.<Scene><Suffix>` references (e.g., `"300.37N"` for pick-up/insert shots) and split the leading numeric components deterministically as integers into `ShootingScheduleRow.episode_number` and `ShootingScheduleRow.scene_number` without float truncation, recording any trailing alphabetic shot suffix additively on the row while preserving the verbatim `row_ref`. Non-episode production unit codes (e.g., `"SB7.2"`, `"T3"` `"Vorspann"`) SHALL retain `episode_number = None` and `scene_number = None` so they surface honestly in `unmatched_schedule_rows` without fabricating scene numbers. When `ShootingScheduleRow.episode_number` is present and `MergeInput` provides episode numbers for applied scenes, `merge_schedule_to_scenes` SHALL match rows by `(episode_number, scene_number)`. If no pair matches, it SHALL leave the row unmatched. It SHALL use `scene_number`-only matching only when episode context is unavailable.

#### Scenario: Trailing zero in Episode.Scene is preserved as scene 10
- **WHEN** a schedule row carries scene reference `"294.10"`
- **THEN** it parses to `episode_number = Some(294)` and `scene_number = Some(10)` (never scene 1)

#### Scenario: Multi-episode block schedule merges by episode and scene number
- **WHEN** a block contains applied Scene 10 in Episode 294 and Scene 10 in Episode 295
- **AND** a schedule row carries `episode_number = Some(295)` and `scene_number = Some(10)`
- **THEN** `merge_schedule_to_scenes` attaches the row to Episode 295's Scene 10

#### Scenario: Pick-up shot suffix matches owning scene without creating a phantom scene
- **WHEN** a schedule row carries scene reference `"300.37N"`
- **THEN** it parses to `episode_number = Some(300)`, `scene_number = Some(37)`, and `shot_suffix = Some("N")` while keeping `row_ref` identifiable
- **AND** `merge_schedule_to_scenes` attaches it to Episode 300's Scene 37

#### Scenario: Non-episode opening-credits unit stays unmatched
- **WHEN** a schedule row carries unit reference `"SB7.2"` or `"T3"` (`"Vorspann"`)
- **THEN** `episode_number` and `scene_number` remain `None`
- **AND** `merge_schedule_to_scenes` places the row in `unmatched_schedule_rows`

## ADDED Requirements

### Requirement: Zone-aware screenplay segmentation isolates front-matter from ScriptBody
Before generating `SceneChunk`s, screenplay segmentation SHALL classify `StructuredDocument` pages into semantic zones (`TitlePage`, `CastList`, `SceneIndex`, `FrontMatter`, `ScriptBody`). Only blocks within `ScriptBody` SHALL produce `SceneChunk`s, sliced verbatim from the document's text blocks without LLM prose re-transcription. Repeating running headers (`Block`, `Ep.:`), page footers, and page-turn continuation banners (`"<N> CONTINUED:"`, `"FORTSETZUNG"`) SHALL be stripped from `SceneChunk.text`.

#### Scenario: Multi-page synopsis after a Script Report never contaminates scene chunks
- **WHEN** a screenplay contains `"SCRIPT REPORT"` index entries `1..42` on pages 3–4, `"SYNOPSIS"` and `"MEDIZINISCHE FÄLLE"` prose on pages 5–10, and `ScriptBody` scenes `1..42` on pages 11–95
- **THEN** segmentation produces exactly `42` `SceneChunk`s from pages 11–95
- **AND** Chunk 42's `text` contains zero lines from pages 3–10

#### Scenario: Page-break continuation headers are stripped while preserving verbatim action and dialogue
- **WHEN** Scene 2 spans pages 11–13 with running headers `"Block 100 / Ep.: 299/2"` and `"2 CONTINUED: (2)"`
- **THEN** Scene 2 produces a single `SceneChunk` whose `text` excludes the running header and `"CONTINUED:"` lines
- **AND** every action and dialogue phrase inside `SceneChunk.text` remains verbatim so `verify_draft_outfits` validates `source_quote` substrings accurately

### Requirement: SceneIndex manifest reconciliation surfaces scene-count discrepancies
When a screenplay contains a `SceneIndex` zone (e.g., `"SCRIPT REPORT"`), segmentation SHALL extract the ordered expected scene labels from `SceneIndex` and compare them against the scene labels extracted from `ScriptBody`.

#### Scenario: Matching SceneIndex and ScriptBody produce zero structural warnings
- **WHEN** `SceneIndex` lists scenes `1..40` and `ScriptBody` yields scenes `1..40`
- **THEN** `ScriptContext` records parity with zero structural mismatch uncertainties

#### Scenario: Missing body scene surfaces a targeted uncertainty
- **WHEN** `SceneIndex` lists scene `18` (`"18 I/T - LABOR"`) but `ScriptBody` contains no chunk numbered `18`
- **THEN** `ScriptContext` records an explicit `Uncertainty` (`field: "scene_number"`) naming the missing scene `18` rather than silently dropping it

### Requirement: Deterministic cast-category precedence resolves CastDirectory, season cast, and inline markers without false positives
Screenplay processing SHALL parse `CastList` pages into a `CastDirectory` (`main_cast` for `"HAUPTCAST"`/`"HAUPTROLLEN"`, `guest` for `"EPISODENHAUPTROLLEN"`/`"GASTROLLEN"`/`"CROSS"`, `extra` for `"KOMPARSEN"`/`"STATISTEN"`) and pass it as read-only grounding context to Pass 1 chunks. Final `CharacterCategory` assignment SHALL be resolved deterministically in `crates/core` in strict priority order: (1) explicit `CastDirectory` entry, (2) existing season `Character` category supplied at job start, (3) inline scene background marker (`(OT)`, `Statist`, `Komparse`) → strictly `extra`, (4) zero-dialogue generic role designator across `ScriptBody` → `extra`, (5) `main_cast` default. Kerning-split names in `ScriptBody` (e.g., `"Mik k o"`) SHALL normalize only against known `CastDirectory` entries.

#### Scenario: Episodic lead marked (OT) on CastList resolves to guest without promoting unlisted (OT) extras
- **WHEN** `CastList` lists `"Jonas Weber (8, OT)"` under `"EPISODENHAUPTROLLEN"`
- **AND** Scene 5 introduces `"PASSANT (OT)"` who is absent from `CastList`
- **THEN** `"Jonas Weber"` is classified as `guest` with zero blocking uncertainties
- **AND** `"PASSANT"` is classified strictly as `extra` (never `guest`)

#### Scenario: Named background performer under KOMPARSEN resolves to extra without inline scene markers
- **WHEN** `CastList` lists `"Heiko Neubert"` under `"KOMPARSEN"`
- **AND** Scene 14 mentions `"HEIKO NEUBERT"` without an inline `(OT)` marker
- **THEN** `"HEIKO NEUBERT"` is classified deterministically as `extra`

#### Scenario: Crossover character under CROSS resolves to guest
- **WHEN** `CastList` lists `"Dr. Kai Hoffmann"` under `"CROSS"`
- **THEN** `"Dr. Kai Hoffmann"` is classified as `guest`

### Requirement: Page-streaming multimodal schedule extraction preserves multi-row cells and additive cast legends
Non-CSV shooting schedules SHALL be extracted page-by-page using multimodal vision (`LlmClient::chat_vision_constrained`) with carry-over of the active shooting-day banner (`shooting_day_label`, `date`) across page breaks, publishing per-page job progress frames. Rest-day banners (`"Drehfrei"`) SHALL NOT emit rows or shooting days. When a schedule contains a numeric role legend (`"ROLLEN"`), the extractor SHALL populate an optional `cast_legend` map and validate per-row numeric cast IDs against it as strictly additive preview metadata; applying a schedule SHALL NEVER create, rename, or reclassify `Character` aggregates.

#### Scenario: Multi-page schedule carries active shooting day across a page break and skips rest days
- **WHEN** page 2 ends under `"3. Drehtag: Mi. 20.10.2021"` and page 3 begins with three scene rows before `"4. Drehtag: Do. 21.10.2021"` and later contains `"Drehfrei: So. 24.10.2021"`
- **THEN** the first three rows on page 3 inherit `"3. Drehtag: Mi. 20.10.2021"`
- **AND** no row or shooting day is emitted for `"Drehfrei: So. 24.10.2021"`

#### Scenario: Stacked multi-row cells preserve both Episode.Scene and script day
- **WHEN** a schedule cell block prints `"300.33"` on line 1 with `"2"` directly underneath in column 1 and a wrapped location across lines 1–2
- **THEN** the extracted `ShootingScheduleRow` carries `episode_number = Some(300)`, `scene_number = Some(33)`, and full unwrapped `location` without mistaking script day `"2"` for a separate scene row

#### Scenario: Numeric cast legend attaches read-only role modifiers without mutating characters on apply
- **WHEN** page 1's `"ROLLEN"` legend maps `2 -> "Ben Ahlbeck"`, `150 -> "Zoe (Dummy)"`, and `1040 -> "Rafael (Nur Stimme)"`
- **AND** a schedule row lists cast numbers `"2, 150, 9999"`
- **THEN** the preview row resolves `2` and `150` (including the `Dummy` modifier), drops unknown `9999` without error, and dispatches zero `CharacterCommands` during schedule apply
