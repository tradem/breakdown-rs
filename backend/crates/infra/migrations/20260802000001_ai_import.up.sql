-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: gpt-5.6-luna (opencode-go)

-- Operational AI import state. This is not event-sourced business truth.
CREATE SCHEMA IF NOT EXISTS ai_import;

CREATE TABLE ai_import.ai_import_job (
    id                  UUID PRIMARY KEY,
    user_id             TEXT NOT NULL,
    document_kind       TEXT NOT NULL CHECK (document_kind IN ('script', 'schedule')),
    block_id            UUID,
    dedup_key           TEXT NOT NULL,
    document_digest     TEXT NOT NULL,
    source_handle       TEXT NOT NULL,
    preview_handle      TEXT,
    status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'dead_letter')),
    retries             INT NOT NULL DEFAULT 0 CHECK (retries >= 0),
    max_retries         INT NOT NULL DEFAULT 5 CHECK (max_retries >= 0),
    last_error          TEXT,
    next_attempt_at     TIMESTAMPTZ,
    provider            TEXT,
    model               TEXT,
    chunk_count         INT NOT NULL DEFAULT 0,
    tokens_in           BIGINT NOT NULL DEFAULT 0,
    tokens_out          BIGINT NOT NULL DEFAULT 0,
    latency_total_ms    BIGINT NOT NULL DEFAULT 0,
    accept_as_is        BOOLEAN,
    edit_distance       INT NOT NULL DEFAULT 0 CHECK (edit_distance >= 0),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ai_import_job_user_dedup_unique UNIQUE (user_id, dedup_key)
);

CREATE INDEX idx_ai_import_job_claim
    ON ai_import.ai_import_job (status, next_attempt_at, created_at);

CREATE INDEX idx_ai_import_job_block
    ON ai_import.ai_import_job (block_id);

CREATE TABLE ai_import.projection_ai_config (
    id                  UUID PRIMARY KEY,
    user_id             TEXT NOT NULL,
    provider            TEXT NOT NULL,
    assistant_model     TEXT NOT NULL,
    image_model         TEXT,
    prompts             JSONB NOT NULL DEFAULT '{}'::jsonb,
    vault_key_id        TEXT NOT NULL,
    revoked             BOOLEAN NOT NULL DEFAULT FALSE,
    version             BIGINT NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_projection_ai_config_user
    ON ai_import.projection_ai_config (user_id);

CREATE TABLE ai_import.concurrency_counter (
    scope               TEXT NOT NULL,
    user_id             TEXT NOT NULL DEFAULT '',
    in_flight           INT NOT NULL DEFAULT 0 CHECK (in_flight >= 0),
    PRIMARY KEY (scope, user_id)
);

INSERT INTO ai_import.concurrency_counter (scope, user_id, in_flight)
VALUES ('global', '', 0)
ON CONFLICT (scope, user_id) DO NOTHING;

CREATE TABLE ai_import.projection_ai_import_mapping (
    preview_id          UUID NOT NULL,
    draft_ref           TEXT NOT NULL,
    aggregate_kind      TEXT NOT NULL,
    aggregate_id        UUID NOT NULL,
    aggregate_version   BIGINT NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (preview_id, draft_ref)
);

COMMENT ON TABLE ai_import.ai_import_job IS
    'Operational AI import jobs; never a source of business truth.';
COMMENT ON TABLE ai_import.projection_ai_import_mapping IS
    'Idempotency mapping for reviewed AI preview rows.';
