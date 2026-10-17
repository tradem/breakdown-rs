-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash-flex (neuralwatt)

-- Per-import AI cost transparency (issue #675).
--
-- Three pieces:
-- 1. `ai_import.ai_model_pricing` — the model pricing read model keyed
--    `(provider, model)`. All rates are non-negative BIGINT **nano-currency
--    units** ($10^-9` of the currency unit: 1_000_000_000 = 1.00 USD/EUR),
--    per 1,000,000 tokens. Seeded with `pricing_source = 'curated_seed'`
--    baseline rows for every curated assistant and image model (including
--    legacy rotated-out model IDs) so freshly booted, offline deployments
--    have deterministic pricing before the first background refresh
--    (`AiPricingRefreshWorker`). The worker UPSERTs live rows; it never
--    deletes rows a feed rotated out.
-- 2. `ai_import.projection_ai_config.cost_display_preference` — the user's
--    preferred primary cost display metric ('token' default | 'energy').
-- 3. `ai_import.ai_import_job` telemetry + cost snapshot columns:
--    `cached_tokens_in`, `energy_millijoules` (NULL when the provider
--    reports no hardware energy) and the immutable `cost` JSONB
--    `CostBreakdown` snapshot persisted at completion.

CREATE TABLE IF NOT EXISTS ai_import.ai_model_pricing (
    provider                     TEXT        NOT NULL,
    model                        TEXT        NOT NULL,
    currency                     TEXT        NOT NULL,
    input_nano_per_million       BIGINT      NOT NULL,
    output_nano_per_million      BIGINT      NOT NULL,
    cached_input_nano_per_million BIGINT,
    energy_nano_per_kwh          BIGINT,
    energy_capped_by_token       BOOLEAN     NOT NULL DEFAULT FALSE,
    image_output_nano_per_million BIGINT,
    image_nano_per_unit          BIGINT,
    pricing_source               TEXT        NOT NULL,
    price_as_of                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_ai_model_pricing PRIMARY KEY (provider, model),
    CONSTRAINT ck_ai_model_pricing_currency CHECK (currency IN ('USD', 'EUR')),
    CONSTRAINT ck_ai_model_pricing_source
        CHECK (pricing_source IN ('curated_seed', 'provider_live', 'models_dev')),
    CONSTRAINT ck_ai_model_pricing_nonnegative
        CHECK (input_nano_per_million >= 0 AND output_nano_per_million >= 0)
);

COMMENT ON TABLE ai_import.ai_model_pricing IS
    'Model pricing read model (issue #675): integer nano-currency rates per 1M tokens, seeded at curated_seed and refreshed by AiPricingRefreshWorker; never deletes rotated-out rows.';

INSERT INTO ai_import.ai_model_pricing
    (provider, model, currency, input_nano_per_million, output_nano_per_million,
     cached_input_nano_per_million, energy_nano_per_kwh, energy_capped_by_token,
     image_output_nano_per_million, image_nano_per_unit, pricing_source)
VALUES
    ('openai', 'gpt-5.6-luna', 'USD', 1250000000, 10000000000, 125000000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openai', 'gpt-5.6-terra', 'USD', 1250000000, 10000000000, 125000000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openai', 'gpt-4.1-mini', 'USD', 1250000000, 10000000000, 125000000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openai', 'gpt-image-2', 'USD', 0, 0, NULL, NULL, FALSE, NULL, 40000000, 'curated_seed'),
    ('openai', 'gpt-image-1', 'USD', 0, 0, NULL, NULL, FALSE, NULL, 40000000, 'curated_seed'),
    ('gemini', 'gemini-3.6-flash', 'USD', 750000000, 2500000000, 187500000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('gemini', 'gemini-3.5-flash-lite', 'USD', 750000000, 2500000000, 187500000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('gemini', 'gemini-3.1-pro-preview', 'USD', 750000000, 2500000000, 187500000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('gemini', 'gemini-2.5-flash', 'USD', 750000000, 2500000000, 187500000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('gemini', 'gemini-2.5-pro', 'USD', 750000000, 2500000000, 187500000, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('gemini', 'gemini-3.1-flash-image', 'USD', 0, 0, NULL, NULL, FALSE, 120000000, NULL, 'curated_seed'),
    ('gemini', 'gemini-3.1-flash-lite-image', 'USD', 0, 0, NULL, NULL, FALSE, 120000000, NULL, 'curated_seed'),
    ('gemini', 'gemini-3-pro-image', 'USD', 0, 0, NULL, NULL, FALSE, 120000000, NULL, 'curated_seed'),
    ('gemini', 'gemini-2.5-flash-image', 'USD', 0, 0, NULL, NULL, FALSE, 120000000, NULL, 'curated_seed'),
    ('openrouter', 'openai/gpt-5-mini', 'USD', 1500000000, 6000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'deepseek/deepseek-v4-flash', 'USD', 1500000000, 6000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'deepseek/deepseek-v4.1-flash', 'USD', 1500000000, 6000000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'nvidia/nemotron-3.5-lightning:free', 'USD', 0, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'nvidia/nemotron-3-nano:free', 'USD', 0, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'mistral-large-3', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'mistral-small-4', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'mistral-small-3.1', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'deepseek-v4-flash', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'deepseek-v4-pro', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'mistral-medium-3.5', 'EUR', 1800000000, 5400000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'deepseek-v4.1-flash', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'deepseek-v4-flash', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3-fast', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3-flex', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3-flash', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.3-short', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k3', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k3-fast', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k3-flex', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'qwen3.6-35b', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'qwen3.6-35b-fast', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'qwen-3.8-27b', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.2', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.2-fast', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.2-flex', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'glm-5.2-short', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k2.7-code', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k2.7-code-fast', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'kimi-k2.7-code-flex', 'USD', 1450000000, 4500000000, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'deepseek-v4-pro', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'deepseek-v4-flash', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'glm-5.2', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'glm-5.3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'kimi-k3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'kimi-k2.7-code', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'minimax-m3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'minimax-m2.7', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'mimo-v2.5', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'mimo-v2.6-pro', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'grok-4.5', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode-go', 'grok-4.6', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'deepseek-v4-pro', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'deepseek-v4-flash', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'glm-5.2', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'glm-5.3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'kimi-k3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'kimi-k2.7-code', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'minimax-m3', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'minimax-m2.7', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'mimo-v2.5', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'mimo-v2.6-pro', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'grok-4.5', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('opencode', 'grok-4.6', 'USD', 900000000, 3600000000, NULL, NULL, FALSE, NULL, NULL, 'curated_seed');
ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN cost_display_preference TEXT NOT NULL DEFAULT 'token';

COMMENT ON COLUMN ai_import.projection_ai_config.cost_display_preference IS
    'Preferred primary cost display metric (issue #675): token (default) or energy.';

ALTER TABLE ai_import.ai_import_job
    ADD COLUMN cached_tokens_in BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN energy_millijoules BIGINT,
    ADD COLUMN cost JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.cached_tokens_in IS
    'Prompt tokens served from the provider cache, accumulated across all chunks and retries (issue #675).';
COMMENT ON COLUMN ai_import.ai_import_job.energy_millijoules IS
    'Hardware energy reported by the provider (e.g. Neuralwatt), accumulated across all chunks and retries; NULL when the provider reports none.';
COMMENT ON COLUMN ai_import.ai_import_job.cost IS
    'Immutable CostBreakdown JSONB snapshot computed at completion from the telemetry and the pricing row active at that moment; never recomputed.';
