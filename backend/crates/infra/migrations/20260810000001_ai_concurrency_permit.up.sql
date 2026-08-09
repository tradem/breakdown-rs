-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #178: cancellation-safe AI concurrency permits.
--
-- The previous model was an anonymous counter
-- (`ai_import.concurrency_counter.in_flight`): acquisition incremented it and
-- `PgAiConcurrencyPermit::release()` decremented it. An increment therefore
-- had no owner, so a worker task that was cancelled between acquire and
-- release (shutdown drops the future without awaiting `release()`) left the
-- counter permanently raised — capacity was lost until an operator repaired
-- the row by hand.
--
-- One row per in-flight permit makes every unit of capacity owned and
-- therefore reclaimable:
--   * `id`          — the permit handle; release is an idempotent DELETE by id.
--   * `user_id`     — per-user ceiling (COUNT over live rows).
--   * `worker_id`   — diagnostics: who holds the slot.
--   * `expires_at`  — lease deadline. A permit whose holder died without
--                     releasing (process kill, runtime teardown) is reclaimed
--                     by the next acquisition, which deletes expired rows
--                     before counting. Long-running holders renew the lease.
CREATE TABLE ai_import.concurrency_permit (
    id          UUID PRIMARY KEY,
    user_id     TEXT NOT NULL,
    worker_id   TEXT NOT NULL DEFAULT '',
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);

-- Reclaim sweep at acquisition time: `DELETE ... WHERE expires_at <= now()`.
CREATE INDEX idx_ai_concurrency_permit_expiry
    ON ai_import.concurrency_permit (expires_at);

-- Per-user ceiling check.
CREATE INDEX idx_ai_concurrency_permit_user
    ON ai_import.concurrency_permit (user_id);

COMMENT ON TABLE ai_import.concurrency_permit IS
    'One row per in-flight AI import permit; expired rows are reclaimed on the next acquisition.';
COMMENT ON COLUMN ai_import.concurrency_permit.expires_at IS
    'Lease deadline; a permit past this timestamp is reclaimable by any acquirer.';

-- The anonymous counter is superseded. Leaving it would keep a second,
-- silently drifting source of truth for the same ceiling.
DROP TABLE IF EXISTS ai_import.concurrency_counter;
