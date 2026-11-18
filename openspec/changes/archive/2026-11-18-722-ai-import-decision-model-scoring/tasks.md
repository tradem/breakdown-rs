<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Tasks: Dedicated Decision Model configuration and best-effort scoring engine (issue #722)

## 1. Backend — Core `AiConfig`, `DecisionClient` Port & Preview Score Types

- [x] 1.1 Extend `AiConfig`, `CreateAiConfig`, `UpdateAiConfig`, `AiConfigEvent`, and `AiConfigView` with optional `decision_provider`, `decision_model`, and `decision_vault_key_id` (`#[serde(default)]`).
- [x] 1.2 Define `DecisionClient`, `DecisionQuestion` (`Noul`, `Choice`, `Score`), `DecisionAnswer`, and hybrid score computation helpers in `crates/core/src/ai/`.
- [x] 1.3 Add `scene_score`, `synopsis_score`, and `shooting_day_score` (`Option<f32>`) + rubric breakdown to `DraftScene`, `DraftShootingDay`, and `ShootingScheduleRow`; wire confidence into `SceneSource::AiExtracted` and `ShootingDaySource::AiExtracted` in `plan_scene_apply` and `ScheduleApplyWorker`.

## 2. Backend — Infra Adapter, Pricing & Non-Fatal Worker Pass

- [x] 2.1 Add `curated_decision_model_ids` and seed decision model pricing rows in `ai_model_pricing` for `Neuralwatt`, `EURouter`, and `OpenRouter`.
- [x] 2.2 Implement the HTTPS/DNS-pinned `DecisionClient` adapter for `/v1/systemone` (`Neuralwatt`) and the Decisions endpoint (`EURouter` / `OpenRouter`).
- [x] 2.3 Wire the non-fatal (best-effort) scoring pass into `ScriptImportWorker` and `ScheduleImportWorker`, accumulating decision input tokens and energy into job telemetry.
- [x] 2.4 Expose decision model catalog + API-edge credential pre-check in `crates/api`, regenerate `backend/openapi.yaml`, and regenerate `vendor/breakdown_api/`.

## 3. Verification

- [x] 3.1 Unit tests for `AiConfig` key-sharing vs. split-key validation, hybrid scoring formulas, and non-fatal degradation.
- [x] 3.2 Contract (`openapi_drift`), architecture, and wire tests green.
