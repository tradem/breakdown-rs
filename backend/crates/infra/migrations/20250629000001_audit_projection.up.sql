-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Generic audit / journal projection (CQRS read model). v1 captures the
-- `membership` Bounded Context's events; the schema is intentionally generic
-- (`entity_type` + `payload` JSONB + a nullable `series_id` tenant dimension)
-- so events from other Bounded Contexts can be appended later without a
-- breaking migration.
--
-- Idempotency under redelivery (ADR-016): SierraDB assigns a fresh `event.id`
-- on every append, so re-delivering the same logical event yields a *new*
-- `event.id`. We therefore cannot rely on `event.id` for deduplication.
-- Instead, `event_key` is a deterministic content key (entity_type +
-- entity_id + event_type + payload) that is identical for a redelivered event,
-- and `ON CONFLICT (event_key) DO NOTHING` makes redelivery safe (no duplicate
-- rows). `id` remains the per-event row identifier.

CREATE TABLE IF NOT EXISTS projection_audit (
    id           UUID PRIMARY KEY,
    event_key    TEXT NOT NULL UNIQUE,
    entity_type  TEXT NOT NULL,
    entity_id    TEXT NOT NULL,
    event_type   TEXT NOT NULL,
    block_id     UUID,
    series_id    UUID,
    actor        TEXT,
    payload      JSONB NOT NULL,
    occurred_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_audit_block ON projection_audit (block_id);
CREATE INDEX IF NOT EXISTS idx_projection_audit_actor ON projection_audit (actor);
CREATE INDEX IF NOT EXISTS idx_projection_audit_series ON projection_audit (series_id);
CREATE INDEX IF NOT EXISTS idx_projection_audit_entity ON projection_audit (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_projection_audit_occurred ON projection_audit (occurred_at);
