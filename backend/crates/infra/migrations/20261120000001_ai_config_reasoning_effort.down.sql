-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

ALTER TABLE ai_import.projection_ai_config
    DROP COLUMN IF EXISTS reasoning_effort;
