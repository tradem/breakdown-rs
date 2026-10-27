// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Tier-4 regression test for the #37 projector dead-letter path: a
//! permanently unprocessable event must be recorded durably in
//! `projection_dead_letter` and the projector's checkpoint must advance past
//! it — instead of the pre-#37 infinite supervisor restart loop.
//!
//! Replicates the original #37 reproducer: a piece is assigned to a
//! character UUID that was never created, so the piece projector's
//! `UPDATE projection_piece SET character_id = ...` hits the
//! `projection_piece_character_id_fkey` FK (SQLSTATE 23503 — a *permanent*
//! error class). The DLQ write + checkpoint advance happen in one
//! transaction; the trailing event on the same stream proves continued
//! processing, and `ProjectorHealthRepository` is exercised as the
//! programmatic health signal.

// Test-only file: unwrap/expect/panic are allowed in test code.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

mod fixtures;

use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use breakdown_core::ops::DeadLetterEntry;
use breakdown_core::piece::events::PieceDetail;
use breakdown_core::piece::events::PieceEvent;
use breakdown_core::shared::AggregateVersion;
use chrono::Utc;
// Trait method scope for the #37 health adapter (issue #409 port split).
use breakdown_core::ops::ProjectorHealthRepository as _;
use infra::projectors::{ProjectorFlushConfig, ProjectorHealthRepository, spawn_piece_projector};
use sqlx::Row;
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(30);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// The dead-letter write happens only after the worker's retry budget is
/// exhausted — 5 attempts under backon's default exponential backoff
/// (roughly 1 s → 16 s, ~35 s per cycle, vendored pre-#37 behavior). Every
/// poll *after* the poison event must therefore use this wider deadline,
/// not [`PROJECTION_DEADLINE`].
const POISON_SETTLE: Duration = Duration::from_secs(150);

fn init_tracing() {
    use tracing_subscriber::prelude::*;
    let fmt_layer = tracing_subscriber::fmt::layer().with_test_writer();
    let _ = tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,kameo_es=debug,sierradb=debug".into()),
        )
        .with(fmt_layer)
        .try_init();
}

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload)
        .map_err(|e| anyhow::anyhow!("CBOR encode failed: {e}"))?;
    Ok(payload)
}

async fn eappend(
    redis_client: &Arc<redis::Client>,
    stream_id: &str,
    event_type: &str,
    expected_version: &str,
    payload: &[u8],
) -> Result<()> {
    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_type)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow::anyhow!("EAPPEND {event_type} failed: {e}"))?;
    Ok(())
}

/// Current piece checkpoint rows (projection_id = "piece").
async fn piece_checkpoints(pool: &sqlx::PgPool) -> Result<Vec<(i16, i64)>> {
    Ok(sqlx::query_as(
        r#"
        SELECT partition_id, sequence
        FROM sierradb_event_checkpoints
        WHERE projection_id = $1
        ORDER BY partition_id
        "#,
    )
    .bind("piece")
    .fetch_all(pool)
    .await?)
}

/// Poll until at least one piece checkpoint row exists.
async fn await_checkpoint_exists(pool: &sqlx::PgPool) -> Result<Vec<(i16, i64)>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let rows = piece_checkpoints(pool).await?;
        if !rows.is_empty() {
            return Ok(rows);
        }
        if Instant::now() >= deadline {
            bail!("projection lag: piece checkpoint row not flushed within deadline");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Piece projection row: (version, notes).
async fn piece_row(pool: &sqlx::PgPool, id: Uuid) -> Result<Option<(i64, String)>> {
    let row = sqlx::query(
        r#"
        SELECT version, notes
        FROM projection_piece
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| (r.get::<i64, _>("version"), r.get::<String, _>("notes"))))
}

async fn await_piece(pool: &sqlx::PgPool, id: Uuid, min_version: i64) -> Result<(i64, String)> {
    await_piece_within(pool, id, min_version, PROJECTION_DEADLINE).await
}

