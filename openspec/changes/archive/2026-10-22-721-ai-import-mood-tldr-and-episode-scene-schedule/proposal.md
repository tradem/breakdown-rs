<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## Why

Issue #721: AI import exploration revealed three extraction gaps across script and shooting-schedule imports:

1. **Missing `mood` extraction (`I/T`, `A/N`, `I/D`, `I/M`, `I/AB`):** `SceneDetails.mood`, `DraftScene.mood`, `SceneView.mood`, and `DispoRow.mood` exist end-to-end, but `extract_scenes` discards the interior/exterior + time-of-day token after heading detection, and `config/default_ai_prompts.toml` only states `mood only when the text states it`. As a result, `mood` is nearly always `null` on AI-imported scenes. On set, standard abbreviations (`I/T`, `A/N`, etc.) are universal and benefit from reinforcing icons in the Flutter UI.
2. **Unfocused `summary` prompt:** `config/default_ai_prompts.toml` currently asks for a generic factual sentence plus appended `<props>` strings. For costume breakdown and Dispo sheets, `summary` must act as a concise 1–2 sentence **TL;DR synopsis** focused on physical action, costume continuity triggers (weather, water, dirt/blood, stunts, in-scene changes), and cross-department interfaces (hair/make-up, sound, props/art dept.), strictly excluding dialogue retelling.
3. **Dot-separated `Episode.Scene` schedule references (e.g., `294.10`):** Production shooting schedules format scene numbers as `<Episode>.<Scene>` (`294.01`, `294.10`). Because `ShootingScheduleRow.scene_number` is a single `Option<u32>`, CSV schedule imports reject `"294.10"` and LLM schedule imports risk reading `294.10` as decimal `294.1` (turning scene 10 into scene 1) while losing episode disambiguation when merging across multi-episode blocks.

## What Changes

- `core` (`crates/core/src/ai/preview.rs`):
  - Extend `SceneChunk` with `#[serde(default)] pub mood: Option<String>`, populated deterministically from German short-form (`I/T`, `A/T`, `I/N`, `A/N`, `I/D`, `A/D`, `I/M`, `A/M`, `I/AB`, `A/AB`), German long-form (`INNEN ... - TAG` -> `I/T`), and English (`INT. ... - DAY` -> `I/T`, `EXT. ... - NIGHT` -> `A/N`) scene headings.
  - Extend `ShootingScheduleRow` with `#[serde(default)] pub episode_number: Option<i32>` and a deterministic `parse_schedule_scene_ref` helper that splits `"<Episode>.<Scene>"` strings (e.g., `"294.10"` -> `episode_number: Some(294), scene_number: Some(10)`) without floating-point coercion.
  - Extend `MergeInput` / `merge_schedule_to_scenes` so schedule rows carrying `episode_number` match scenes by `(episode_number, scene_number)`; a row whose pair matches no scene stays unmatched, and `scene_number`-only matching applies only when episode context is unavailable.
- `infra`:
  - `ScriptImportWorker`: backfill `scene.mood` from `chunk.mood` on the first scene of a chunk when the model leaves `mood` empty (same server-truth doctrine as `scene_number`, `episode`, and `shooting_day`).
  - `csv_schedule.rs` & `ShootingScheduleSchema`: parse `scene_number` via `parse_schedule_scene_ref` so `"294.10"` populates `episode_number: Some(294)` and `scene_number: Some(10)`.
  - `config/default_ai_prompts.toml`: update `<location>`/`<mood>` to specify canonical set shorthand (`I/T`, `A/N`, etc.) and rewrite `<summary>` into a concise 1–2 sentence costume- and cross-department-focused Dispo TL;DR while retaining `<props>` as the instruction to record grounded, named props in `<summary>` (no dialogue retelling; `sanitize_meta_summary` guard unchanged).
- `frontend-flutter`:
  - `BreakdownMaterialIcons`: add mood icon resolution pairing interior/exterior (`home_outlined` / `park_outlined`) and time-of-day (`wb_sunny_outlined`, `dark_mode_outlined`, `wb_twilight_outlined`, `bedtime_outlined`) icons alongside the visible `I/T` text on scene detail, script overview, and AI preview rows.
  - Register mood icons and copy keys in `docs/design/glossary.md` and regenerate `vendor/breakdown_api/`.

## Impact

- **CQRS boundary:** `merge_schedule_to_scenes` remains pure; episode number context for applied scenes is pre-loaded into `MergeInput` at the authorized API boundary.
- **Wire compatibility:** `SceneChunk.mood` and `ShootingScheduleRow.episode_number` are additive (`#[serde(default)]`); existing stored previews deserialize unchanged.
- **Affected specs:** `specs/ai-import/spec.md`, `specs/flutter-ai-import-workflow/spec.md`, `docs/design/glossary.md`.
