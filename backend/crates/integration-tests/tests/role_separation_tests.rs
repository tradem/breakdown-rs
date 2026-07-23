// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
//
// Hardening tests for Postgres role separation (Issue #87).
//
// These tests verify the least-privilege security model:
//   - breakdown_migrator (DDL, schema owner)
//   - breakdown_app     (DML only, INSERT-only audit)
//
// They replicate the bootstrap logic from scripts/postgres-init-roles.sh and
// assert the production runtime guarantees:
//   1. DML works for breakdown_app on all projection_* tables.
//   2. DDL (CREATE TABLE / DROP TABLE) is denied for breakdown_app.
//   3. projection_audit is INSERT-only for breakdown_app (UPDATE/DELETE denied).
//   4. sqlx migrations run as breakdown_migrator.
//   5. breakdown_app cannot escalate to breakdown_migrator via SET ROLE.
//
// Each test starts a fresh Postgres container.

mod fixtures;

use anyhow::{Context, Result};
use sqlx::Executor;
use testcontainers::runners::AsyncRunner;
use testcontainers_modules::postgres::Postgres as PostgresImage;

/// Mirror of `scripts/postgres-init-roles.sh`: create roles and set up
/// least-privilege permissions. Additionally revokes the Postgres-default
/// `CREATE ON SCHEMA public FROM PUBLIC` so the app role truly cannot DDL.
async fn setup_roles(pool: &sqlx::PgPool) -> Result<()> {
    // Create roles if they don't exist.
    sqlx::query(
        r#"
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
        "#,
    )
    .execute(pool)
    .await?;

    // Transfer schema ownership to migrator.
    sqlx::query("ALTER SCHEMA public OWNER TO breakdown_migrator")
        .execute(pool)
        .await?;

    // Revoke the Postgres-default CREATE privilege on the public schema.
    // Otherwise EVERY role (including breakdown_app) can create tables.
    sqlx::query("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
        .execute(pool)
        .await?;

    // Grant schema USAGE to app role (required for any object access).
    sqlx::query("GRANT USAGE ON SCHEMA public TO breakdown_app")
        .execute(pool)
        .await?;

    // Default privileges: future tables created by migrator get DML grants.
    sqlx::query(
        r#"
        ALTER DEFAULT PRIVILEGES FOR ROLE breakdown_migrator IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO breakdown_app
        "#,
    )
    .execute(pool)
    .await?;

    // Grant DML on all existing tables.
    sqlx::query(
        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO breakdown_app",
    )
    .execute(pool)
    .await?;

    // Grant USAGE, SELECT on sequences.
    sqlx::query("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO breakdown_app")
        .execute(pool)
        .await?;

    Ok(())
}

/// Start a Postgres container, set up roles, run migrations, apply the
/// post-migration audit REVOKE, and return connection pools for both roles.
async fn spawn_role_separated_postgres(
) -> Result<(
    sqlx::PgPool,                                            // super_pool (postgres)
    sqlx::PgPool,                                            // migrator_pool (breakdown_migrator)
    sqlx::PgPool,                                            // app_pool (breakdown_app)
    testcontainers::ContainerAsync<PostgresImage>,           // container guard
)> {
    // ── 1. Start container and connect as superuser ──
    let image = fixtures::build_postgres_container_request();
    let container = image.start().await?;
    let host = container.get_host().await?;
    let port = container.get_host_port_ipv4(5432).await?;

    let super_url = format!("postgres://postgres:postgres@{host}:{port}/postgres");
    let super_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .connect(&super_url)
        .await?;

    sqlx::query("SELECT 1").fetch_one(&super_pool).await?;

    // ── 2. Create roles and set up permissions ──
    setup_roles(&super_pool).await.context("setup roles")?;

    // ── 3. Run migrations as breakdown_migrator ──
    let migrator_url =
        format!("postgres://breakdown_migrator:breakdown_migrator@{host}:{port}/postgres");
    let migrator_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .connect(&migrator_url)
        .await?;

    sqlx::migrate!("../infra/migrations")
        .run(&migrator_pool)
        .await
        .context("run migrations as breakdown_migrator")?;

    // ── 4. Apply post-migration: REVOKE on audit table ──
    sqlx::query("REVOKE UPDATE, DELETE ON projection_audit FROM breakdown_app")
        .execute(&migrator_pool)
        .await
        .context("revoke UPDATE/DELETE on audit table")?;

    // ── 5. Connect as breakdown_app ──
    let app_url = format!("postgres://breakdown_app:breakdown_app@{host}:{port}/postgres");
    let app_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&app_url)
        .await?;

    Ok((super_pool, migrator_pool, app_pool, container))
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

#[tokio::test]
async fn app_role_can_select_from_projection_tables() -> Result<()> {
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    let membership_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_membership")
            .fetch_one(&app)
            .await?;
    assert_eq!(membership_count, 0);

    let audit_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_audit")
            .fetch_one(&app)
            .await?;
    assert_eq!(audit_count, 0);

    // Also verify the _sqlx_migrations table is visible (sqlx needs it).
    let migration_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM _sqlx_migrations")
            .fetch_one(&app)
            .await?;
    assert!(migration_count > 0);

    Ok(())
}

#[tokio::test]
async fn app_role_can_insert_update_delete_on_projection_tables() -> Result<()> {
    let uuid = uuid::Uuid::now_v7();
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    // Use projection_membership — a stable table with a simple schema:
    //   (block_id, user_id, role, state, joined_at, updated_at)

    // ── INSERT ──
    sqlx::query(
        r#"
        INSERT INTO projection_membership (block_id, user_id, role, state, joined_at, updated_at)
        VALUES ($1, $2, 'Kostümbildner', 'active', NOW(), NOW())
        "#,
    )
    .bind(uuid)
    .bind("test-user")
    .execute(&app)
    .await
    .context("INSERT as breakdown_app should succeed")?;

    // ── SELECT ──
    let found: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM projection_membership WHERE block_id = $1 AND user_id = $2)",
    )
    .bind(uuid)
    .bind("test-user")
    .fetch_one(&app)
    .await?;
    assert!(found);

    // ── UPDATE ──
    let updated = sqlx::query(
        "UPDATE projection_membership SET role = $1 WHERE block_id = $2",
    )
    .bind("Gewandmeister")
    .bind(uuid)
    .execute(&app)
    .await
    .context("UPDATE as breakdown_app should succeed")?;
    assert_eq!(updated.rows_affected(), 1);

    // ── DELETE ──
    let deleted = sqlx::query("DELETE FROM projection_membership WHERE block_id = $1")
        .bind(uuid)
        .execute(&app)
        .await
        .context("DELETE as breakdown_app should succeed")?;
    assert_eq!(deleted.rows_affected(), 1);

    Ok(())
}

