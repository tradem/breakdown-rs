// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

//! Tier-4 regression test for the #404 numbering-projector skip path
//! (issue #407): a duplicate `SeasonCreated` for an already-projected
//! `(series_id, number)` pair under a *different* stream id hits the
//! authoritative backstop `idx_projection_season_series_number` (23505) and
//! must be savepoint-skipped — never panic-killing the worker.
//!
//! Machine-checks the "inert for reports" claim documented in
//! `backend/docs/operations/runbooks.md` → "Replaying pre-#404
//! invariant-violating events":
//!
//! 1. the duplicate is skipped (warn-logged exactly once), the checkpoint in
//!    `sierradb_event_checkpoints` advances past it, and the projection keeps
//!    the authoritative (first) row;
//! 2. follow-up events on the skipped stream are harmless by construction:
//!    their handlers are `UPDATE ... WHERE id = $1` statements that affect
//!    0 rows and cannot create a projection row;
//! 3. the projector keeps processing later events of the category stream
//!    (in-order delivery ⇒ processing a trailing event proves the checkpoint
//!    advanced past the poison event).
//!
//! The SceneShoot pair-uniqueness analog lives in
//! `scene_shoot_invariant_skip_tests.rs` (PR #406, commit b672e94).

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

use anyhow::{Result, anyhow, bail};
use breakdown_core::error::DomainError;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::season::ports::SeasonRepository as _;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, SeriesId};
use chrono::Utc;
use infra::projectors::spawn_season_projector;
use infra::queries::SeasonRepositoryImpl;
use lazy_static::lazy_static;
use tracing::field::{Field, Visit};
use tracing_subscriber::prelude::*;
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// The authoritative season-numbering backstop (issue #404). Must stay in
/// sync with `infra::projectors::invariant_skip::SEASON_NUMBER_CONSTRAINT`
/// (kept private there; asserted indirectly via the warn-constraint check).
const SEASON_NUMBER_CONSTRAINT: &str = "idx_projection_season_series_number";

/// One captured `tracing::warn!` from the season projector's skip path.
/// The constraint equality (`idx_projection_season_series_number`) is checked
/// at capture time, so only the poison id is stored.
#[derive(Debug, Clone)]
struct SkipWarn {
    season_id: Uuid,
}

lazy_static! {
    /// Global warn store shared by every test in this binary. All tests
    /// install the same subscriber chain (first `try_init` wins); counts are
    /// always filtered by the poison event's `season_id`, so parallel tests
    /// cannot cross-contaminate.
    static ref SKIP_WARNS: std::sync::Mutex<Vec<SkipWarn>> =
        std::sync::Mutex::new(Vec::new());
}

/// `tracing` visitor extracting the `season_id` (Display) and `constraint`
/// (&str) fields of the projector's skip warn.
#[derive(Default)]
struct SkipWarnVisitor {
    season_id: Option<Uuid>,
    constraint: Option<String>,
}

impl Visit for SkipWarnVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        let rendered = format!("{value:?}");
        match field.name() {
            // `%id` fields surface via Display-backed Debug formatting.
            "season_id" => {
                if let Ok(id) = rendered.parse() {
                    self.season_id = Some(id);
                }
            }
            "constraint" => self.constraint = Some(rendered),
            _ => {}
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        match field.name() {
            "season_id" => {
                if let Ok(id) = value.parse() {
                    self.season_id = Some(id);
                }
            }
            "constraint" => self.constraint = Some(value.to_string()),
            _ => {}
        }
    }
}

/// Counting layer: records every warn carrying the season-numbering
/// constraint into the global [`SKIP_WARNS`] store.
struct SkipWarnCollector;

impl<S> tracing_subscriber::layer::Layer<S> for SkipWarnCollector
where
    S: tracing::Subscriber,
{
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        if event.metadata().level() != &tracing::Level::WARN {
            return;
        }
        let mut visitor = SkipWarnVisitor::default();
        event.record(&mut visitor);
        if let (Some(season_id), Some(constraint)) = (visitor.season_id, visitor.constraint)
            && constraint == SEASON_NUMBER_CONSTRAINT
        {
            SKIP_WARNS.lock().unwrap().push(SkipWarn { season_id });
        }
    }
}

