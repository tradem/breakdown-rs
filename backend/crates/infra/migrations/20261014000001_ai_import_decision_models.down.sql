-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

DELETE FROM ai_import.ai_model_pricing
WHERE pricing_source = 'curated_seed'
  AND output_nano_per_million = 0
  AND model IN ('clef-flash', 'clef', 'metis', 'cloudflare/clef-flash',
                'cloudflare/clef', 'typesafe/jev-1.14',
                'perplexity/pplx-decider-flash-v1.2', 'liquid/d1');

ALTER TABLE ai_import.projection_ai_config
    DROP COLUMN IF EXISTS decision_provider,
    DROP COLUMN IF EXISTS decision_model,
    DROP COLUMN IF EXISTS decision_vault_key_id;
