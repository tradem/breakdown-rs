use anyhow::Result;
use breakdown_core::shared::ProjectId;
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn postgres_harness_spins_up_and_applies_migrations() -> Result<()> {
    let (pool, _container) = infra::testing::spawn_postgres().await?;

    let id = Uuid::now_v7();
    let project_id = ProjectId::new();

    sqlx::query(
        r#"
        INSERT INTO projection_character
            (id, project_id, name, is_extra, is_main_character, measurements, contact, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
        "#,
    )
    .bind(id)
    .bind(project_id.0)
    .bind("Smoke Test")
    .bind(false)
    .bind(false)
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
