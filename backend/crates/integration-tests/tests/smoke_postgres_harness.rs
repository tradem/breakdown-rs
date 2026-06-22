// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Template smoke test for the Postgres Testcontainers harness.
//!
//! This test exercises the canonical integration-test pattern:
//!
//! ```text
//! spawn resource → seed via public command API → assert via public query API → drop guards
//! ```
//!
//! In this minimal form the test only verifies the harness itself: a fresh
//! Postgres container is started, the projection schema is applied, and a
//! round-trip insert/select works. The command/event-store step against
//! sierradb (via `kameo_es`) is deferred to a follow-up feature branch; the
//! harness structure is already prepared to host that step once a sierradb
//! test instance is available.

use anyhow::Result;
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn postgres_harness_spins_up_and_applies_migrations() -> Result<()> {
    let (pool, _container) = infra::testing::spawn_postgres().await?;

    let id = Uuid::now_v7();

    sqlx::query("INSERT INTO integration_test_smoke_check (id) VALUES ($1)")
        .bind(id)
        .execute(&pool)
        .await?;

    let row: Uuid = sqlx::query("SELECT id FROM integration_test_smoke_check WHERE id = $1")
        .bind(id)
        .fetch_one(&pool)
        .await?
        .try_get("id")?;

    assert_eq!(row, id);

    Ok(())
}
