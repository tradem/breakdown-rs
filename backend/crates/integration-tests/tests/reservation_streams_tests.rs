// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 integration tests for the ES-native reservation streams
//! (ADR-036, issue #586).
//!
//! Covers the issue's acceptance criteria:
//!
//! 1. **Atomicity at the write boundary**: two concurrent creates with the
//!    same `(series_id, number)` on the same adapter path — exactly one
//!    succeeds; the loser answers the registered 409 problem code *before*
//!    any aggregate append (its aggregate stream stays empty — no phantom
//!    aggregate, no event for the projector to skip).
//! 2. **Create-failure compensation**: a claim whose aggregate append fails
//!    is released (the key becomes claimable again) — no orphaned
//!    reservation on the in-process path.
//! 3. **Reaper consume**: a realized claim (aggregate stream exists) is
//!    marked `consumed` by a reaper pass while future reserves still 409.
//! 4. **Reaper release of a crash orphan**: a reserved-but-never-realized
//!    claim older than the TTL is released by `run_reaper_pass`; competitors
//!    can claim the key afterwards.
//!
//! Both a manual-create and an AI-apply-style retry converge because a claim
//! by the same `aggregate_id` never conflicts with itself (issue #182
//! mirror); test 2 pins that semantics too.

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use breakdown_core::episode::commands::CreateEpisode;
use breakdown_core::episode::events::EpisodeEvent;
use breakdown_core::episode::ports::EpisodeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::season::ports::SeasonCommands as _;
use breakdown_core::shared::{AggregateVersion, BlockId, SeriesId};
use chrono::Utc;
use infra::reservations::reaper::run_reaper_pass;
use infra::reservations::store::ReservationStore;
use kameo_es::ConnectionPool;
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

fn test_user() -> breakdown_core::shared::UserId {
    breakdown_core::shared::UserId("test-user".into())
}

fn encode_event<E: serde::Serialize>(event: &E) -> Result<Vec<u8>> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    Ok(payload)
}

/// Shared harness: SierraDB + Postgres containers, episode projector and the
/// ADR-036 reservation projector in the test profile.
async fn init() -> Result<(
    sqlx::PgPool,
    Arc<redis::Client>,
    testcontainers::ContainerAsync<testcontainers_modules::postgres::Postgres>,
    testcontainers::ContainerAsync<fixtures::SierraDbImage>,
)> {
    let (pool, pg_guard) = fixtures::spawn_postgres().await?;
    let (sierra_client, _conn, sierra_guard) = fixtures::spawn_sierradb().await?;

    let r1 = sierra_client.clone();
    let r2 = sierra_client.clone();
    let _episode_proj = infra::projectors::spawn_episode_projector(
        pool.clone(),
        r1,
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;
    let _reservation_proj = infra::projectors::spawn_reservation_projector(
        pool.clone(),
        r2,
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    Ok((pool, sierra_client, pg_guard, sierra_guard))
}

async fn store_for(sierra_client: &Arc<redis::Client>) -> Result<ReservationStore> {
    let conn = sierra_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| anyhow!("sierra connection failed: {e}"))?;
    Ok(ReservationStore::new(ConnectionPool::from(conn)))
}

/// Waits until the reservation claim row appears (or reaches `state`) in
/// `projection_number_reservation`.
async fn await_reservation_state(pool: &sqlx::PgPool, key: &str, state: &str) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    let mut interval = tokio::time::interval(POLL_INTERVAL);
    loop {
        interval.tick().await;
        if std::time::Instant::now() > deadline {
            anyhow::bail!("projection_number_reservation({key}) never reached state '{state}'");
        }
        let state_now: Option<String> = sqlx::query_scalar(
            "SELECT state FROM projection_number_reservation WHERE reservation_key = $1",
        )
        .bind(key)
        .fetch_optional(pool)
        .await?;
        if state_now.as_deref() == Some(state) {
            return Ok(());
        }
    }
}

/// Counts events on an aggregate stream via raw ESCAN (0 = absent stream).
/// Raw RESP-path ESCAN (fixtures pattern mirrors
/// `scene_shoot_invariant_skip_tests.rs`).
async fn aggregate_stream_events(
    redis_client: &Arc<redis::Client>,
    aggregate_category: &str,
    id: Uuid,
) -> Result<usize> {
    let mut conn = redis_client.get_multiplexed_async_connection().await?;
    let value: redis::Value = redis::cmd("ESCAN")
        .arg(format!("{aggregate_category}-{}", id))
        .arg("0")
        .arg("+") // end token of the sierradb range syntax (RangeValue::End)
        .arg("COUNT")
        .arg(1000u64)
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("ESCAN {aggregate_category}-{id} failed: {e}"))?;
    Ok(count_escan_events(value))
}

