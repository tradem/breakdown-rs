-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (neuralwatt)

-- The stable problem `code` of the failure that ended an attempt (issue #639).
--
-- `error_summary` is free-form `DomainError::to_string()` text; a client
-- cannot branch on it without parsing log wording (frontend-flutter/AGENTS.md
-- §5). Storing the registered code (ADR-031 D2) alongside the summary lets the
-- job-status screen localize the reason from its ARB catalogs, keyed on
-- identity rather than prose. NULL for writers that recorded no typed error.
ALTER TABLE ai_import.ai_import_job_attempt
    ADD COLUMN error_code TEXT;

COMMENT ON COLUMN ai_import.ai_import_job_attempt.error_code IS
    'Stable problem code (ADR-031 D2) of the failure; NULL when unclassified.';