async fn await_piece_within(
    pool: &sqlx::PgPool,
    id: Uuid,
    min_version: i64,
    deadline_budget: Duration,
) -> Result<(i64, String)> {
    let deadline = Instant::now() + deadline_budget;
    loop {
        if let Some((version, notes)) = piece_row(pool, id).await?
            && version >= min_version
        {
            return Ok((version, notes));
        }
        if Instant::now() >= deadline {
            bail!(
                "projection lag: piece {id} did not reach version >= {min_version} within deadline"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Poll until exactly one DLQ row exists for the piece projector and return it.
async fn await_dead_letter(
    repo: &ProjectorHealthRepository,
    piece_id: Uuid,
) -> Result<DeadLetterEntry> {
    let deadline = Instant::now() + POISON_SETTLE;
    loop {
        let entries: Vec<DeadLetterEntry> = repo.list_dead_letters(100).await?;
        let matches: Vec<&DeadLetterEntry> = entries
            .iter()
            .filter(|e| e.projection_id == "piece" && e.stream_id.contains(&piece_id.to_string()))
            .collect();
        if matches.len() == 1 {
            return Ok(matches[0].clone());
        }
        if Instant::now() >= deadline {
            bail!(
                "dead-letter lag: expected exactly 1 DLQ row for piece {piece_id}, saw {} entries after deadline",
                entries.len()
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Wait until the piece checkpoints advanced past the poison event (some
/// partition reaches `sequence >= 1` while baseline partitions stay
/// monotonic). The poison event is position 1 of the piece stream (after
/// `PieceCreated` at position 0); only a successful dead-letter + checkpoint
/// advance lets the partition flush beyond it.
async fn await_checkpoint_advanced(
    pool: &sqlx::PgPool,
    baseline: &[(i16, i64)],
) -> Result<Vec<(i16, i64)>> {
    let deadline = Instant::now() + POISON_SETTLE;
    loop {
        let rows = piece_checkpoints(pool).await?;
        let monotonic = baseline
            .iter()
            .all(|(p, base)| rows.iter().any(|(rp, rseq)| rp == p && rseq >= base));
        let advanced = rows.iter().any(|(_, seq)| *seq >= 1);
        if monotonic && advanced {
            return Ok(rows);
        }
        if Instant::now() >= deadline {
            bail!(
                "projection lag: piece checkpoints {rows:?} show no advance past baseline {baseline:?} within deadline"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// A piece assigned to a never-created character (FK 23503) is dead-lettered;
/// the checkpoint advances past it; the trailing event on the same stream is
/// still processed; the health signal exposes the poison event.
#[tokio::test]
async fn fk_violation_event_is_dead_lettered_and_projector_keeps_advancing() -> Result<()> {
    init_tracing();
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    let (redis_client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_piece_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let health = ProjectorHealthRepository::new(pool.clone());

    let piece_id = Uuid::now_v7();
    let stream = format!("piece-{piece_id}");

    // 1. Authoritative PieceCreated projects (v1).
    let created = PieceEvent::PieceCreated {
        id: piece_id,
        name: "Fundus-Piece".to_string(),
        category_id: None,
        season_id: None,
        notes: String::new(),
        details: Vec::new(),
        photos: Vec::new(),
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &stream,
        "PieceCreated",
        "EMPTY",
        &encode_event(&created)?,
    )
    .await?;
    let (v1, _) = await_piece(&pool, piece_id, 1).await?;
    assert_eq!(v1, 1, "piece projected");

    // Baseline checkpoint (the created stream's partition sits at 0).
    let baseline = await_checkpoint_exists(&pool).await?;

    // 2. Successful event *immediately before* the poison event — both land
    //    in the same batch transaction (flushes only fire on event-count/time
    //    checkpoints, and the poison retry loop runs before any flush check).
    //    Regression guard for the #37 review finding: the dead-letter path
    //    must commit this event's effect atomically with the DLQ row +
    //    checkpoint advance, never roll it back and skip it on replay.
    let detail = PieceDetail {
        id: Uuid::now_v7(),
        text: "pre-poison detail".into(),
        subject: None,
    };
    let detail_added = PieceEvent::PieceDetailAdded {
        id: piece_id,
        detail: detail.clone(),
        version: AggregateVersion(2),
    };
    eappend(
        &redis_client,
        &stream,
        "PieceDetailAdded",
        "0",
        &encode_event(&detail_added)?,
    )
    .await?;

    // 3. Poison event: a `PieceDetailAdded` naming a piece that was never
    //    created, so the detail INSERT violates
    //    `projection_piece_detail_piece_id_fkey` (23503, permanent).
    //    Pre-#37 this stalled the projector forever.
    let ghost_piece = Uuid::now_v7();
    let poison = PieceEvent::PieceDetailAdded {
        id: ghost_piece,
        detail: PieceDetail {
            id: Uuid::now_v7(),
            subject: None,
            text: "poison".into(),
        },
        version: AggregateVersion(3),
    };
    eappend(
        &redis_client,
        &stream,
        "PieceDetailAdded",
        "1",
        &encode_event(&poison)?,
    )
    .await?;

    // 4. Trailing event on the same stream — in-order delivery means it is
    //    only processed after the poison event was dead-lettered; proves the
    //    projector keeps advancing instead of restart-looping.
    let trailing = PieceEvent::PieceNotesUpdated {
        id: piece_id,
        notes: "after-poison".into(),
        version: AggregateVersion(4),
    };
    eappend(
        &redis_client,
        &stream,
        "PieceNotesUpdated",
        "2",
        &encode_event(&trailing)?,
    )
    .await?;
    let (v4, notes) = await_piece_within(&pool, piece_id, 4, POISON_SETTLE).await?;
    assert_eq!(v4, 4, "projector alive and advanced past the poison event");
    assert_eq!(notes, "after-poison");

    // 4. Durable dead-letter record with full diagnostics.
    // The dead-letter row is keyed by the STREAM (the real piece), not by the
    // ghost id inside the poison payload.
    let entry = await_dead_letter(&health, piece_id).await?;
    assert_eq!(entry.event_name, "PieceDetailAdded");
    assert_eq!(
        entry.sqlstate.as_deref(),
        Some("23503"),
        "FK violation SQLSTATE recorded"
    );
    assert!(
        entry
            .constraint_name
            .as_deref()
            .is_some_and(|c| c.contains("piece_id")),
        "FK constraint recorded, got {:?}",
        entry.constraint_name
    );
    assert!(entry.error_message.contains("23503"));
    assert!(entry.attempts >= 1);

    // 5b. Regression (issue #37 review): the successful unflushed event
    //     before the poison event must have been committed atomically with
    //     the dead-letter row + checkpoint advance — the pre-#37-review
    //     full-batch rollback would have lost it while the checkpoint jumped
    //     past it, and replay would never re-apply it.
    let detail_rows: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM projection_piece_detail
        WHERE piece_id = $1 AND detail_id = $2
        "#,
    )
    .bind(piece_id)
    .bind(detail.id)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        detail_rows, 1,
        "the pre-poison unflushed event's effect must survive the dead-letter path"
    );

    // 5. Checkpoints advanced strictly past the poison event — without the
    //    dead-letter path the worker would retry forever and never flush.
    let advanced = await_checkpoint_advanced(&pool, &baseline).await?;
    assert!(
        advanced.iter().any(|(_, seq)| *seq >= 1),
        "the poison partition must flush a checkpoint beyond the dead-lettered event"
    );

    // 6. The dead-lettered event's effect did NOT land (the assignment to the
    //    ghost character was skipped, not applied with NULL-fallback).
    let (_, final_notes) = piece_row(&pool, piece_id)
        .await?
        .unwrap_or((0, String::new()));
    assert_eq!(final_notes, "after-poison");

    // 7. Health signal aggregates: one dead letter total, checkpoint progress
    //    queryable per projection.
    let count = health.dead_letter_count().await?;
    assert!(
        count >= 1,
        "dead_letter_count must surface at least the poison event"
    );
    let progress = health.checkpoint_progress().await?;
    assert!(
        progress
            .iter()
            .any(|c| c.projection_id == "piece" && c.sequence >= 1),
        "checkpoint progress must show the piece projector past the poison event"
    );

    Ok(())
}

/// A Sierra message whose payload cannot be decoded (corruption) is
/// dead-lettered at the *stream* layer (issue #411): the DLQ row carries the
/// raw message coordinates, the checkpoint advances past it, and the
/// projector continues with the next event instead of restart-looping on the
/// malformed message forever.
#[tokio::test]
async fn undecodable_sierra_message_is_dead_lettered_and_projector_keeps_advancing() -> Result<()> {
    init_tracing();
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    let (redis_client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_piece_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let health = ProjectorHealthRepository::new(pool.clone());

    let piece_id = Uuid::now_v7();
    let stream = format!("piece-{piece_id}");

    // 1. Corrupt message: SierraDB stores the payload opaque, so EAPPEND
    //    accepts bytes that no CBOR decoder can read (break marker at the
    //    start). The stream's decode fails before any worker involvement —
    //    pre-#411 this restart-looped the projector forever.
    eappend(
        &redis_client,
        &stream,
        "PieceCreated",
        "EMPTY",
        b"\xff\xff\xff\xff",
    )
    .await?;

    // 2. Trailing valid event on the same stream — only processed after the
    //    corrupt message was dead-lettered; proves the projector keeps
    //    advancing.
    let created = PieceEvent::PieceCreated {
        id: piece_id,
        name: "Fundus-Piece".to_string(),
        category_id: None,
        season_id: None,
        notes: String::new(),
        details: Vec::new(),
        photos: Vec::new(),
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &stream,
        "PieceCreated",
        "0",
        &encode_event(&created)?,
    )
    .await?;
    let (v1, _) = await_piece_within(&pool, piece_id, 1, POISON_SETTLE).await?;
    assert_eq!(
        v1, 1,
        "projector alive and advanced past the corrupt message"
    );

    // 3. Durable DLQ row with the raw message coordinates and error.
    let deadline = Instant::now() + POISON_SETTLE;
    let entry = loop {
        let entries: Vec<DeadLetterEntry> = health.list_dead_letters(100).await?;
        let matches: Vec<&DeadLetterEntry> = entries
            .iter()
            .filter(|e| e.projection_id == "piece" && e.stream_id.contains(&piece_id.to_string()))
            .collect();
        if matches.len() == 1 {
            break matches[0].clone();
        }
        if Instant::now() >= deadline {
            bail!(
                "dead-letter lag: expected exactly 1 DLQ row for piece {piece_id}, saw {} entries",
                entries.len()
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    };
    assert_eq!(entry.event_name, "PieceCreated");
    assert!(
        entry.error_message.contains("deserialize"),
        "decode failure recorded, got: {}",
        entry.error_message
    );
    assert!(
        entry.sqlstate.is_none(),
        "a decode failure carries no SQLSTATE"
    );

    // 4. Checkpoints advanced past the corrupt message's partition position.
    let deadline = Instant::now() + POISON_SETTLE;
    loop {
        let rows = piece_checkpoints(&pool).await?;
        if rows.iter().any(|(_, seq)| *seq >= 1) {
            break;
        }
        if Instant::now() >= deadline {
            bail!("projection lag: piece checkpoints {rows:?} never advanced past position 1");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    Ok(())
}
