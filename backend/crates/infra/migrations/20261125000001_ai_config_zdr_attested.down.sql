-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

ALTER TABLE ai_import.projection_ai_config
    DROP COLUMN IF EXISTS zdr_attested;
