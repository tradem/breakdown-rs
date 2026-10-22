<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — 722 AI Import: Dedicated Decision Model Configuration and Best-Effort Scoring Engine

## Decisions

### D1 — Separate Decision Model slot on `AiConfig` with same-key or split-key support
`AiConfig` gains optional `decision_provider: Option<LlmProvider>`, `decision_model: Option<String>`, and `decision_vault_key_id: Option<String>` (`#[serde(default)]`).
- Supported decision providers: `Neuralwatt`, `EURouter`, `OpenRouter`.
- When `decision_provider == Some(provider)`, `decision_vault_key_id` may either equal `vault_key_id` (shared API key) or point to a distinct active `Settings` credential owned by the caller for the same provider (split billing).
- When `decision_provider != Some(provider)`, the API edge verifies that `decision_vault_key_id` is an active credential bound to `decision_provider` and owned by the caller.

### D2 — `DecisionClient` port and provider routing
`DecisionClient` in `core::ai::ports` accepts a `DecisionRequest` (`provider`, `model`, `state`, `questions: BTreeMap<String, DecisionQuestion>`) and returns calibrated probabilities/expected scores (`DecisionCallOutcome`) plus `LlmCallUsage` (input tokens and millijoules energy; completion tokens are 0).
- `Neuralwatt` routes to `POST https://api.neuralwatt.com/v1/systemone` (`curated_decision_model_ids`: `clef-flash`, `clef`).
- `EURouter` routes to its Decisions endpoint (`curated_decision_model_ids`: `clef-flash`, `metis`, priced in EUR).
- `OpenRouter` routes to `POST https://openrouter.ai/api/alpha/decisions` (`curated_decision_model_ids`: `cloudflare/clef-flash`, `cloudflare/clef`, `typesafe/jev-1.14`, `perplexity/pplx-decider-flash-v1.2`, `liquid/d1`).

### D3 — Non-fatal (best-effort) single-pass hybrid scoring & 0.5.x APO foundation
In `ScriptImportWorker` and `ScheduleImportWorker`:
- All questions for a chunk/schedule (`scene_score`, `synopsis_score`, `shooting_day_score` + sub-questions) execute in **one** non-autoregressive forward pass.
- Scores combine calibrated Decision Model probabilities with deterministic server-side grounding signals (`verify_draft_costumes`, `sanitize_meta_summary`, deterministic heading/marker extraction).
- Any failure of the decision call after bounded retry logs a `tracing::warn!` and degrades scores to `None` — the extraction job never fails due to a decision-model outage.
- Sub-question probabilities are retained in preview/telemetry metadata to serve as the structured reward signal for `0.5.x` automatic prompt optimization.
