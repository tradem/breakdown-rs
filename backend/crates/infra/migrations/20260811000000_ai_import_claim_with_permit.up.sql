-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: gpt-5.6-luna (pi)
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #180: link a job to the concurrency permit that owns its claim, so a
-- reclaiming worker can release the orphan of a crashed worker exactly once.
--
-- Two leases already guard an in-flight job: the job lease on this table
-- (`lease_expires_at`, issue #177) and the permit lease on
-- `ai_import.concurrency_permit` (`expires_at`, issue #178). They recover on
-- different clocks. When a worker dies, the job lease is reclaimed and the job
-- runs again elsewhere, but the dead worker's permit row lives until its own
-- lease lapses — up to AI_IMPORT_LEASE_SECS (900s) of capacity consumed by a
-- job that is already running somewhere else.
--
-- This column closes that gap. `claim_next_reconciling` reads the `permit_id`
-- left by the previous claim and deletes that permit row in the same statement
-- that flips the job to the new worker. Reconciliation is exactly-once: only
-- the worker that wins the `FOR UPDATE SKIP LOCKED` race observes a non-null
-- orphan id, the DELETE is by primary key, and the same statement resets this
-- column to NULL.
--
-- The claim writes NULL here, not the new owner's permit: capacity is acquired
-- *after* the claim, once the job's `user_id` is known, and linked back with
-- `attach_permit`. Acquiring before the claim would mean acquiring before the
-- owning user is known, and the per-user ceiling could then only be charged to
-- a synthetic per-worker identity — i.e. it would never bind.
--
-- No FK: the referenced permit may already have been reclaimed and deleted by
-- the lease sweep in `try_acquire_as`. The reclaim path treats a missing
-- permit as "already freed" rather than an error, and an FK would instead turn
-- that ordinary race into a constraint violation.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN permit_id UUID;

COMMENT ON COLUMN ai_import.ai_import_job.permit_id IS
    'Concurrency permit owning the current claim, linked after acquisition by attach_permit. NULL when the job is unclaimed, between claim and acquisition, or after the permit was released.';
