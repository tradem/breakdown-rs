-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS billed_calls;
