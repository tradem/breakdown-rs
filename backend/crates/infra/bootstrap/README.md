# Bootstrap: Postgres Role Separation

This directory contains reference SQL scripts for deploying the two-role
Postgres security model described in ADR-### (Issue #87).

## Files

| File | Purpose |
|------|---------|
| `01_create_roles.sql` | Creates `breakdown_migrator` and `breakdown_app` roles |
| `02_grant_app_permissions.sql` | Grants DML-only permissions to `breakdown_app` |

## Deploy order (production)

These scripts are applied **out-of-band** by ops (deploy bootstrap), NOT via
`sqlx::migrate!` (chicken-and-egg: roles must exist before the migrator can
connect).

1. Run `01_create_roles.sql` as a Postgres superuser / `cloudsqlsuperuser`.
2. Run `02_grant_app_permissions.sql` as a Postgres superuser.
3. Deploy the application binary with:
   - `MIGRATOR_DATABASE_URL` → connect as `breakdown_migrator`
   - `DATABASE_URL` → connect as `breakdown_app`
4. On boot, the binary runs `sqlx::migrate!()` on the migrator pool (DDL),
   then drops it and serves requests on the app pool (DML only).
5. After migrations, the binary runs `REVOKE UPDATE, DELETE ON projection_audit
   FROM breakdown_app` to enforce INSERT-only audit logging.

## Dev runtime

For local dev, the equivalent logic is in `scripts/postgres-init-roles.sh`,
which is mounted into the Postgres container's `/docker-entrypoint-initdb.d/`
directory by `docker-compose.dev.yml`.

## Role privileges

| Privilege | `breakdown_migrator` | `breakdown_app` |
|-----------|---------------------|-----------------|
| Schema `public` | OWNER | USAGE |
| `CREATE TABLE`, `ALTER`, indexes | ✅ | ❌ |
| `SELECT`, `INSERT`, `UPDATE`, `DELETE` on `projection_*` | via ownership | ✅ |
| `INSERT` on `projection_audit` | via ownership | ✅ |
| `UPDATE`, `DELETE` on `projection_audit` | via ownership | ❌ (revoked) |
| `DROP TABLE`, `TRUNCATE` | ✅ | ❌ |
