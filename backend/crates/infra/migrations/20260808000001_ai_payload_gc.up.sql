-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: pi-agent (pi-coding-agent)

-- AI payload garbage collection run history.
CREATE TABLE ai_import.projection_ai_payload_gc_run (
    run_id              UUID PRIMARY KEY,
    started_at          TIMESTAMPTZ NOT NULL,
    finished_at         TIMESTAMPTZ NOT NULL,
    scanned             BIGINT NOT NULL DEFAULT 0,
    source_deleted      BIGINT NOT NULL DEFAULT 0,
    preview_deleted     BIGINT NOT NULL DEFAULT 0,
    errors              BIGINT NOT NULL DEFAULT 0,
    dry_run             BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_ai_payload_gc_run_started
    ON ai_import.projection_ai_payload_gc_run (started_at);
