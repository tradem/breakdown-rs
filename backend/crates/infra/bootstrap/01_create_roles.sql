-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
--
-- Bootstrap: Create Postgres roles for the Breakdown CQRS runtime.
--
-- This script is applied out-of-band by ops (deploy bootstrap / init container),
-- NOT via sqlx::migrate! (chicken-and-egg: roles must exist before the migration
-- can connect as the migrator user).
--
-- For local dev, this logic is replicated in scripts/postgres-init-roles.sh
-- and mounted as a docker-entrypoint-initdb.d script.

-- Create the migrator role (owns the projection schema; DDL rights).
CREATE ROLE breakdown_migrator WITH LOGIN PASSWORD 'change-me-in-production';

-- Create the app role (DML only; no DDL, DROP, TRUNCATE, or CREATE).
CREATE ROLE breakdown_app WITH LOGIN PASSWORD 'change-me-in-production';

-- Transfer schema ownership so migrations run as the schema owner.
ALTER SCHEMA public OWNER TO breakdown_migrator;