/// Extracts the `events` array length from an ESCAN map reply.
fn count_escan_events(value: redis::Value) -> usize {
    match &value {
        redis::Value::Map(fields) => fields.iter().find_map(|(k, v)| {
            match k {
                redis::Value::SimpleString(s) if s == "events" => {}
                _ => return None,
            }
            match v {
                redis::Value::Array(events) => Some(events.len()),
                _ => None,
            }
        }),
        _ => None,
    }
    .unwrap_or(0)
}

fn create_episode_cmd(id: Uuid, block_id: Uuid, series_id: Uuid, number: i32) -> CreateEpisode {
    CreateEpisode {
        id,
        block_id: BlockId(block_id),
        series_id: SeriesId(series_id),
        number,
        name: Some("Test Episode".into()),
    }
}

fn episode_key(series_id: Uuid, number: i32) -> String {
    infra::reservations::event::episode_number_key(series_id, number)
}

// ---------------------------------------------------------------------------
// 1. Atomicity: two concurrent creates, same (series_id, number)
// ---------------------------------------------------------------------------

/// Issue #586 AC: two concurrent creates with the same target number —
/// exactly one succeeds, the loser gets the registered 409 and its aggregate
/// stream stays empty (no scenes/rows can ever reference an unprojected
/// episode because no losing aggregate event exists to project).
#[tokio::test(flavor = "multi_thread")]
async fn concurrent_creates_same_episode_number_exactly_one_wins() -> Result<()> {
    let (_pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let block_id = Uuid::now_v7();
    let id_a = Uuid::now_v7();
    let id_b = Uuid::now_v7();

    let episodes = infra::event_store::EpisodeCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );

    let (res_a, res_b) = tokio::join!(
        episodes.create(
            test_user(),
            create_episode_cmd(id_a, block_id, series_id, 3),
        ),
        episodes.create(
            test_user(),
            create_episode_cmd(id_b, block_id, series_id, 3),
        ),
    );

    // Exactly one winner.
    match (&res_a, &res_b) {
        (Ok(_), Err(DomainError::Conflict { code, .. }))
            if code.code == "episode.number-already-exists" => {}
        (Err(DomainError::Conflict { code, .. }), Ok(_))
            if code.code == "episode.number-already-exists" => {}
        _ => anyhow::bail!(
            "expected exactly one success and one registered 409, got {res_a:?} / {res_b:?}"
        ),
    }

    // The loser never appended to its aggregate stream.
    let loser_id = match res_a {
        Ok(_) => id_b,
        Err(_) => id_a,
    };
    let loser_events = aggregate_stream_events(&sierra_client, "episode", loser_id).await?;
    let winner_id = if loser_id == id_a { id_b } else { id_a };
    let winner_events = aggregate_stream_events(&sierra_client, "episode", winner_id).await?;
    assert_eq!(
        loser_events, 0,
        "losing create must not have appended any aggregate event (ADR-036 §2)"
    );
    assert!(
        winner_events >= 1,
        "winning create must have appended EpisodeCreated"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 2. Create-failure compensation: the claim is released
// ---------------------------------------------------------------------------

/// The aggregate append fails (pre-seeded aggregate stream → version
/// conflict) after the claim won. The adapter MUST NOT release the claim in
/// that state — the claimed aggregate exists, so the key IS owned (releasing
/// would re-open the race ADR-036 closes); the claim stays held and the
/// reaper resolves it: aggregate exists ⇒ consumed ⇒ competitors keep
/// getting the registered 409. The same-aggregate retry converges (issue
/// #182 mirror) instead of conflicts.
#[tokio::test(flavor = "multi_thread")]
async fn create_failure_keeps_claim_reaper_consumes_realized_claim() -> Result<()> {
    let (pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let block_id = Uuid::now_v7();
    let stuck_id = Uuid::now_v7(); // the aggregate append will fail for this id
    let number = 7;
    let key = episode_key(series_id, number);
    let conflict = DomainError::Conflict {
        code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
        reason: "episode number already taken".into(),
    };

    // Pre-seed the FAILING aggregate's stream so
    // `EpisodeAggregate::execute(..., ExpectedVersion::Empty)` fails after
    // the reservation won.
    {
        let mut conn = sierra_client.get_multiplexed_async_connection().await?;
        let payload = encode_event(&EpisodeEvent::EpisodeCreated {
            id: stuck_id,
            block_id: BlockId(block_id),
            series_id: SeriesId(series_id),
            number,
            name: None,
            version: AggregateVersion(1),
        })?;
        let now_ms = Utc::now().timestamp_millis();
        let _: redis::Value = redis::cmd("EAPPEND")
            .arg(format!("episode-{}", stuck_id))
            .arg("EpisodeCreated")
            .arg("EXPECTED_VERSION")
            .arg("EMPTY")
            .arg("PAYLOAD")
            .arg(payload)
            .arg("TIMESTAMP")
            .arg(now_ms.to_string().as_bytes())
            .query_async(&mut conn)
            .await?;
    }

    let episodes = infra::event_store::EpisodeCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );

    // The create command claims first, then fails the aggregate append.
    let outcome = episodes
        .create(
            test_user(),
            create_episode_cmd(stuck_id, block_id, series_id, number),
        )
        .await;
    assert!(
        outcome.is_err(),
        "pre-seeded aggregate stream must make the create fail (compensation precondition)"
    );

    // Policy pin: the claim is NOT released on an unknown-append-state
    // failure — a competitor must still be blocked right away.
    {
        let store = store_for(&sierra_client).await?;
        assert!(
            store
                .reserve(&key, Uuid::now_v7(), conflict.clone())
                .await
                .is_err(),
            "a failed create with unknown append state must NOT release the claim (ADR-036 §3.2)"
        );
    }

    // …and the same-aggregate retry is recovered, not conflicted (the claim
    // holder passes through and the existing stream is addressed).
    {
        let store = store_for(&sierra_client).await?;
        let recovered = store
            .reserve(&key, stuck_id, conflict.clone())
            .await
            .expect("own-claimed retry must pass through");
        assert_eq!(recovered.aggregate_id, stuck_id);
    }

    // The reaper (TTL 0) resolves the claim against the event store: the
    // aggregate stream exists ⇒ consumed ⇒ the key stays owned forever.
    let config = infra::reservations::reaper::ReaperConfig {
        enabled: true,
        interval_secs: 300,
        claim_ttl_secs: 0,
        batch_size: 200,
    };
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let pass_store = store_for(&sierra_client).await?;
        run_reaper_pass(&pool, &pass_store, &config).await?;
        let state: Option<String> = sqlx::query_scalar(
            "SELECT state FROM projection_number_reservation WHERE reservation_key = $1",
        )
        .bind(&key)
        .fetch_optional(&pool)
        .await?;
        if state.as_deref() == Some("consumed") {
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!("reaper pass never consumed the realized claim (last state {state:?})");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // …and even post-consume, competitors keep answering the registered 409.
    {
        let store = store_for(&sierra_client).await?;
        assert!(
            store
                .reserve(&key, Uuid::now_v7(), conflict.clone())
                .await
                .is_err(),
            "post-consume reserves must keep answering 409"
        );
    }

    Ok(())
}

/// A claim by the same `aggregate_id` never conflicts with its own retry
/// (AI-apply crash-recovery convergence, issue #182 mirror via ADR-036 §2).
#[tokio::test(flavor = "multi_thread")]
async fn same_aggregate_claim_is_recovered_not_conflicted() -> Result<()> {
    let (_pool, sierra_client, _pg, _sierra) = init().await?;
    let store = store_for(&sierra_client).await?;

    let series_id = Uuid::now_v7();
    let id = Uuid::now_v7();
    let conflict = DomainError::Conflict {
        code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
        reason: "episode number already taken".into(),
    };

    let first = store
        .reserve(&episode_key(series_id, 9), id, conflict.clone())
        .await?;
    let retry = store
        .reserve(&episode_key(series_id, 9), id, conflict.clone())
        .await?;

    assert_eq!(first.claim_version, retry.claim_version);
    assert_eq!(retry.aggregate_id, id);

    // And a different aggregate on the same key still conflicts.
    let other = store
        .reserve(&episode_key(series_id, 9), Uuid::now_v7(), conflict.clone())
        .await;
    assert!(other.is_err(), "a different aggregate must lose the race");

    Ok(())
}

// ---------------------------------------------------------------------------
// 3. Reaper: consumed and released dispositions
// ---------------------------------------------------------------------------

/// A realized claim (aggregate stream exists) is marked `consumed` by a
/// reaper pass, is excluded from later reaper work, and future reserves for
/// the key still answer 409 — the number is owned by the realized aggregate
/// from here on (ADR-036 §3.2).
#[tokio::test(flavor = "multi_thread")]
async fn reaper_consumes_a_realized_claim() -> Result<()> {
    let (pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let block_id = Uuid::now_v7();
    let winner_id = Uuid::now_v7();
    let number = 42;
    let key = episode_key(series_id, number);

    // Winner create (claim stays held — the domain never releases numbers).
    let episodes = infra::event_store::EpisodeCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );
    episodes
        .create(
            test_user(),
            create_episode_cmd(winner_id, block_id, series_id, number),
        )
        .await?;

    // The claim projector mirrors the held claim.
    await_reservation_state(&pool, &key, "reserved").await?;

    // Reaper pass (TTL 0 ⇒ every claim is old enough right away).
    let config = infra::reservations::reaper::ReaperConfig {
        enabled: true,
        interval_secs: 300,
        claim_ttl_secs: 0,
        batch_size: 200,
    };
    // Bounded wait: the pass resolves against the event store even when the
    // projector row lags; the loop stops when the row shows 'consumed'.
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let pool_store = store_for(&sierra_client).await?;
        run_reaper_pass(&pool, &pool_store, &config).await?;
        let state: Option<String> = sqlx::query_scalar(
            "SELECT state FROM projection_number_reservation WHERE reservation_key = $1",
        )
        .bind(&key)
        .fetch_optional(&pool)
        .await?;
        if state.as_deref() == Some("consumed") {
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "reaper pass never marked the realized claim consumed (last state {state:?})"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // A competitor's reserve still conflicts — the number is owned.
    let store = store_for(&sierra_client).await?;
    let conflict = DomainError::Conflict {
        code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
        reason: "episode number already taken".into(),
    };
    assert!(
        store
            .reserve(&key, Uuid::now_v7(), conflict.clone())
            .await
            .is_err(),
        "post-consume reserves must keep answering 409"
    );

    Ok(())
}

/// A reserved-but-never-realized claim (crash between reserve and aggregate
/// append) older than the TTL is RELEASED by the reaper; afterwards a
/// competitor create can claim the number (ADR-036 §3.2 — no orphaned
/// reservations).
#[tokio::test(flavor = "multi_thread")]
async fn reaper_releases_a_crash_orphan() -> Result<()> {
    let (pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let orphan_id = Uuid::now_v7();
    let number = 55;
    let key = episode_key(series_id, number);

    // Simulate the crash: claim reserved, no aggregate appended.
    {
        let store = store_for(&sierra_client).await?;
        store
            .reserve(
                &key,
                orphan_id,
                DomainError::Conflict {
                    code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
                    reason: "episode number already taken".into(),
                },
            )
            .await?;
    }

    // The claim projector mirrors the held claim (candidate for the reaper).
    await_reservation_state(&pool, &key, "reserved").await?;

    // A competitor must be blocked BEFORE the reaper acts.
    let store = store_for(&sierra_client).await?;
    let conflict = DomainError::Conflict {
        code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
        reason: "episode number already taken".into(),
    };
    assert!(
        store
            .reserve(&key, Uuid::now_v7(), conflict.clone())
            .await
            .is_err(),
        "the orphan claim must block competitors before the reaper releases it"
    );

    // Reaper pass (TTL 0), then the projection row must turn 'released' and
    // the competitor must be able to claim (and create) afterwards.
    let config = infra::reservations::reaper::ReaperConfig {
        enabled: true,
        interval_secs: 300,
        claim_ttl_secs: 0,
        batch_size: 200,
    };
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let pass_store = store_for(&sierra_client).await?;
        run_reaper_pass(&pool, &pass_store, &config).await?;
        let state: Option<String> = sqlx::query_scalar(
            "SELECT state FROM projection_number_reservation WHERE reservation_key = $1",
        )
        .bind(&key)
        .fetch_optional(&pool)
        .await?;
        if state.as_deref() == Some("released") {
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!("reaper pass never released the crash orphan (last state {state:?})");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // Competitor create now succeeds.
    let competitor_id = Uuid::now_v7();
    let episodes = infra::event_store::EpisodeCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );
    let competitor_create = episodes
        .create(
            test_user(),
            create_episode_cmd(competitor_id, Uuid::now_v7(), series_id, number),
        )
        .await;
    assert!(
        competitor_create.is_ok(),
        "after the orphan release the competitor create must succeed: {competitor_create:?}"
    );

    Ok(())
}

/// A claimed aggregate whose persisted create event does NOT match the claim
/// key (CodeRabbit review on this PR) must NOT be consumed — the claim is a
/// phantom (a re-driven attempt claimed a different key under the same
/// derived aggregate id) and is RELEASED: the key becomes claimable again
/// and a competitor create succeeds (ADR-036 §3.2 realized-key check).
#[tokio::test(flavor = "multi_thread")]
async fn reaper_releases_a_claim_whose_aggregate_carries_a_different_key() -> Result<()> {
    let (pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let stuck_id = Uuid::now_v7();
    let claimed_number = 80;
    let realized_number = 81; // the pre-seeded aggregate carries a DIFFERENT number
    let key = episode_key(series_id, claimed_number);

    // Pre-seed the claimed aggregate's stream with a create event whose
    // number does NOT match the claim key.
    {
        let mut conn = sierra_client.get_multiplexed_async_connection().await?;
        let payload = encode_event(&EpisodeEvent::EpisodeCreated {
            id: stuck_id,
            block_id: BlockId(Uuid::now_v7()),
            series_id: SeriesId(series_id),
            number: realized_number,
            name: None,
            version: AggregateVersion(1),
        })?;
        let now_ms = Utc::now().timestamp_millis();
        let _: redis::Value = redis::cmd("EAPPEND")
            .arg(format!("episode-{}", stuck_id))
            .arg("EpisodeCreated")
            .arg("EXPECTED_VERSION")
            .arg("EMPTY")
            .arg("PAYLOAD")
            .arg(payload)
            .arg("TIMESTAMP")
            .arg(now_ms.to_string().as_bytes())
            .query_async(&mut conn)
            .await?;
    }

    // Claim key 80 for the aggregate that actually carries number 81.
    {
        let store = store_for(&sierra_client).await?;
        store
            .reserve(
                &key,
                stuck_id,
                DomainError::Conflict {
                    code: &breakdown_core::error_registry::EPISODE_NUMBER_ALREADY_EXISTS,
                    reason: "episode number already taken".into(),
                },
            )
            .await?;
    }
    await_reservation_state(&pool, &key, "reserved").await?;

    // Reaper pass (TTL 0): the realized-key check must find the mismatch and
    // RELEASE — never consume.
    let config = infra::reservations::reaper::ReaperConfig {
        enabled: true,
        interval_secs: 300,
        claim_ttl_secs: 0,
        batch_size: 200,
    };
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let pass_store = store_for(&sierra_client).await?;
        run_reaper_pass(&pool, &pass_store, &config).await?;
        let state: Option<String> = sqlx::query_scalar(
            "SELECT state FROM projection_number_reservation WHERE reservation_key = $1",
        )
        .bind(&key)
        .fetch_optional(&pool)
        .await?;
        if state.as_deref() == Some("released") {
            break;
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "reaper must release (never consume) a claim whose aggregate carries a different key (last state {state:?})"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    // A competitor can now claim (and create) the released number.
    let competitor_id = Uuid::now_v7();
    let episodes = infra::event_store::EpisodeCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );
    let competitor_create = episodes
        .create(
            test_user(),
            create_episode_cmd(competitor_id, Uuid::now_v7(), series_id, claimed_number),
        )
        .await;
    assert!(
        competitor_create.is_ok(),
        "after the phantom release the competitor create must succeed: {competitor_create:?}"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// 4. Season / bloglockcoverage: the same guarantee for the sibling invariants
// ---------------------------------------------------------------------------

/// The other three numbering invariants ride the same store; pin season
/// `(series_id, number)` atomicy end-to-end (a second concurrent create
/// answers the registered 409 with an empty aggregate stream).
#[tokio::test(flavor = "multi_thread")]
async fn concurrent_creates_same_season_number_exactly_one_wins() -> Result<()> {
    let (_pool, sierra_client, _pg, _sierra) = init().await?;

    let series_id = Uuid::now_v7();
    let id_a = Uuid::now_v7();
    let id_b = Uuid::now_v7();

    let seasons = infra::event_store::SeasonCommandsImpl::new(
        kameo_es::command_service::CommandService::new(
            sierra_client.get_multiplexed_async_connection().await?,
        ),
    );

    let make = |id: Uuid| breakdown_core::season::commands::CreateSeason {
        id,
        series_id: SeriesId(series_id),
        number: 1,
        title: Some("A".into()),
    };

    let (res_a, res_b) = tokio::join!(
        seasons.create(test_user(), make(id_a)),
        seasons.create(test_user(), make(id_b))
    );

    match (&res_a, &res_b) {
        (Ok(_), Err(DomainError::Conflict { code, .. }))
            if code.code == "season.number-already-exists" => {}
        (Err(DomainError::Conflict { code, .. }), Ok(_))
            if code.code == "season.number-already-exists" => {}
        _ => anyhow::bail!("expected exactly one win: {res_a:?} / {res_b:?}"),
    }

    let loser = if res_a.is_ok() { id_b } else { id_a };
    let loser_events = aggregate_stream_events(&sierra_client, "season", loser).await?;
    assert_eq!(loser_events, 0, "losing season create must not append");

    Ok(())
}
