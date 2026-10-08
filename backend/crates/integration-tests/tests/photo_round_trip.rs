// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 integration test: Postgres + SierraDB + Garage full round-trip.
//!
//! Spawns the Photo projector + thumbnail/deletion/bytes-cleanup sagas and
//! exercises the full command→event→projection→read chain for photo lifecycle.

mod fixtures;

fn test_user() -> breakdown_core::shared::UserId {
    crate::fixtures::test_user()
}

use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

use anyhow::Result;
use breakdown_core::photo::commands::UploadPhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::photo::views::PhotoView;
use breakdown_core::shared::{PhotoId, PhotoVariant, VariantStatus};
use fixtures::{await_photo, build_storage, spawn_garage, spawn_postgres, spawn_sierradb};

use infra::photo::repository::PhotoRepositoryImpl;
use kameo_es::command_service::CommandService;

/// Seed a Season into projection_season.
async fn seed_season(pool: &sqlx::PgPool) -> Result<breakdown_core::shared::SeasonId> {
    let project_id = Uuid::now_v7();
    let season_id = Uuid::now_v7();
    sqlx::query(
        r#"INSERT INTO projection_season (id, project_id, number, title, version, updated_at)
           VALUES ($1, $2, 1, 'Season 1', 1, now())"#,
    )
    .bind(season_id)
    .bind(project_id)
    .execute(pool)
    .await?;
    Ok(breakdown_core::shared::SeasonId(season_id))
}

/// Seed a Character into projection_character.
async fn seed_character(pool: &sqlx::PgPool, season_id: Uuid) -> Result<Uuid> {
    let char_id = Uuid::now_v7();
    sqlx::query(
        r#"INSERT INTO projection_character (id, name, season_id, category, measurements, contact, version, updated_at)
           VALUES ($1, 'Char', $2, '"main_cast"'::jsonb, '{}'::jsonb, '{}'::jsonb, 1, now())"#,
    )
    .bind(char_id)
    .bind(season_id)
    .execute(pool)
    .await?;
    Ok(char_id)
}

/// Seed a Costume into projection_costume.
async fn seed_costume(pool: &sqlx::PgPool, character_id: Uuid) -> Result<Uuid> {
    let costume_id = Uuid::now_v7();
    sqlx::query(
        r#"INSERT INTO projection_costume (id, character_id, notes, version, updated_at)
           VALUES ($1, $2, '', 1, now())"#,
    )
    .bind(costume_id)
    .bind(character_id)
    .execute(pool)
    .await?;
    Ok(costume_id)
}

/// True when `kind` has reached a terminal status (`Ready` or `Failed`) in the
/// projected view — i.e. the thumbnail saga is done working on that variant.
fn variant_terminal(view: &PhotoView, kind: PhotoVariant) -> bool {
    view.variants
        .iter()
        .any(|v| v.kind == kind && matches!(v.status, VariantStatus::Ready | VariantStatus::Failed))
}

