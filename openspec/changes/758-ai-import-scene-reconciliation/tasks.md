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
- [ ] 5.1 Preview header renders `{detected} erkannt · {extracted} extrahiert` (de/en l10n + generated localizations).
- [ ] 5.2 Jobs list names a degraded import (`scenes_synthesized > 0`) instead of a silent success.
- [ ] 5.3 Widget tests for both surfaces.
