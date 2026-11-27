-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Remove ONLY the rows this migration introduced (issue #1007). Rotated-out
-- ids such as `deepseek-v4-flash`, `glm-5.2` or `liquid/d1` are pre-existing
-- historical rows and must survive a down migration, so the delete is pinned to
-- the exact `(provider, model)` list of the up migration.
DELETE FROM ai_import.ai_model_pricing
WHERE pricing_source = 'curated_seed'
  AND (
        (provider = 'openai'
            AND model IN ('gpt-6-luna', 'gpt-6.1-terra'))
     OR (provider = 'gemini'
            AND model IN ('gemini-3.8-flash'))
     OR (provider = 'openrouter'
            AND model IN ('openai/gpt-6-luna', 'liquid/d1.2'))
     OR (provider = 'eurouter'
            AND model IN ('deepseek-v4.1-flash-1017', 'clef'))
     OR (provider = 'neuralwatt'
            AND model IN ('deepseek-v4.1-flash-flex', 'glm-5.3-flash-flex',
                          'kimi-k3.1-pro', 'kimi-k3.1-pro-flex',
                          'qwen3.6-35b-flex', 'qwen-3.8-27b-flex'))
     OR (provider = 'opencode-go'
            AND model IN ('deepseek-v4.1-flash', 'glm-5.3-flash',
                          'kimi-k3.1-pro', 'grok-4.7'))
     OR (provider = 'opencode'
            AND model IN ('deepseek-v4.1-flash', 'glm-5.3-flash',
                          'kimi-k3.1-pro', 'grok-4.7'))
  );
