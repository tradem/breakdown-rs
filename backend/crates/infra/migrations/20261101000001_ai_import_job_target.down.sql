-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Revert issue #771: drop the import-target snapshot columns.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS target_season_id,
    DROP COLUMN IF EXISTS target_season_number,
    DROP COLUMN IF EXISTS target_block_number;
