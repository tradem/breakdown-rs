-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
--
-- Dedicated report-archival job schema (change: add-report-archival-backup).
--
-- SSOT / EventStorming guardrail (design D2):
--   * This schema holds ONLY operational state (that a backup was requested,
--     where bytes were staged, whether the provider accepted them).
--   * It is NOT a source of business truth.
--   * It shadows/duplicates/supersedes no event, aggregate, or projection.
--   * No domain query path reads from it.
--   * FK to projection_shooting_day is for referential integrity only;
--     this migration never WRITES to business projection tables.

CREATE SCHEMA IF NOT EXISTS report_ops;

CREATE TABLE report_ops.report_job (
    id                  UUID PRIMARY KEY,
    -- Deterministic dedup key:
    --   {kind}|{shooting_day_id}|{snapshot_identity}|{locale}|{template_version}
    dedup_key           TEXT NOT NULL,
    kind                TEXT NOT NULL,
    shooting_day_id     UUID NOT NULL,
    locale              TEXT NOT NULL,
    template_version    TEXT NOT NULL,
    snapshot_identity   TEXT NOT NULL,
    -- Trigger provenance (audit only; NOT part of dedup_key).
    trigger_source      TEXT NOT NULL,
    -- Staged object handle (adapter key) + content digest (hex SHA-256).
    staged_handle       TEXT,
    content_digest      TEXT,
    -- External provider outcome.
    provider_object_id  TEXT,
    provider_etag       TEXT,
    provider_recorded_at TIMESTAMPTZ,
    -- Retry / lifecycle.
    retries             INT  NOT NULL DEFAULT 0,
    max_retries         INT  NOT NULL DEFAULT 5,
    status              TEXT NOT NULL,
    -- Short, non-sensitive last error summary (never bytes/credentials).
    last_error          TEXT,
    claimed_at          TIMESTAMPTZ,
    claimed_by          TEXT,
    next_attempt_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT report_job_dedup_key_unique UNIQUE (dedup_key),
    -- Integrity-only FK to the read-model shooting day. No cascade-write of
    -- business facts; ON DELETE RESTRICT so jobs outlive accidental deletes
    -- only when the day still exists (operator cleans jobs first).
    CONSTRAINT report_job_shooting_day_fk
        FOREIGN KEY (shooting_day_id)
        REFERENCES projection_shooting_day (id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_report_job_status_next_attempt
    ON report_ops.report_job (status, next_attempt_at);

CREATE INDEX idx_report_job_shooting_day
    ON report_ops.report_job (shooting_day_id);

-- Claim helper: workers SELECT … FOR UPDATE SKIP LOCKED against pending/failed.
COMMENT ON TABLE report_ops.report_job IS
    'Operational report-archival jobs. NOT business truth; no domain query reads this.';