/// Install the subscriber chain once per binary; harmless if another test
/// already won (the global store still receives events).
fn init_tracing() {
    let fmt_layer = tracing_subscriber::fmt::layer().with_test_writer();
    let _ = tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,kameo_es=debug,sierradb=debug".into()),
        )
        .with(fmt_layer)
        .with(SkipWarnCollector)
        .try_init();
}

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
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
        .map_err(|e| anyhow!("EAPPEND {event_type} failed: {e}"))?;
    Ok(())
}

/// Wait until the season row is projected.
async fn await_season(repo: &SeasonRepositoryImpl, id: Uuid) -> Result<SeasonView> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        match repo.find_by_id(id).await {
            Ok(view) => return Ok(view),
            Err(DomainError::NotFound { .. }) if Instant::now() < deadline => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(DomainError::NotFound { .. }) => {
                bail!("projection lag: Season({id}) not projected within deadline");
            }
            Err(other) => return Err(anyhow!(other.to_string())),
        }
    }
}

/// Current `sierradb_event_checkpoints` rows for the season projector.
/// Streams hash into distinct partitions — each partition carries its own
/// checkpoint row with a per-partition 0-based event position.
async fn season_checkpoints(pool: &sqlx::PgPool) -> Result<Vec<(i16, i64)>> {
    Ok(sqlx::query_as(
        r#"
        SELECT partition_id, sequence
        FROM sierradb_event_checkpoints
        WHERE projection_id = $1
        ORDER BY partition_id
        "#,
    )
    .bind("season")
    .fetch_all(pool)
    .await?)
}

