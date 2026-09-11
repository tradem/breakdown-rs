-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Durable poison-event dead-letter table for projectors (issue #37).
--
-- When the kameo_es PostgresProcessor exhausts its retry budget on one event
-- and classifies the error as *permanent* (SQLSTATE class 23 integrity
-- constraint / 22 data exception, or an event deserialization failure), it
-- records the event here and advances the projector's checkpoint in
-- `sierradb_event_checkpoints` past it — atomically, in one transaction — so
-- the projector keeps progressing instead of restart-looping forever.
--
-- Row identity `(projection_id, partition_id, sequence)` is the same
-- coordinates as the checkpoint table; the upsert from the projector bumps
-- `attempts` / `last_seen_at` on replay instead of duplicating.

CREATE TABLE IF NOT EXISTS projection_dead_letter (
    projection_id TEXT NOT NULL,
    partition_id SMALLINT NOT NULL,
    sequence BIGINT NOT NULL,
    stream_id TEXT NOT NULL,
    event_name TEXT NOT NULL,
    sqlstate TEXT,
    constraint_name TEXT,
    error_message TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 1,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (projection_id, partition_id, sequence)
);

-- Column order matches ProjectorHealthRepository::list_dead_letters
-- (`ORDER BY last_seen_at DESC, projection_id, partition_id, sequence LIMIT`)
-- so the sort+limit is served from the index without a separate sort step.
CREATE INDEX IF NOT EXISTS idx_projection_dead_letter_recent
    ON projection_dead_letter(last_seen_at DESC, projection_id, partition_id, sequence);
