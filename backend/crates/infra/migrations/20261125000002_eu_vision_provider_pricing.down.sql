-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

DELETE FROM ai_import.ai_model_pricing
WHERE pricing_source = 'curated_seed'
  AND (
        (provider = 'scaleway'
            AND model IN ('qwen3.5-397b-a17b', 'mistral-small-3.2-24b-instruct-2506'))
     OR (provider = 'ovhcloud'
            AND model IN ('qwen3-vl-30b-a3b', 'Mistral-Small-3.2-24B-Instruct-2506'))
     OR (provider = 'nebius'
            AND model IN ('Qwen/Qwen3.8-27B', 'deepseek-ai/DeepSeek-V4.1-Flash-1017'))
  );
