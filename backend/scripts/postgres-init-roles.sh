#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
#
# Bootstrap script for the dev Postgres container (docker-compose.dev.yml).
# Creates the migrator and app roles with least-privilege DML rights.
#
# Runs automatically on first container start via docker-entrypoint-initdb.d.
# Idempotent: safe to re-run on container restart with persisted volume.
#
# The per-table REVOKE on projection_audit (INSERT-only enforcement) cannot
# run here because the table does not exist yet at init time. It is applied
# as a post-migration step in main.rs.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
    -- Create roles if they don't exist (idempotent via DO block)
    DO $$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'breakdown_migrator') THEN
            CREATE ROLE breakdown_migrator WITH LOGIN PASSWORD 'breakdown_migrator';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'breakdown_app') THEN
            CREATE ROLE breakdown_app WITH LOGIN PASSWORD 'breakdown_app';
        END IF;
    END
    $$;

    -- Transfer schema ownership to the migrator role so it can run DDL.
    ALTER SCHEMA public OWNER TO breakdown_migrator;

    -- Grant schema USAGE to the app role (required for any object access).
    GRANT USAGE ON SCHEMA public TO breakdown_app;

    -- Default privileges: any table created by breakdown_migrator in the future
    -- automatically grants DML to breakdown_app. This keeps migrations clean:
    -- no per-table GRANT statements needed.
    ALTER DEFAULT PRIVILEGES FOR ROLE breakdown_migrator IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO breakdown_app;

    -- Grant DML on all existing tables (the public schema may already have
    -- tables from previous boots with a persisted volume).
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO breakdown_app;

    -- Grant USAGE on all sequences (needed for any SERIAL/BIGSERIAL columns).
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO breakdown_app;
EOSQL
