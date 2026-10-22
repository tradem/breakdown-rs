<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Dedicated Decision Model configuration and credential binding
`AiConfig` SHALL support an optional Decision Model configuration (`decision_provider`, `decision_model`, `decision_vault_key_id`) independent of the generative assistant model. Curated decision models SHALL be exposed for `Neuralwatt` (`clef-flash`, `clef`), `EURouter` (`clef-flash`, `metis`), and `OpenRouter` (`cloudflare/clef-flash`, `cloudflare/clef`, `typesafe/jev-1.14`, `perplexity/pplx-decider-flash-v1.2`, `liquid/d1`). When `decision_provider` matches the extraction `provider`, `decision_vault_key_id` MAY reuse `vault_key_id` or bind a separate active `Settings` credential owned by the caller for split billing; when `decision_provider` differs, the API edge SHALL pre-check that `decision_vault_key_id` is an active credential of `decision_provider` owned by the caller.

#### Scenario: Same-provider decision model reuses extraction vault key
- **WHEN** a user configures `provider = neuralwatt`, `decision_provider = Some(neuralwatt)`, `decision_model = Some("clef-flash")`, and `decision_vault_key_id = Some(vault_key_id)`
- **THEN** `AiConfig` accepts and persists the configuration

#### Scenario: Separate billing key for decision model is validated at API edge
- **WHEN** a user supplies a distinct `decision_vault_key_id` for `decision_provider`
- **THEN** the API handler verifies the key is active, owned by the caller, and bound to `decision_provider` before dispatching the command

### Requirement: Non-fatal hybrid scoring for scenes, TL;DR synopses, and shooting days
When a Decision Model is configured, `ScriptImportWorker` and `ScheduleImportWorker` SHALL evaluate each extracted chunk/schedule in a single forward pass via `DecisionClient` combined with deterministic grounding signals to populate `scene_score`, `synopsis_score`, and `shooting_day_score` (`Option<f32>` in `0.0..=1.0`). If no Decision Model is configured or if the decision request fails after bounded retry, the import job SHALL still succeed with the score fields set to `None`. Applying a scored preview SHALL record `scene_score` on `SceneSource::AiExtracted.confidence` and `shooting_day_score` on `ShootingDaySource::AiExtracted.confidence`.

#### Scenario: Decision endpoint outage does not fail script import
- **WHEN** script extraction succeeds for all chunks but the Decision Model endpoint returns 503
- **THEN** `ScriptImportWorker` stores the preview with `scene_score = None`, `synopsis_score = None`, `shooting_day_score = None` and marks the job `Succeeded`
