-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Reverses step 1. By the time this runs, `20260812000002`'s down migration
-- has already restored `ai_import_job_status_check` to the narrow set and
-- folded any `payload_unavailable` rows into `dead_letter`, so the leftover
-- widened constraint is simply dropped.
ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check_v2;
