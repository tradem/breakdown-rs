-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

ALTER TABLE ai_import.projection_ai_config
    DROP COLUMN IF EXISTS vision_zdr_attested,
    DROP COLUMN IF EXISTS vision_vault_key_id,
    DROP COLUMN IF EXISTS vision_model,
    DROP COLUMN IF EXISTS vision_provider;
