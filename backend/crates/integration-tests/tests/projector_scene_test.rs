use anyhow::Result;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use infra::projectors::SceneProjector;
use kameo_es::event_handler::EntityEventHandler;
use kameo_es::{Entity, EventType};
use kameo_es::{Event, Metadata, StreamId};
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn scene_created_event_projects_to_projection_scene() -> Result<()> {
    let (pool, _container) = infra::testing::spawn_postgres().await?;

    let project_id = ProjectId::new();
    let scene_id = Uuid::now_v7();
    let details = SceneDetails {
        scene_number: Some(42),
        location: Some("Berlin".into()),
        mood: Some("dark".into()),
        is_schedule_set: true,
    };
    let event = SceneEvent::SceneCreated {
        id: scene_id,
        project_id,
        details: details.clone(),
        assigned_characters: vec![Uuid::now_v7()],
        version: AggregateVersion::INITIAL,
    };

    let mut tx = pool.begin().await?;
    let kameo_event = Event {
        id: Uuid::now_v7(),
        partition_key: Uuid::now_v7(),
        partition_id: 0,
        transaction_id: Uuid::now_v7(),
        partition_sequence: 1,
        stream_version: 1,
        stream_id: StreamId::new_from_parts(SceneAggregate::category(), scene_id),
        name: event.event_type().to_string(),
        data: event,
        metadata: Metadata::default(),
        timestamp: Utc::now(),
    };

    SceneProjector
        .handle(&mut tx, scene_id, kameo_event)
        .await?;
    tx.commit().await?;

    let row = sqlx::query("SELECT * FROM projection_scene WHERE id = $1")
        .bind(scene_id)
        .fetch_one(&pool)
        .await?;

    assert_eq!(row.try_get::<Uuid, _>("id")?, scene_id);
    assert_eq!(row.try_get::<Uuid, _>("project_id")?, project_id.0);
    assert_eq!(row.try_get::<i32, _>("scene_number")?, 42);
    assert_eq!(row.try_get::<String, _>("location")?, "Berlin");
    assert_eq!(row.try_get::<String, _>("mood")?, "dark");
    assert!(row.try_get::<bool, _>("is_schedule_set")?);
    assert_eq!(row.try_get::<i64, _>("version")?, 1);

    let character_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_scene_character WHERE scene_id = $1")
            .bind(scene_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(character_count, 1);

    Ok(())
}
