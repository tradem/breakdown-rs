// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Contract: the settings projector populates the credential-binding owner
//! from the persisted event metadata (issue #552).
//!
//! The AI-config API edge compares `projection_settings.owner` against the
//! authenticated caller to reject a foreign-but-valid `vault_key_id`
//! (confused deputy). These tests drive the real SierraDB → projector →
//! Postgres pipeline and assert:
//!
//! 1. `CredentialBound` records the dispatching actor as `owner`.
//! 2. Rotation never mutates the owner — in particular it does NOT backfill
//!    a legacy row whose bind event carried no actor metadata (the rotating
//!    actor is not verified against the binding owner, so a backfill would
//!    let any credential-role member claim a legacy binding; issue #552
//!    review).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use infra::projectors::{ProjectorFlushConfig, spawn_settings_projector};
use kameo_es::Metadata;
use redis::Client as RedisClient;
use sqlx::PgPool;
use uuid::Uuid;

use breakdown_core::settings::events::SettingsEvent;
use breakdown_core::shared::{AggregateVersion, EventMetadata, Provenance, UserId};

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);
const OWNER_SUB: &str = "settings-owner-test-user";

/// Append one event with the kameo_es metadata envelope
/// (`Metadata<EventMetadata>`, CBOR) exactly as the command service writes
/// it — the projector recovers the actor from this envelope.
async fn eappend_with_metadata<T: serde::Serialize>(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &T,
    metadata: &Metadata<EventMetadata>,
) -> Result<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;

    let mut encoded = Vec::new();
    ciborium::into_writer(payload, &mut encoded).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    let mut meta_buf = Vec::new();
    ciborium::into_writer(metadata, &mut meta_buf)
        .map_err(|e| anyhow!("CBOR metadata encode failed: {e}"))?;

    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&encoded)
        .arg("METADATA")
        .arg(&meta_buf)
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

fn actor_metadata(sub: &str) -> Metadata<EventMetadata> {
    Metadata {
        data: Some(EventMetadata {
            actor: Some(UserId::from_sub(sub)),
            provenance: Provenance::Human,
            project_id: None,
        }),
        ..Default::default()
    }
}

/// Poll `projection_settings` until the row's `owner` is non-NULL (bind
/// processed) and return it.
async fn await_owner(pool: &PgPool, id: Uuid) -> Result<Option<String>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        tokio::time::sleep(POLL_INTERVAL).await;
        if std::time::Instant::now() > deadline {
            anyhow::bail!("projection_settings row for {id} not projected in time");
        }
        let owner: Option<Option<String>> =
            sqlx::query_scalar("SELECT owner FROM projection_settings WHERE id = $1")
                .bind(id)
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("owner read failed: {e}"))?;
        if let Some(owner) = owner {
            return Ok(owner);
        }
    }
}

#[tokio::test]
async fn settings_projector_records_the_binding_owner() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_settings_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let settings_id = Uuid::now_v7();
    let stream_id = format!("settings-{settings_id}");

    let bind = SettingsEvent::CredentialBound {
        id: settings_id,
        provider: "gdrive".into(),
        vault_key_id: format!("settings-{settings_id}:1"),
        vault_version: 1,
        version: AggregateVersion::INITIAL,
    };
    eappend_with_metadata(
        &redis_client,
        &stream_id,
        "CredentialBound",
        "EMPTY",
        &bind,
        &actor_metadata(OWNER_SUB),
    )
    .await?;

    let owner = await_owner(&pool, settings_id).await?;
    assert_eq!(
        owner.as_deref(),
        Some(OWNER_SUB),
        "the bind event's actor must become the binding owner"
    );

    // Rotation with a different actor must NOT overwrite the owner (issue
    // #552: the owner of a binding is immutable; the rotating actor must be
    // the owner in practice, so COALESCE keeps the recorded value).
    let rotate = SettingsEvent::CredentialRotated {
        id: settings_id,
        provider: "gdrive".into(),
        vault_key_id: format!("settings-{settings_id}:2"),
        vault_version: 2,
        version: AggregateVersion(2),
    };
    eappend_with_metadata(
        &redis_client,
        &stream_id,
        "CredentialRotated",
        "0",
        &rotate,
        &actor_metadata("someone-else"),
    )
    .await?;
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let version: Option<i64> =
            sqlx::query_scalar("SELECT version FROM projection_settings WHERE id = $1")
                .bind(settings_id)
                .fetch_optional(&pool)
                .await
                .map_err(|e| anyhow!("version read failed: {e}"))?;
        if version == Some(2) {
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!("rotation not projected in time");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
    let owner: Option<String> =
        sqlx::query_scalar("SELECT owner FROM projection_settings WHERE id = $1")
            .bind(settings_id)
            .fetch_one(&pool)
            .await
            .map_err(|e| anyhow!("owner read failed: {e}"))?;
    assert_eq!(
        owner.as_deref(),
        Some(OWNER_SUB),
        "rotation must keep the original owner"
    );

    Ok(())
}

#[tokio::test]
async fn rotation_keeps_a_legacy_null_owner() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_settings_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let settings_id = Uuid::now_v7();
    let stream_id = format!("settings-{settings_id}");

    // Legacy bind WITHOUT actor metadata — the projector leaves `owner` NULL
    // (pre-#552 replay shape), which the API edge fails closed on.
    let bind = SettingsEvent::CredentialBound {
        id: settings_id,
        provider: "gdrive".into(),
        vault_key_id: format!("settings-{settings_id}:1"),
        vault_version: 1,
        version: AggregateVersion::INITIAL,
    };
    eappend_with_metadata(
        &redis_client,
        &stream_id,
        "CredentialBound",
        "EMPTY",
        &bind,
        &Metadata::default(),
    )
    .await?;
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let row: Option<Option<String>> =
            sqlx::query_scalar("SELECT owner FROM projection_settings WHERE id = $1")
                .bind(settings_id)
                .fetch_optional(&pool)
                .await
                .map_err(|e| anyhow!("owner read failed: {e}"))?;
        if row.is_some() {
            assert!(
                row.flatten().is_none(),
                "a bind without actor metadata must project a NULL owner"
            );
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!("legacy bind not projected in time");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // The owner rotates their key — rotation refreshes the key but must NOT
    // touch the owner: the settings rotate handlers do not verify the
    // rotating actor against the binding owner, so a backfill would let any
    // credential-role member claim a legacy binding (issue #552 review).
    // Legacy owners recover via re-projection only (runbook §10).
    let rotate = SettingsEvent::CredentialRotated {
        id: settings_id,
        provider: "gdrive".into(),
        vault_key_id: format!("settings-{settings_id}:2"),
        vault_version: 2,
        version: AggregateVersion(2),
    };
    eappend_with_metadata(
        &redis_client,
        &stream_id,
        "CredentialRotated",
        "0",
        &rotate,
        &actor_metadata(OWNER_SUB),
    )
    .await?;
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let row: Option<(i64, Option<String>)> =
            sqlx::query_as("SELECT version, owner FROM projection_settings WHERE id = $1")
                .bind(settings_id)
                .fetch_optional(&pool)
                .await
                .map_err(|e| anyhow!("row read failed: {e}"))?;
        if let Some((version, owner)) = row
            && version >= 2
        {
            assert_eq!(
                owner, None,
                "rotation must not backfill a legacy NULL owner"
            );
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!("rotation not projected in time");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    Ok(())
}