/// Poll until the projection reports BOTH variants the thumbnail saga owns
/// (`Thumb` and `Medium`) as terminal, and return that settled view.
///
/// The settled view exists for one reason: its `version`. Since `511baaa9` the
/// thumbnail saga actually runs (before that it was never wired into production,
/// and this round-trip test only passed because of that), and every variant it
/// finishes appends an event to the Photo stream. The version `UploadPhoto`
/// returns is therefore already stale by the time the projection row appears, so
/// a delete that echoes it is a legitimate optimistic-concurrency defeat —
/// `version conflict: expected AggregateVersion(0), current AggregateVersion(3)`.
///
/// A real client never sees this, because it reads the photo view (which carries
/// the projected version) before issuing the delete; this waits for the same
/// settled state, so the delete echoes the version a client would echo. Waiting
/// on STATE rather than on a fixed version number keeps the test honest about how
/// many events the saga happens to emit. Retries on `NotFound`: the projector may
/// not have reached the row yet.
///
/// `Original` is deliberately NOT part of the wait. This fixture's bytes are a
/// truncated JPEG header, so normalization fails and the saga's failure path
/// marks only `Thumb`/`Medium` `Failed`, leaving the untouched `Original` row
/// `Pending`. Observed while fixing this test; whether a permanently `Pending`
/// `Original` is the right terminal state belongs to the photo bounded context
/// and is tracked separately, not answered here.
async fn await_photo_settled(
    repo: &PhotoRepositoryImpl,
    photo_id: PhotoId,
    deadline: tokio::time::Instant,
) -> Result<PhotoView> {
    loop {
        match repo.find_by_id(photo_id).await {
            Ok(view)
                if variant_terminal(&view, PhotoVariant::Thumb)
                    && variant_terminal(&view, PhotoVariant::Medium) =>
            {
                return Ok(view);
            }
            Ok(view) => {
                if tokio::time::Instant::now() > deadline {
                    let seen: Vec<String> = view
                        .variants
                        .iter()
                        .map(|v| format!("{:?}:{:?}", v.kind, v.status))
                        .collect();
                    anyhow::bail!(
                        "Timed out waiting for the photo variants to settle; last \
                         seen version={:?} variants=[{}]",
                        view.version,
                        seen.join(", ")
                    );
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
            Err(error) => {
                if tokio::time::Instant::now() > deadline {
                    anyhow::bail!("Timed out waiting for the photo projection: {error:?}");
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
}

#[tokio::test]
async fn photo_upload_then_delete_round_trip() -> Result<()> {
    // Start all three tiers.
    let (pg_pool, _pg_guard) = spawn_postgres().await?;
    let (sierra_client, _conn, _sierra_guard) = spawn_sierradb().await?;
    let (creds, _garage_guard) = spawn_garage().await?;

    let storage = build_storage(&creds);
    let cmd_service = {
        let conn = sierra_client.get_multiplexed_async_connection().await?;
        CommandService::new(conn)
    };
    let photo_repo = PhotoRepositoryImpl::new(pg_pool.clone());

    // Seed Season → Character → Costume before creating PhotoCommandsImpl.
    let season_id = seed_season(&pg_pool).await?;
    let character_id = seed_character(&pg_pool, season_id.0).await?;
    let costume_id = seed_costume(&pg_pool, character_id).await?;

    let photo_commands = infra::event_store::PhotoCommandsImpl::new(cmd_service.clone());

    // Spawn the photo projector.
    let redis_client = Arc::clone(&sierra_client);
    let _photo_projector = infra::projectors::spawn_photo_projector(
        pg_pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    // Spawn photo sagas.
    infra::photo::sagas::spawn_photo_thumbnail_saga(
        cmd_service.clone(),
        storage.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_bytes_cleanup_saga(storage.clone(), Arc::clone(&redis_client))
        .await?;

    // Generate a photo ID and store original bytes in Garage.
    let photo_id = PhotoId::new();
    let content_type = "image/jpeg".to_string();
    let image_bytes = vec![
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b,
        0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
        0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31,
        0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32,
    ];

    // Store original bytes in Garage first (the saga needs them).
    storage
        .store(
            photo_id,
            PhotoVariant::Original,
            image_bytes.clone(),
            content_type.clone(),
        )
        .await?;

    // 1. Dispatch UploadPhoto command — binding points to the seeded costume.
    let version = photo_commands
        .upload(
            test_user(),
            UploadPhoto {
                id: photo_id,
                content_type: content_type.clone(),
                size_bytes: image_bytes.len() as u64,
                binding: breakdown_core::photo::binding::PhotoBinding::Costume { costume_id },
                project_id: Some(breakdown_core::shared::ProjectId::new()),
            },
        )
        .await?;
    assert!(version.0 > 0, "UploadPhoto should return version > 0");

    // 2. Wait for the projector to create the projection row.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let photo_view = await_photo(&photo_repo, photo_id, deadline).await?;
    assert_eq!(photo_view.id, photo_id);
    assert_eq!(photo_view.content_type, content_type);
    assert_eq!(photo_view.size_bytes, image_bytes.len() as u64);

    // 3. Verify bytes are still fetchable from Garage.
    let fetched = storage.fetch(photo_id, PhotoVariant::Original).await?;
    assert_eq!(fetched.bytes, image_bytes);

    // 4. Dispatch DeletePhoto with the SETTLED version. `version` from the upload
    //    ack is already behind the aggregate: the saga appended its variant events
    //    in the meantime (see `await_photo_settled`).
    let settled = await_photo_settled(&photo_repo, photo_id, deadline).await?;
    assert!(
        settled.version.0 > version.0,
        "the thumbnail saga must have advanced the aggregate beyond the upload \
         ack (upload {}, settled {}) — otherwise this test is not echoing the \
         version a client would actually have",
        version.0,
        settled.version.0
    );
    photo_commands
        .delete(
            test_user(),
            breakdown_core::photo::commands::DeletePhoto {
                id: photo_id,
                project_id: None,
                version: settled.version,
            },
        )
        .await?;

    // 5. Wait for the bytes-cleanup saga to remove bytes from Garage.
    tokio::time::sleep(Duration::from_secs(5)).await;
    let fetch_result = storage.fetch(photo_id, PhotoVariant::Original).await;
    assert!(
        fetch_result.is_err(),
        "Original bytes should be deleted after PhotoDeleted"
    );

    Ok(())
}
