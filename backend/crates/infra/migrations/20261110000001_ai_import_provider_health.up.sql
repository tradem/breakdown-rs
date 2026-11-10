-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Provider circuit breaker + held jobs (issue #871, workstream A; design D-A2,
-- D-A2b, D-A4, D-A6).
--
-- The durable breaker state lives in Postgres rather than in an in-process
-- `watch` channel for three reasons, all of which the table's shape serves:
--
--   1. the filter must happen ATOMICALLY with the claim (`FOR UPDATE SKIP
--      LOCKED` already picks the row; a second in-process check is a TOCTOU),
--      and that is a SQL predicate;
--   2. a multi-replica deployment would otherwise keep N independent verdicts,
--      so replica B keeps paying for an outage replica A already proved;
--   3. a restart forgets an in-process verdict — exactly the cold-start moment
--      that re-pays the first failure. The permit and the lease are durable for
--      the same reason; the SSE hub is in-process because a lost wake-up is
--      harmless (the poll recovers it). A lost breaker verdict is not.
CREATE TABLE ai_import.provider_health (
    provider              TEXT        NOT NULL,
    model                 TEXT        NOT NULL,
    -- Three values only: `expired` is a *job-hold* state (D-C4) and never a
    -- breaker state, so this CHECK rejects it.
    state                 TEXT        NOT NULL DEFAULT 'closed'
                          CHECK (state IN ('closed', 'open', 'half_open')),
    consecutive_failures  INTEGER     NOT NULL DEFAULT 0
                          CHECK (consecutive_failures >= 0),
    opened_at             TIMESTAMPTZ,
    -- The probe schedule. NOT a claim gate: only `state = 'closed'` admits a
    -- claim, because lifting the filter when the probe became due would drain
    -- the queue instead of running one probe (D-A2).
    retry_at              TIMESTAMPTZ,
    -- Operator readability only; the fence is `probe_lease_id` below.
    probe_owner           TEXT,
    probe_started_at      TIMESTAMPTZ,
    -- Escalates the OPEN window, incremented on `closed -> open` only (a
    -- `half_open -> open` is the same outage still failing to clear).
    flap_count            INTEGER     NOT NULL DEFAULT 0
                          CHECK (flap_count >= 0),
    last_failure_at       TIMESTAMPTZ,
    -- When the breaker last closed: the stable-window test on the next
    -- `closed -> open` reads it, so a flap is counted where a new outage
    -- starts and a genuinely stable provider resets its punishment.
    closed_at             TIMESTAMPTZ,
    -- Fence of the CURRENT probe lease: a fresh UUIDv7 per probe attempt.
    -- `probe_owner` alone is not unique — the same worker can reacquire the
    -- lease, and a stale result would then pass an owner check.
    probe_lease_id        UUID,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, model)
);

COMMENT ON TABLE ai_import.provider_health IS
    'Provider circuit breaker keyed by the resolved (provider, model) pair (issue #871). Only `closed` admits a claim; only the probe task ends a non-closed state.';

-- The probe task selects `state <> 'closed' AND retry_at <= now()`; the sweeper
-- selects the same set. One partial index keeps both off a sequential scan
-- without indexing the (many, always-closed) healthy pairs.
CREATE INDEX idx_ai_import_provider_health_probe
    ON ai_import.provider_health (retry_at)
    WHERE state <> 'closed';

-- The breaker key snapshot (D-A2b), filled at the API edge from the user's
-- active AI config — the same edge that resolves the #771 target snapshot.
-- NULL for every pre-#871 row and for an upload whose config could not be
-- resolved; such a job is simply never breaker-filtered, which is the honest
-- degradation (there is nothing to compare a breaker against).
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN provider TEXT,
    ADD COLUMN model    TEXT;

-- The wire view's column (D-A4): `{provider, model, reason_code, state, until,
-- hold_deadline, chunks_done}`. Cleared by every other lifecycle write, kept
-- with `state = 'expired'` by the hold-expiry write — that marker is the only
-- durable signal separating an expiry from a spent retry budget.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN provider_hold JSONB;

-- The hold SERIES clock (D-C4), deliberately its own column: `provider_hold` is
-- cleared on every breaker close, so a deadline stored inside it would restart
-- at 6 h on each short recovery and a flapping provider could never expire.
-- `COALESCE`d on every hold write, cleared on claim and by the terminal writes.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN provider_hold_series_started_at TIMESTAMPTZ;

COMMENT ON COLUMN ai_import.ai_import_job.provider_hold IS
    'Why this job waits on its provider (issue #871). Retries are NOT charged while held; state=expired survives the terminal expiry write.';
COMMENT ON COLUMN ai_import.ai_import_job.provider_hold_series_started_at IS
    'Start of the current hold series (issue #871 D-C4): the 6h hold budget is measured from here so a flapping provider cannot reset it one probe at a time.';

-- The breaker is consulted per claim, joined on the snapshot pair; the claim
-- already filters on status, so this index only has to make the hold sweeper
-- (status = 'failed' AND provider_hold IS NOT NULL) cheap.
CREATE INDEX idx_ai_import_job_provider_hold
    ON ai_import.ai_import_job (provider, model, next_attempt_at)
    WHERE provider_hold IS NOT NULL;