#[tokio::test]
async fn app_role_cannot_create_table() -> Result<()> {
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    let result = app
        .execute(sqlx::query(
            "CREATE TABLE app_role_should_fail (id UUID PRIMARY KEY)",
        ))
        .await;

    match result {
        Ok(_) => anyhow::bail!(
            "breakdown_app should NOT be able to CREATE TABLE, but it succeeded"
        ),
        Err(e) => {
            let msg = e.to_string();
            assert!(
                msg.contains("permission denied")
                    || msg.contains("insufficient privilege"),
                "expected permission denied, got: {msg}"
            );
        }
    }

    Ok(())
}

#[tokio::test]
async fn app_role_cannot_drop_table() -> Result<()> {
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    let result = app
        .execute(sqlx::query("DROP TABLE projection_membership"))
        .await;

    match result {
        Ok(_) => anyhow::bail!(
            "breakdown_app should NOT be able to DROP TABLE, but it succeeded"
        ),
        Err(e) => {
            let msg = e.to_string();
            assert!(
                msg.contains("permission denied")
                    || msg.contains("insufficient privilege")
                    || msg.contains("must be owner"),
                "expected permission denied or must be owner, got: {msg}"
            );
        }
    }

    Ok(())
}

#[tokio::test]
async fn audit_table_is_insert_only_for_app_role() -> Result<()> {
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    // ── INSERT should succeed ──
    let id = uuid::Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO projection_audit (id, event_key, entity_type, entity_id, event_type, payload, occurred_at)
        VALUES ($1, $2, 'test', 'test-id', 'TestEvent', '{}', NOW())
        "#,
    )
    .bind(id)
    .bind(format!("test-key-{id}"))
    .execute(&app)
    .await
    .context("INSERT into projection_audit as breakdown_app should succeed")?;

    // ── UPDATE should fail ──
    let update_result = app
        .execute(
            sqlx::query("UPDATE projection_audit SET event_type = 'Hacked' WHERE id = $1")
                .bind(id),
        )
        .await;

    match update_result {
        Ok(_) => anyhow::bail!("UPDATE on projection_audit should be denied for breakdown_app"),
        Err(e) => {
            let msg = e.to_string();
            assert!(
                msg.contains("permission denied"),
                "expected permission denied on audit UPDATE, got: {msg}"
            );
        }
    }

    // ── DELETE should fail ──
    let delete_result = app
        .execute(sqlx::query("DELETE FROM projection_audit WHERE id = $1").bind(id))
        .await;

    match delete_result {
        Ok(_) => anyhow::bail!("DELETE on projection_audit should be denied for breakdown_app"),
        Err(e) => {
            let msg = e.to_string();
            assert!(
                msg.contains("permission denied"),
                "expected permission denied on audit DELETE, got: {msg}"
            );
        }
    }

    Ok(())
}

#[tokio::test]
async fn app_role_cannot_escalate_to_migrator() -> Result<()> {
    let (_super, _migrator, app, _container) = spawn_role_separated_postgres().await?;

    let result = app
        .execute(sqlx::query("SET ROLE breakdown_migrator"))
        .await;

    match result {
        Ok(_) => anyhow::bail!(
            "breakdown_app should NOT be able to SET ROLE breakdown_migrator"
        ),
        Err(e) => {
            let msg = e.to_string();
            assert!(
                msg.contains("permission denied"),
                "expected permission denied on SET ROLE, got: {msg}"
            );
        }
    }

    Ok(())
}
