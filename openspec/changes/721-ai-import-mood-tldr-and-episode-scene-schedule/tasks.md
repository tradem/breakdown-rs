<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Tasks: AI import mood (I/T, A/N), costume TL;DR synopsis, and Episode.Scene schedule parsing (issue #721)

## 1. Backend — Core & Infra Extraction / Schedule Merge

- [ ] 1.1 Add `#[serde(default)] pub mood: Option<String>` to `SceneChunk`, parse canonical set shorthand (`I/T`, `A/N`, `I/D`, `I/M`, `I/AB`, etc.) from German and English headings in `extract_scenes`, and backfill `DraftScene.mood` in `ScriptImportWorker`.
- [ ] 1.2 Add `#[serde(default)] pub episode_number: Option<i32>` to `ShootingScheduleRow`, implement `parse_schedule_scene_ref`, wire it into `csv_schedule.rs` and the `LlmClient::extract_schedule` decoding path, extend `MergeInput` + `merge_schedule_to_scenes` for episode-aware matching, and add tests for `"294.10"` and `"03.05"`.
- [ ] 1.3 Update `config/default_ai_prompts.toml` for canonical `mood` shorthand and costume-/cross-department-focused Dispo TL;DR `summary` (no dialogue retelling).
- [ ] 1.4 Regenerate `backend/openapi.yaml` and bump backend crate versions in lockstep (`core → infra → api`).

## 2. Frontend — Regenerated Client & Mood Icon Reinforcement

- [ ] 2.1 Regenerate `vendor/breakdown_api/` via `scripts/regen-client.sh`.
- [ ] 2.2 Add `BreakdownMaterialIcons` mood icon resolver and render reinforcing icons alongside visible `mood` text on scene detail, script overview, and AI preview rows.
- [ ] 2.3 Update `docs/design/glossary.md`, `lib/l10n/app_{de,en}.arb`, and bump `pubspec.yaml` + `CHANGELOG.md`.

## 3. Verification

- [ ] 3.1 Backend unit, contract (`openapi_drift`), and architecture tests green.
- [ ] 3.2 Frontend `dart format`, `flutter analyze`, `breakdown_lints`, and widget/golden tests green.
