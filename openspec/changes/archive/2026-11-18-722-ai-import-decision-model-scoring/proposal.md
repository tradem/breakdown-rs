<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## Why

Issue #722 (depends on #721): Reviewers inspecting AI-imported screenplays and shooting schedules need calibrated quality scores for extracted **scenes**, **TL;DR synopses (`summary`)**, and **shooting days** — both to focus human review on uncertain extractions today and to build the structured reward signal needed for automatic prompt optimization (APO) in `0.5.x`.

Asking a generative extraction LLM to output self-confidence in JSON produces uncalibrated verbal overconfidence. Non-autoregressive **System One Decision Models** (`clef-flash`, `clef`, `jev`, `metis`), trained with Brier loss and RLCD, evaluate an input `state` against typed `questions` (`noul`, `choice`, `score`) in a single forward pass (~39 ms median latency, zero output tokens) and return mathematically calibrated probability distributions. Three curated providers in `breakdown-rs` natively host these models:
- **Neuralwatt** (`POST /v1/systemone`): `clef-flash` (preview), `clef` (energy-billed + token ceiling, $0 output).
- **EURouter** (`?output_modalities=decisions`): `clef-flash` (€0.042/1M input), `metis` (€0.12/1M input), €0 output, native EUR.
- **OpenRouter** (`POST /api/alpha/decisions`, `?output_modalities=decisions`): `cloudflare/clef-flash`, `cloudflare/clef`, `typesafe/jev-1.14`, `perplexity/pplx-decider-flash-v1.2`, `liquid/d1`, etc., $0 output.

## What Changes

- `core` (`crates/core/src/ai/`):
  - Extend `AiConfig`, `CreateAiConfig`, `UpdateAiConfig`, `AiConfigEvent`, and `AiConfigView` additively (`#[serde(default)]`) with an optional, separate Decision Model configuration:
    - `decision_provider: Option<LlmProvider>`
    - `decision_model: Option<String>`
    - `decision_vault_key_id: Option<String>`
  - Permit `decision_vault_key_id == Some(vault_key_id)` when `decision_provider == Some(provider)` (same-key reuse) OR a separate active `Settings` credential bound to `decision_provider` (enabling separate billing/cost tracking).
  - Define the `DecisionClient` port and typed question/answer primitives (`Noul`, `Choice`, `Score`, `DecisionCallOutcome`).
  - Extend `DraftScene`, `DraftShootingDay`, and `ShootingScheduleRow` additively (`#[serde(default)]`) with `scene_score: Option<f32>`, `synopsis_score: Option<f32>`, `shooting_day_score: Option<f32>` (normalized `0.0..=1.0`), plus structured rubric sub-scores for `0.5.x` prompt optimization.
  - Thread `scene_score` into `SceneSource::AiExtracted.confidence` and `shooting_day_score` into `ShootingDaySource::AiExtracted.confidence` during apply planning.
- `infra` (`crates/infra/src/ai/`):
  - Curated decision model catalog (`curated_decision_model_ids`) and pricing seed migration for `Neuralwatt`, `EURouter`, and `OpenRouter`.
  - `DecisionClient` HTTP adapter enforcing ADR-024 / issue #170 transport guards (HTTPS-only, DNS-rebinding pin, descriptive `User-Agent`).
  - **Non-fatal (best-effort) scoring pass** in `ScriptImportWorker` and `ScheduleImportWorker`: evaluates scene, synopsis, and shooting-day questions in one forward pass per chunk/schedule, combining them with deterministic server-side grounding signals (`verify_draft_costumes`, `sanitize_meta_summary`, heading/marker match). Any decision-endpoint failure after bounded retry logs a warning and leaves scores as `None` without failing the import job.
- `api`:
  - Expose curated decision models per provider and validate `decision_vault_key_id` ownership/provider binding at the API edge (mirroring #528/#552).
  - Regenerate `backend/openapi.yaml` and `vendor/breakdown_api/`.

## Impact

- **Reliability:** The decision pass is strictly non-fatal (best-effort); a transient outage on a preview decision endpoint never discards a completed extraction.
- **CQRS & Security:** Vault key ownership and provider-binding pre-checks stay at the API edge; no secret material enters `AiConfig`.
- **Affected specs:** `specs/ai-import/spec.md`.
