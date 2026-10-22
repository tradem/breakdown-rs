-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Dedicated Decision Model configuration and best-effort scoring (issue #722).
--
-- 1. `ai_import.projection_ai_config.decision_*` — the optional Decision
--    Model slot (`decision_provider`, `decision_model`,
--    `decision_vault_key_id`). All three are nullable; a row with all three
--    NULL behaves exactly like a pre-#722 configuration (no scoring pass).
-- 2. `ai_import.ai_model_pricing` — curated_seed rows for every curated
--    decision model. Decision models emit ZERO output tokens (single
--    non-autoregressive forward pass), so `output_nano_per_million` is 0.
--    Neuralwatt decision models are energy-billed with a token ceiling
--    (`energy_capped_by_token`), EURouter/OpenRouter bill input only.

ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN IF NOT EXISTS decision_provider TEXT,
    ADD COLUMN IF NOT EXISTS decision_model TEXT,
    ADD COLUMN IF NOT EXISTS decision_vault_key_id TEXT;

COMMENT ON COLUMN ai_import.projection_ai_config.decision_provider IS
    'Optional Decision Model host (issue #722): neuralwatt | eurouter | openrouter. NULL = no scoring pass.';
COMMENT ON COLUMN ai_import.projection_ai_config.decision_model IS
    'Curated decision model ID (issue #722), e.g. clef-flash / clef / metis / cloudflare/clef-flash.';
COMMENT ON COLUMN ai_import.projection_ai_config.decision_vault_key_id IS
    'Vault key of the decision provider credential (issue #722): may equal vault_key_id (same-key reuse) or reference a distinct owned credential (split billing).';

INSERT INTO ai_import.ai_model_pricing
    (provider, model, currency, input_nano_per_million, output_nano_per_million,
     cached_input_nano_per_million, energy_nano_per_kwh, energy_capped_by_token,
     image_output_nano_per_million, image_nano_per_unit, pricing_source)
VALUES
    -- Neuralwatt: energy-billed with a token ceiling, $0 output.
    ('neuralwatt', 'clef-flash', 'USD', 40000000, 0, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    ('neuralwatt', 'clef', 'USD', 42000000, 0, NULL, 10000000000, TRUE, NULL, NULL, 'curated_seed'),
    -- EURouter: native EUR, €0 output.
    ('eurouter', 'clef-flash', 'EUR', 42000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('eurouter', 'metis', 'EUR', 120000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    -- OpenRouter: $0 output.
    ('openrouter', 'cloudflare/clef-flash', 'USD', 38000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'cloudflare/clef', 'USD', 42000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'typesafe/jev-1.14', 'USD', 42000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'perplexity/pplx-decider-flash-v1.2', 'USD', 10000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed'),
    ('openrouter', 'liquid/d1', 'USD', 38000000, 0, NULL, NULL, FALSE, NULL, NULL, 'curated_seed')
ON CONFLICT (provider, model) DO NOTHING;
