<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — 721 AI Import: Set-Shorthand Mood, Costume TL;DR Synopsis, and Episode.Scene Schedule Parsing

## Decisions

### D1 — Canonical set-shorthand `mood` (`I/T`, `A/N`, `I/D`, `I/M`, `I/AB`) on `SceneChunk`
`extract_scenes` derives `SceneChunk.mood: Option<String>` deterministically from screenplay headings:
- German short form (`12 I/T - WERKSTATT`, `8 A/N - STRASSE`): the `I`/`A` prefix and `T`/`N`/`D`/`M`/`AB` time token normalize directly to `"I/T"`, `"A/N"`, `"I/D"`, `"I/M"`, `"I/AB"` (and `A/*` counterparts).
- German spelled-out (`INNEN WOHNUNG - NACHT`) and English (`INT. KITCHEN - DAY`, `EXT. STREET - NIGHT`, `DUSK`/`DAWN`, `MORNING`, `EVENING`): map interior/exterior (`INT`/`INNEN` -> `I`, `EXT`/`AUSSEN` -> `A`, `INT/EXT` -> `I/A`) and trailing time token (`DAY`/`TAG` -> `T`, `NIGHT`/`NACHT` -> `N`, `DUSK`/`DAWN`/`DÄMMERUNG` -> `D`, `MORNING`/`MORGEN` -> `M`, `EVENING`/`ABEND` -> `AB`). The combined interior/exterior heading serializes as the single three-component canonical value `I/A/T` (e.g., `INT/EXT. WORKSHOP - DAY` -> `"I/A/T"`, `INT/EXT` without a trailing time token does not occur and is not a canonical mood); it is the only three-component value in the set.
- `ScriptImportWorker` backfills `scene.mood` from `chunk.mood` on the first scene of a chunk when `scene.mood` is `None`.

### D2 — Reinforcing Material icons alongside visible `mood` text
Per `docs/design/glossary.md`, icons reinforce visible text and never replace it. `BreakdownMaterialIcons.forSceneMood(String? mood)` returns the interior/exterior icon (`Icons.home_outlined` for `I`, `Icons.park_outlined` for `A`, `Icons.sensor_door_outlined` for the combined `I/A` component, i.e. for a `I/A/T` mood) and time-of-day icon (`Icons.wb_sunny_outlined` for `T`, `Icons.dark_mode_outlined` for `N`, `Icons.wb_twilight_outlined` for `D`/`M`, `Icons.bedtime_outlined` for `AB`) rendered next to the visible `mood` label.

### D3 — Costume- & cross-department-focused Dispo TL;DR (`summary`)
`config/default_ai_prompts.toml` defines `<summary>` as a 1–2 sentence production/Dispo TL;DR:
1. Core physical action and participating figures (strictly no dialogue retelling).
2. Costume-relevant conditions (weather/rain, dirt/blood, fight/stunt, in-scene change, time jump).
3. Cross-department interfaces stated in the block (Hair/Make-up, Sound, Props/Art Dept.).
`sanitize_meta_summary` (#668) remains the deterministic post-extraction guard.

### D4 — Lossless `<Episode>.<Scene>` schedule parsing & episode-aware merge
`parse_schedule_scene_ref(raw: &str)` parses `"294.10"` as `(Some(294), Some(10))` by splitting on `.` as two integer components — never as a decimal float. `ShootingScheduleRow` gains `#[serde(default)] pub episode_number: Option<i32>`, and `MergeInput` carries an optional `episode_numbers: HashMap<EpisodeId, i32>` map prepared at the API edge so `merge_schedule_to_scenes` matches `(episode_number, scene_number)` without violating the CQRS boundary.
