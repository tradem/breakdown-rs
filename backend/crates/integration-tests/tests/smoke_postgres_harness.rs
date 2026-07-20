// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

mod fixtures;

use anyhow::Result;
use breakdown_core::shared::SeasonId;
use fixtures::spawn_postgres;
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn postgres_harness_spins_up_and_applies_migrations() -> Result<()> {
    let (pool, _container) = spawn_postgres().await?;

    let id = Uuid::now_v7();
    let season_id = SeasonId::new();

    sqlx::query(
        r#"
        INSERT INTO projection_character
            (id, season_id, name, category, measurements, contact, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
        "#,
    )
    .bind(id)
    .bind(season_id.0)
    .bind("Smoke Test")
    .bind(serde_json::json!("main_cast"))
    .bind(serde_json::json!({}))
    .bind(serde_json::json!({}))
    .bind(1_i64)
    .execute(&pool)
    .await?;

    let row_name: String = sqlx::query("SELECT name FROM projection_character WHERE id = $1")
        .bind(id)
        .fetch_one(&pool)
        .await?
        .try_get("name")?;

    assert_eq!(row_name, "Smoke Test");

    Ok(())
}
