-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- `curated_seed` pricing rows for the assistant/Decision catalogue rotation of
-- issue #1007 (research date 2026-11-26 UTC).
--
-- Rates are integer nano-currency units per 1,000,000 tokens (1_000_000_000 =
-- 1.00 of the currency unit), i.e. `rate × 1_000_000_000`. `pricing_source =
-- 'curated_seed'` is the same provenance every offline default uses;
-- `AiPricingRefreshWorker` may later UPSERT a `provider_live` row for the same
-- `(provider, model)`.
--
-- Scope rules (do not broaden):
--   * ONLY these 21 `(provider, model)` rows are seeded. No existing row is
--     deleted or repriced — the live pricing refresh worker owns that.
--   * A rotated-out id (`deepseek-v4-flash`, `glm-5.2`, `kimi-k3-fast`, …) keeps
--     its historical row so a persisted config and every cost snapshot made
--     from it stay resolvable.
--   * Decision Models emit no completion, so their `output_nano_per_million`
--     is 0; `eurouter/clef` and `openrouter/liquid/d1.2` therefore reuse the
--     decision billing shape of migration 20261014000001.
--   * Unknown cached-input/image rates stay NULL, `energy_capped_by_token` is
--     FALSE except for Neuralwatt, which is energy-billed with a token ceiling
--     like its existing rows.
--   * Ollama needs no hosted pricing seed (local, zero egress).
--
-- Sources, verified 2026-11-26: https://openrouter.ai/api/v1/models,
-- https://api.eurouter.ai/api/v1/models (plus `?output_modalities=decisions`),
-- https://api.neuralwatt.com/v1/models, https://opencode.ai/zen/go/v1/models,
-- https://opencode.ai/zen/v1/models, https://models.dev/api.json and the
-- official OpenAI/Gemini model docs. Anonymous first-party `/models` calls for
-- OpenAI and Gemini answer 401/403, so those three ids rest on the documented
-- prices + the models.dev feed.
INSERT INTO ai_import.ai_model_pricing
    (provider, model, currency, input_nano_per_million, output_nano_per_million,
     cached_input_nano_per_million, energy_nano_per_kwh, energy_capped_by_token,
     image_output_nano_per_million, image_nano_per_unit, pricing_source)
VALUES
    -- OpenAI (USD).
    ('openai', 'gpt-6-luna', 'USD', 100000000, 500000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openai', 'gpt-6.1-terra', 'USD', 1000000000, 5000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- Gemini (USD).
    ('gemini', 'gemini-3.8-flash', 'USD', 750000000, 3750000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- OpenRouter (USD).
    ('openrouter', 'openai/gpt-6-luna', 'USD', 100000000, 500000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- EURouter (native EUR): assistant model + the newly listed decision model.
    ('eurouter', 'deepseek-v4.1-flash-1017', 'EUR', 133600000, 534600000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'clef', 'EUR', 200000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- Neuralwatt (USD, energy-billed with a token ceiling).
    ('neuralwatt', 'deepseek-v4.1-flash-flex', 'USD', 97500000, 390000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3-flash-flex', 'USD', 97500000, 325000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k3.1-pro', 'USD', 2000000000, 10000000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k3.1-pro-flex', 'USD', 1300000000, 6500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'qwen3.6-35b-flex', 'USD', 188500000, 747500000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'qwen-3.8-27b-flex', 'USD', 292500000, 2080000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    -- OpenCode Go gateway (USD).
    ('opencode-go', 'deepseek-v4.1-flash', 'USD', 150000000, 600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'glm-5.3-flash', 'USD', 150000000, 500000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'kimi-k3.1-pro', 'USD', 2000000000, 10000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'grok-4.7', 'USD', 2000000000, 6000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- OpenCode (USD) — the direct gateway prices differ from the Go reseller.
    ('opencode', 'deepseek-v4.1-flash', 'USD', 120000000, 480000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'glm-5.3-flash', 'USD', 150000000, 500000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'kimi-k3.1-pro', 'USD', 2000000000, 10000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'grok-4.7', 'USD', 2000000000, 6000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- OpenRouter decision model (USD, zero output tokens).
    ('openrouter', 'liquid/d1.2', 'USD', 20000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed')
ON CONFLICT (provider, model) DO NOTHING;
