-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
--
-- Bootstrap: Grant DML-only permissions to the app role.
--
-- Applied out-of-band after 01_create_roles.sql. For local dev, these
-- privileges are set automatically by scripts/postgres-init-roles.sh.

-- Schema USAGE (required for any object access).
GRANT USAGE ON SCHEMA public TO breakdown_app;

-- Default privileges: any future table created by breakdown_migrator
-- automatically gets DML grants for breakdown_app.
ALTER DEFAULT PRIVILEGES FOR ROLE breakdown_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO breakdown_app;

-- Existing tables (if any).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO breakdown_app;

-- Sequences (for SERIAL/BIGSERIAL columns).
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO breakdown_app;

-- The audit table gets a narrower privilege set (INSERT-only).
-- This is applied as a post-migration step in main.rs because the
-- table does not exist at init time. In production, run this AFTER
-- migrations:
--   REVOKE UPDATE, DELETE ON projection_audit FROM breakdown_app;
