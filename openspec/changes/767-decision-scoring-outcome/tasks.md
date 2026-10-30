<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 767 — Tasks

## 1. Backend: the job records what the scoring pass did

- [x] 1.1 `core`: `DecisionOutcome` (`ran`, `skipped_no_config`,
      `client_unavailable`, `scoring_failed`, `skipped_not_applicable`;
      snake_case wire values) and `DecisionTelemetry`
      (`provider`, `model`, `outcome`, `failed_rows`) next to
      `JobTelemetrySummary`; `AiImportJob.decision_telemetry` additive with
      `serde(default)`.
- [x] 1.2 `core`: `Telemetry.decision` carries the outcome through the existing
      completion write (fully specified at both worker sites and the merge
      worker, per the #307 convention).
- [x] 1.3 `infra`: migration `20261102000001_ai_decision_telemetry`
      (`decision_telemetry JSONB`, no backfill) + down migration.
- [x] 1.4 `infra`: `TelemetryValues` serializes the outcome and
      `record_worker_telemetry` writes it in the same owner-fenced statement;
      `map_job_row` decodes it (advisory: an undecodable payload degrades to
      `None` instead of failing the job read).
- [x] 1.5 `infra`: `DecisionResolution` (`Available(DecisionPass)` /
      `Unavailable { provider, model }`) replaces the bare
      `Option<Arc<DecisionPass>>` on both workers; `resolve_decision` resolves
      the configuration and reports the reason.
- [x] 1.6 `infra`: `info` log (`job_id`, `config_id`) when no decision config
      resolves at claim time — the previously traceless path; the existing
      `warn`s stay.
- [x] 1.7 `infra`: `score_script_chunk` / `score_schedule_rows` return the
      number of rows the failed request left unscored (per chunk; every
      labelled schedule row), summed into `failed_rows`.

## 2. Backend: tests (the missing regression guard)

- [x] 2.1 Configured path end to end through the production worker: non-null
      `scene_score` / `synopsis_score`, rubric `decision_provider` /
      `decision_model` matching the configuration, outcome `ran`.
- [x] 2.2 Unbuildable client: the job still succeeds, no decision request is
      issued, every score stays `None`, outcome `client_unavailable` with the
      resolved pair.
- [x] 2.3 No configuration: outcome `skipped_no_config` with no provider/model.
- [x] 2.4 Failed scoring request: rows keep the honest `scoring_failed` rubric,
      outcome `scoring_failed`, `failed_rows` = the affected row count.
- [x] 2.5 Worker-loop boundary: an unreadable decision credential resolves to
      `Unavailable` (never to the `None` a missing config produces), and an
      unconfigured job resolves to nothing without reading a credential.
- [x] 2.6 Wire contract: a pre-#767 payload deserializes with
      `decision_telemetry: null`; a recorded outcome serializes with its
      snake_case class and omits an absent provider/model.
- [x] 2.7 Postgres integration test: `record_worker_telemetry` persists the
      outcome and `get` decodes it back onto the job view.
- [x] 2.8 `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`
      regenerates `backend/openapi.yaml`.

## 3. Frontend: surface the outcome

- [x] 3.1 `scripts/regen-client.sh` regenerates `vendor/breakdown_api/`
      (`DecisionTelemetry`, `DecisionOutcome`,
      `AiImportJob.decisionTelemetry`); no hand edit.
- [x] 3.2 `decision_outcome.dart`: `aiJobDecisionTelemetry` (single snapshot
      read, never a second SSE consumer), `aiDecisionPairLabel`,
      `aiDecisionSummary` (one arm per stable outcome class, unknown future
      values degrade to the neutral "not recorded" copy),
      `AiDecisionOutcomeLine` (preview) and `AiDecisionOutcomeText` (cost card,
      no second read) plus `AiScoringFailedNote` (per row).
- [x] 3.3 `preview_screen.dart`: the effective-Decision-Model line under the
      naming line, and the per-row failure note for rows whose
      `DecisionRubric.scoringFailed` is true — never a fabricated rating.
- [x] 3.4 `job_status_screen.dart`: the same line on the cost card (both the
      regular and the `not_applicable` branch), rendered from the job the
      screen already holds.
- [x] 3.5 ARB catalogs de+en (`aiDecisionRan`, `aiDecisionSkippedNoConfig`,
      `aiDecisionClientUnavailable`, `aiDecisionScoringFailed` with an ICU
      plural, `aiDecisionSkippedNotApplicable`, `aiDecisionNotRecorded`,
      `aiDecisionModelUnnamed`, `aiPreviewScoringFailed`) + regenerated l10n.
- [x] 3.6 Version bump `0.4.0-beta.24+116 → 0.4.0-beta.25+117`.

## 4. Frontend: tests

- [x] 4.1 Unit: every outcome class in both locales, the ICU plural for
      `scoring_failed`, and the pair degradation when the wire carries only a
      provider, only a model, or neither.
- [x] 4.2 Widget: a failed row renders the failure note inside its card and no
      stars; a scored row renders stars and no note; an unscored row (no
      rubric) renders neither.
- [x] 4.3 Widget: the preview header names the outcome; a job without a
      recorded outcome renders no line.
- [x] 4.4 Widget: the job cost card renders the outcome line, and stays silent
      when the job carries none.
- [x] 4.5 Gates: `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test` (full suite), `build_runner`, `gen-l10n`.
