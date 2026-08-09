-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Restore the anonymous counter from 20260802000001_ai_import.up.sql.
CREATE TABLE IF NOT EXISTS ai_import.concurrency_counter (
    scope               TEXT NOT NULL,
    user_id             TEXT NOT NULL DEFAULT '',
    in_flight           INT NOT NULL DEFAULT 0 CHECK (in_flight >= 0),
    PRIMARY KEY (scope, user_id)
);

INSERT INTO ai_import.concurrency_counter (scope, user_id, in_flight)
VALUES ('global', '', 0)
ON CONFLICT (scope, user_id) DO NOTHING;

DROP TABLE IF EXISTS ai_import.concurrency_permit;
