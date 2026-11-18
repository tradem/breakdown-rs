<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 758-ai-import-scene-reconciliation

## 1. Backend — extraction reconciliation
- [x] 1.1 Add `ScriptContext.scenes_detected/extracted/synthesized` (additive, `serde(default)`).
- [x] 1.2 Rebuild a zero-row chunk's scene from the deterministic heading and attach a non-blocking `DroppedRow` uncertainty (`field = "extraction"`); `warn` with `job_id`, chunk index/total, heading.
- [x] 1.3 Stamp the counters at the storing boundary; add the job-level divergence `warn`.
- [x] 1.4 Keep the Decision scoring pass off rebuilt rows (nothing to score).

## 2. Backend — telemetry and persistence
- [x] 2.1 `Telemetry` + `JobTelemetrySummary` counters; `From<&Telemetry>` mapping.
- [x] 2.2 Migration `20261017000001_ai_import_scene_reconciliation` (`NOT NULL DEFAULT 0` + non-negative CHECK).
- [x] 2.3 `TelemetryValues` range-checked narrowing, fenced-write SQL, row decoding.
- [x] 2.4 Schedule + merge workers record zeros (fully specified literals).

## 3. Tests
- [x] 3.1 Unit: fake LLM returns an empty `scenes` array for one chunk of a two-chunk fixture — row rebuilt, counters, non-blocking uncertainty, job succeeds.
- [x] 3.2 Unit: healthy run records `detected == extracted`, `synthesized == 0`, no uncertainty.
- [x] 3.3 Core: pre-#758 payload deserializes; counters round-trip.
- [x] 3.4 Integration: worker telemetry persists the three columns and the job summary exposes them.
- [x] 3.5 Per-target-episode apply counts: already covered by the issue #763 tests (`applied_episodes` per episode); no new case added.

## 4. Contract and release
- [x] 4.1 `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`.
- [x] 4.2 `frontend-flutter/scripts/regen-client.sh` and commit the diff.
- [x] 4.3 Version bumps `core 0.47.0 → 0.48.0`, `infra 0.56.0 → 0.57.0`, `api 0.46.1 → 0.47.0` + pin updates.
- [x] 4.4 `backend/CHANGELOG.md` `[Unreleased]` entry.

## 5. Flutter (stacked PR)
- [x] 5.1 Preview header renders `{detected} erkannt · {extracted} extrahiert` (de/en l10n + generated localizations).
- [x] 5.2 Jobs list names a degraded import (`scenes_synthesized > 0`) instead of a silent success.
- [x] 5.3 Widget tests for both surfaces.

## 6. Flutter implementation notes
- [x] 6.1 `AiImportJobRowView.scenesSynthesized` (nullable — the Drift cache persists no telemetry column, so a cached paint omits the line instead of claiming a clean run); the authoritative read fills it from `job.telemetry.scenesSynthesized`.
- [x] 6.2 Preview subtitle composes `{rows} · {detected} erkannt · {extracted} extrahiert[ · {n} aus Dokument-Metadaten ergänzt]`; `scenes_detected` absent/`0` renders the row count alone.
- [x] 6.3 l10n keys `aiPreviewScriptReconciliation`, `aiPreviewScriptSynthesized`, `aiJobsRowScenesRebuilt` in de + en, generated localizations regenerated (`flutter gen-l10n`), ARB parity 985/985.
- [x] 6.4 Widget tests: preview header (reconciled + pre-#758 payload) and jobs row (degraded vs clean). Full suite: 1962 passed; goldens unchanged.
- [x] 6.5 `docs/design/screens/ai-import-jobs.md` (row line + new preview section + test note), `frontend-flutter/CHANGELOG.md`, `pubspec.yaml 0.4.0-beta.22+114 → 0.4.0-beta.23+115`.
