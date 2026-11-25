-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Curated `curated_seed` pricing rows for the EU vision fallbacks of issue
-- #968 (ADR-041 `D2`), so `compute_cost_snapshot` (#675/#794) prices the
-- page-streaming schedule calls of every provider, not just EURouter.
--
-- Rates are integer nano-currency units per 1,000,000 tokens (1_000_000_000 =
-- 1.00 of the currency unit). `pricing_source = 'curated_seed'` is the same
-- provenance every offline default uses; `AiPricingRefreshWorker` may later
-- UPSERT a `provider_live` row for the same `(provider, model)`.
--
-- A model WITHOUT a row stays honest absence (`CostStatus::Unknown`, never a
-- zero-cost snapshot) — this table is therefore an improvement, not a
-- prerequisite for the providers to work.
--
-- Sources, verified 2026-11-25:
--   * scaleway  — Scaleway Generative APIs price list (EUR). The same figures
--                 are what models.dev publishes for `scaleway` converted at its
--                 USD rate, so both feeds agree.
--   * ovhcloud  — the LIVE `GET https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/models`
--                 response (`pricing.prompt` / `pricing.completion`, USD).
--   * nebius    — models.dev `nebius` feed (USD); Token Factory publishes no
--                 public price list without an account.
INSERT INTO ai_import.ai_model_pricing
    (provider, model, currency, input_nano_per_million, output_nano_per_million,
     cached_input_nano_per_million, energy_nano_per_kwh, energy_capped_by_token,
     image_output_nano_per_million, image_nano_per_unit, pricing_source)
VALUES
    -- Scaleway Generative APIs (Paris, France) — EUR.
    ('scaleway', 'qwen3.5-397b-a17b', 'EUR', 600000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('scaleway', 'mistral-small-3.2-24b-instruct-2506', 'EUR', 150000000, 350000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- OVHcloud AI Endpoints (EU) — USD, from the provider's own model feed.
    ('ovhcloud', 'qwen3-vl-30b-a3b', 'USD', 150000000, 580000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('ovhcloud', 'Mistral-Small-3.2-24B-Instruct-2506', 'USD', 100000000, 310000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- Nebius Token Factory (EU) — USD.
    ('nebius', 'Qwen/Qwen3.8-27B', 'USD', 450000000, 3000000000, 100000000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('nebius', 'deepseek-ai/DeepSeek-V4.1-Flash-1017', 'USD', 300000000, 1200000000, 6000000, NULL, FALSE, NULL, NULL, 'curated_seed')
ON CONFLICT (provider, model) DO NOTHING;