/// Poll until the season checkpoint rows exist and return them.
async fn await_checkpoint_exists(pool: &sqlx::PgPool) -> Result<Vec<(i16, i64)>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let rows = season_checkpoints(pool).await?;
        if !rows.is_empty() {
            return Ok(rows);
        }
        if Instant::now() >= deadline {
            bail!("projection lag: season checkpoint row not flushed within deadline");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Poll until the season checkpoints prove catch-up past the skipped poison
/// event:
///
/// * every baseline partition row is still present and did not regress
///   (monotonic per-partition sequences), and
/// * some partition row reached `sequence >= 1`. Only the duplicate stream
///   carries a second event (the harmless follow-up), so a partition at
///   sequence >= 1 can only exist after the poison event (position 0) was
///   acknowledged and flushed. Had the 23505 propagated, the worker would
///   retry forever and that partition would never flush.
async fn await_checkpoint_advanced(
    pool: &sqlx::PgPool,
    baseline: &[(i16, i64)],
) -> Result<Vec<(i16, i64)>> {
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let rows = season_checkpoints(pool).await?;
        let monotonic = baseline
            .iter()
            .all(|(p, base)| rows.iter().any(|(rp, rseq)| rp == p && rseq >= base));
        let advanced = rows.iter().any(|(_, seq)| *seq >= 1);
        if monotonic && advanced {
            return Ok(rows);
        }
        if Instant::now() >= deadline {
            bail!(
                "projection lag: season checkpoints {rows:?} show no advance past baseline {baseline:?} within deadline"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// The duplicate `SeasonCreated` (same `(series_id, number)` under a fresh
/// stream id) is savepoint-skipped; its follow-up `SeasonRenamed` is harmless;
/// the checkpoint advances past the poison event; the warn fires exactly once.
#[tokio::test]
async fn duplicate_season_number_is_skipped_and_checkpoint_advances() -> Result<()> {
    init_tracing();
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    let (redis_client, _conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_season_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = SeasonRepositoryImpl::new(pool.clone());

    let series_id = SeriesId(Uuid::now_v7());
    let season_a = Uuid::now_v7();
    let season_b = Uuid::now_v7(); // duplicate stream (poison)
    let season_c = Uuid::now_v7(); // trailing stream, distinct number

    // 1. Authoritative SeasonCreated projects (v1).
    let created_a = SeasonEvent::SeasonCreated {
        id: season_a,
        series_id,
        number: 1,
        title: Some("Season One".into()),
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &format!("season-{season_a}"),
        "SeasonCreated",
        "EMPTY",
        &encode_event(&created_a)?,
    )
    .await?;
    let view_a = await_season(&repo, season_a).await?;
    assert_eq!(view_a.version.0, 1, "authoritative season projected");

    // Baseline checkpoint (flushes are batched — poll until rows exist;
    // after the single SeasonCreated the authoritative stream's partition
    // sits at sequence 0).
    let baseline = await_checkpoint_exists(&pool).await?;

    // 2. Duplicate SeasonCreated for the same (series_id, number) pair under a
    //    fresh stream id → 23505 on idx_projection_season_series_number →
    //    savepoint-skip (no panic, no projection row).
    let duplicate = SeasonEvent::SeasonCreated {
        id: season_b,
        series_id,
        number: 1,
        title: Some("Season One Duplicate".into()),
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &format!("season-{season_b}"),
        "SeasonCreated",
        "EMPTY",
        &encode_event(&duplicate)?,
    )
    .await?;

    // 3. Follow-up event on the skipped stream: SeasonRenamed's handler is an
    //    `UPDATE ... WHERE id = $1` statement hitting 0 rows — harmless by
    //    construction; must neither error nor create/modify a projection row.
    let renamed_b = SeasonEvent::SeasonRenamed {
        id: season_b,
        title: Some("renamed on the skipped stream".into()),
        version: AggregateVersion(2),
    };
    eappend(
        &redis_client,
        &format!("season-{season_b}"),
        "SeasonRenamed",
        "0",
        &encode_event(&renamed_b)?,
    )
    .await?;

    // 4. Trailing SeasonCreated with a distinct number on a third stream.
    //    In-order delivery means it is only processed *after* the poison event
    //    was attempted and skipped — its projection proves catch-up.
    let trailing = SeasonEvent::SeasonCreated {
        id: season_c,
        series_id,
        number: 2,
        title: Some("Season Two".into()),
        version: AggregateVersion(1),
    };
    eappend(
        &redis_client,
        &format!("season-{season_c}"),
        "SeasonCreated",
        "EMPTY",
        &encode_event(&trailing)?,
    )
    .await?;
    let view_c = await_season(&repo, season_c).await?;
    assert_eq!(
        view_c.version.0, 1,
        "projector alive after the poison event"
    );

    // 5. Checkpoints advanced strictly past the baseline — the skip
    //    acknowledged the poison event (see `await_checkpoint_advanced`).
    let advanced = await_checkpoint_advanced(&pool, &baseline).await?;
    assert!(
        advanced.iter().any(|(_, seq)| *seq >= 1),
        "the poison partition must flush a checkpoint beyond the skipped event"
    );

    // 6. Exactly one warn per skipped event, filtered by the poison id.
    let deadline = Instant::now() + PROJECTION_DEADLINE;
    loop {
        let count = SKIP_WARNS
            .lock()
            .unwrap()
            .iter()
            .filter(|w| w.season_id == season_b)
            .count();
        if count >= 1 {
            // Let any duplicate warn land before asserting exactly-once —
            // a second warn emitted right after this read must still be
            // observed (issue #407 acceptance criterion 4).
            tokio::time::sleep(POLL_INTERVAL * 4).await;
            let settled = SKIP_WARNS
                .lock()
                .unwrap()
                .iter()
                .filter(|w| w.season_id == season_b)
                .count();
            assert_eq!(
                settled, 1,
                "the skip warn must fire exactly once per skipped event"
            );
            break;
        }
        if Instant::now() >= deadline {
            bail!("no skip warn for Season({season_b}) observed within deadline");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // 7. Projection keeps the authoritative row; the skipped stream created no
    //    row and its follow-up changed nothing.
    let rows_for_pair: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM projection_season
        WHERE series_id = $1 AND number = $2
        "#,
    )
    .bind(series_id.0)
    .bind(1)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        rows_for_pair, 1,
        "duplicate season number must not create a second row"
    );

    let authoritative = repo.find_by_id(season_a).await?;
    assert_eq!(
        authoritative.title.as_deref(),
        Some("Season One"),
        "authoritative row untouched by the skipped stream's follow-up"
    );

    let skipped_rows: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM projection_season WHERE id = $1
        "#,
    )
    .bind(season_b)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        skipped_rows, 0,
        "skipped duplicate stream must not be projected"
    );
    assert!(
        repo.find_by_id(season_b).await.is_err(),
        "skipped duplicate stream must not be readable via the repository"
    );

    Ok(())
}
