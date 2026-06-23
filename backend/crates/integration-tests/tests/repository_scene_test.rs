use anyhow::Result;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use infra::queries::SceneRepositoryImpl;
use uuid::Uuid;

#[tokio::test]
async fn scene_repository_returns_view_with_version_and_updated_at() -> Result<()> {
    let (pool, _container) = infra::testing::spawn_postgres().await?;

    let project_id = ProjectId::new();
    let scene_id = Uuid::now_v7();
    let updated_at = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO projection_scene
            (id, project_id, scene_number, location, mood, is_schedule_set, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(scene_id)
    .bind(project_id.0)
    .bind(10_i32)
    .bind("Studio")
    .bind("Neutral")
    .bind(true)
    .bind(7_i64)
    .bind(updated_at)
    .execute(&pool)
    .await?;

    let repo = SceneRepositoryImpl::new(pool);
    let view = repo.find_by_id(scene_id).await?;

    assert_eq!(view.id, scene_id);
    assert_eq!(view.project_id, project_id);
    assert_eq!(view.scene_number, Some(10));
    assert_eq!(view.location, Some("Studio".into()));
    assert_eq!(view.mood, Some("Neutral".into()));
    assert!(view.is_schedule_set);
    assert_eq!(view.version, AggregateVersion(7));
    assert_eq!(view.updated_at, updated_at);

    Ok(())
}
