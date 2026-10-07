-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- Reservation claim projection (ADR-036, issue #586).
--
-- `projection_number_reservation` mirrors the claim lifecycle of the
-- ES-native reservation streams (`reservation-*`, SierraDB category
-- `reservation`) for observability and reaper candidate selection ONLY. The
-- authoritative claim state lives in the event store; the reaper always
-- re-reads the reservation stream and the claimed aggregate's stream before
-- acting, so a lagging projector can never cause a wrong release.
--
-- Rows: one per reservation key (`epnum-{series}-{n}`,
-- `seasnum-{series}-{n}`, `blocknum-{series}-{n}`, `sspair-{scene}-{day}`),
-- state = the last lifecycle event kind (reserved / released / consumed),
-- `stream_version` = last observed stream version (idempotency guard).
-- `reserved_at` = timestamp of the LAST ReservationReserved event — the
-- reaper's TTL clock (a claim re-reserved after a release resets the clock).

CREATE TABLE IF NOT EXISTS projection_number_reservation (
    reservation_key TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN (
        'episode_number', 'season_number', 'block_number', 'scene_shoot_pair'
    )),
    aggregate_id UUID NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('reserved', 'released', 'consumed')),
    reserved_at TIMESTAMPTZ NOT NULL,
    released_at TIMESTAMPTZ,
    stream_version BIGINT NOT NULL,
    projector_version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reaper candidate selection: 'reserved' rows past their TTL, oldest first.
CREATE INDEX IF NOT EXISTS idx_projection_number_reservation_reaper
    ON projection_number_reservation (reserved_at)
    WHERE state = 'reserved';

-- Runbook constructor for lagging-claim observations.
CREATE INDEX IF NOT EXISTS idx_projection_number_reservation_state
    ON projection_number_reservation (state, kind);
