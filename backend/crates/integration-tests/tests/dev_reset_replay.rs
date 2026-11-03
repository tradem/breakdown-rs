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
//! Tier-4: the level-`business` keep-list round trip (issue #810).
//!
//! The 2026-11-03 loss happened because nothing ever tested the actual
//! `export → drop the event store → replay` composition: the export was allowed
//! to carry zero events and the replay reported `0` as success, so a failed run
//! silently turned a recoverable incident into a permanent one.
//!
//! "Dropping the volume" is modelled by spawning a **second** SierraDB
//! container: a fresh container is, by definition, an empty store — the same
//! state the wrapper produces with `docker volume rm` (SierraDB 0.3.1 has no
//! delete command).
//!
//! Covered here:
//! 1. a real export → replay into a fresh store restores every keep stream
//!    verbatim, and replaying twice is refused (strict versioning),
//! 2. an export whose keep projections hold rows but whose streams carry no
//!    events is refused unless the operator passes `--allow-empty-keep-list`,
//! 3. the projections keep naming the keep streams, which is what makes the
//!    wipe's empty-store assertion survive an empty export (guard 6).

mod fixtures;

use std::time::{Duration, UNIX_EPOCH};

use anyhow::{Result, anyhow};
use infra::dev_reset::events;
use redis::aio::MultiplexedConnection;
use sierradb_client::{AsyncTypedCommands, EMAppendEvent, ExpectedVersion, stream_partition_key};
use sqlx::PgPool;
use uuid::Uuid;

const DATABASE_TARGET: &str = "localhost/breakdown";

/// Appends one event to a keep stream, reproducing the stream's versions.
///
/// The event id is left to SierraDB (it must embed the partition hash, which is
/// why the replay re-uses the ids the store generated — see below).
async fn append_keep_event(
    connection: &mut MultiplexedConnection,
    stream: &str,
    event_name: &str,
    stream_version: u64,
) -> Result<()> {
    let expected = match stream_version {
        0 => ExpectedVersion::Empty,
        version => ExpectedVersion::Exact(version - 1),
    };
    let event = EMAppendEvent::new(stream, event_name)
        .expected_version(expected)
        .timestamp(UNIX_EPOCH + Duration::from_secs(1_700_000_000))
        // The reset tooling is byte-verbatim: no projector reads these payloads,
        // so a CBOR empty map is enough to prove the round trip.
        .payload(vec![0xa0])
        .metadata(Vec::new());
    connection
        .emappend(stream_partition_key(stream), &[event])
        .await
        .map_err(|error| anyhow!("EMAPPEND {stream}: {error}"))?;
    Ok(())
}

