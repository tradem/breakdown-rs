-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash-flex (neuralwatt)

-- Revert per-import AI cost transparency (issue #675).
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS cost,
    DROP COLUMN IF EXISTS energy_millijoules,
    DROP COLUMN IF EXISTS cached_tokens_in;

ALTER TABLE ai_import.projection_ai_config
    DROP COLUMN IF EXISTS cost_display_preference;

DROP TABLE IF EXISTS ai_import.ai_model_pricing;