/// Seeds the keep projections — the export resolves its stream ids from them.
///
/// All three keep categories are seeded on purpose: `membership` is keyed by its
/// **block id** and named `membership-<block>` (not `<category>-<id>`), so a
/// regression in `keep_id_sql` or `stream_id` would otherwise stay invisible
/// here (issue #810 review).
async fn seed_keep_projections(
    pool: &PgPool,
    ai_config_id: Uuid,
    settings_id: Uuid,
    block_id: Uuid,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO ai_import.projection_ai_config
            (id, user_id, provider, assistant_model, vault_key_id, version)
        VALUES ($1, 'dev-user', 'openrouter', 'assistant-x', 'vault-key-ai-config', 1)
        "#,
    )
    .bind(ai_config_id)
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        INSERT INTO projection_settings
            (id, provider, vault_key_id, vault_version, binding_state, version, updated_at)
        VALUES ($1, 'openrouter', 'vault-key-settings', 1, 'active', 1, now())
        "#,
    )
    .bind(settings_id)
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        INSERT INTO projection_membership
            (block_id, user_id, role, state, joined_at, updated_at)
        VALUES ($1, 'dev-user', 'Kostümbildner', 'active', now(), now())
        "#,
    )
    .bind(block_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Tier-4: export → fresh store → replay restores the keep-list exactly.
#[tokio::test]
async fn keep_list_export_survives_a_fresh_event_store_and_replays_back() -> Result<()> {
    let (pool, _postgres) = crate::fixtures::spawn_postgres().await?;
    let (_client, mut store, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let ai_config_id = Uuid::now_v7();
    let settings_id = Uuid::now_v7();
    let block_id = Uuid::now_v7();
    seed_keep_projections(&pool, ai_config_id, settings_id, block_id).await?;

    let ai_config_stream =
        events::stream_id(infra::dev_reset::AggregateCategory::AiConfig, ai_config_id);
    let settings_stream =
        events::stream_id(infra::dev_reset::AggregateCategory::Settings, settings_id);
    let membership_stream =
        events::stream_id(infra::dev_reset::AggregateCategory::Membership, block_id);
    append_keep_event(&mut store, &ai_config_stream, "AiConfigCreated", 0).await?;
    append_keep_event(&mut store, &ai_config_stream, "AiConfigUpdated", 1).await?;
    append_keep_event(&mut store, &settings_stream, "SettingsBound", 0).await?;
    append_keep_event(&mut store, &membership_stream, "MemberInvited", 0).await?;

    // 1. Export against the store that still holds the configuration.
    let export = events::export_keep_list(&pool, &mut store, DATABASE_TARGET, false).await?;
    assert_eq!(export.streams.len(), 3, "one stream per keep aggregate");
    assert_eq!(export.event_count(), 4);
    assert!(
        export
            .streams
            .iter()
            .any(|stream| stream.stream_id == membership_stream),
        "the membership stream keeps its block-id naming"
    );

    // 2. The wrapper's `docker volume rm`: a brand-new container = empty store.
    let (_fresh_client, mut fresh, _fresh_sierra) = crate::fixtures::spawn_sierradb().await?;

    // The wipe's assertion (guard 6) probes the streams the projections name.
    let probes = events::current_keep_streams(&pool).await?;
    assert_eq!(
        probes.len(),
        3,
        "the projections name all three keep streams"
    );
    assert!(
        probes.contains(&membership_stream),
        "current_keep_streams resolves membership through its block id"
    );

    // 3. Replay into the fresh store and re-read every stream.
    let appended = events::replay_keep_list(&mut fresh, &export).await?;
    assert_eq!(appended, export.event_count());
    for stream in &export.streams {
        // Verbatim means verbatim — event ids, versions, timestamps, names and
        // both hex payloads (the replay must reproduce the original history).
        let replayed = events::read_stream(&mut fresh, &stream.stream_id).await?;
        assert_eq!(
            replayed, stream.events,
            "stream {} must come back verbatim",
            stream.stream_id
        );
    }

    // 4. Strict versioning: a second replay into a non-empty store is refused.
    assert!(
        events::replay_keep_list(&mut fresh, &export).await.is_err(),
        "replaying into a non-empty store must fail loudly"
    );
    Ok(())
}

/// Defect 1 of issue #810: an export taken *after* the store was lost must abort
/// before the wipe, and the override is explicit.
#[tokio::test]
async fn an_export_of_an_already_emptied_store_is_refused() -> Result<()> {
    let (pool, _postgres) = crate::fixtures::spawn_postgres().await?;
    let (_client, mut store, _sierra) = crate::fixtures::spawn_sierradb().await?;

    // Exactly the 2026-11-03 state: the read model still holds the configuration
    // rows, the event store is empty.
    let ai_config_id = Uuid::now_v7();
    let settings_id = Uuid::now_v7();
    let block_id = Uuid::now_v7();
    seed_keep_projections(&pool, ai_config_id, settings_id, block_id).await?;

    let error = events::export_keep_list(&pool, &mut store, DATABASE_TARGET, false)
        .await
        .expect_err("an export with rows but no events must be refused");
    let message = error.to_string();
    assert!(message.contains("refusing to export"), "{message}");
    assert!(message.contains("--allow-empty-keep-list"), "{message}");

    // The explicit override exports, and the plan/dry-run can then show `0`.
    let export = events::export_keep_list(&pool, &mut store, DATABASE_TARGET, true).await?;
    assert_eq!(export.streams.len(), 3);
    assert_eq!(export.event_count(), 0);
    let counts = export.category_counts();
    assert!(
        counts.iter().all(|count| count.events == 0),
        "the summary must expose the zero: {counts:?}"
    );
    Ok(())
}
