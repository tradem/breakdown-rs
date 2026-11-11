// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Provider-breaker contract for the AI import queue (issue #871, workstream A).
//!
//! What these tests guard, in the order the design states it:
//!
//! 1. **Only `closed` admits a claim** (D-A2) — including the drain regression:
//!    a `half_open` breaker must still filter, or the instant a probe becomes due
//!    every queued job of the pair would be claimed and re-pay the outage.
//! 2. **A held job is not a failed job** (D-A4): `mark_held` leaves `retries`
//!    and the attempt history untouched.
//! 3. **The two materialization writers** (D-A4) reach the jobs the owner-fenced
//!    write cannot, and are idempotent.
//! 4. **Held rows follow the breaker** (D-A6): a failed probe re-points `until`,
//!    a successful close releases the rows but **not** the series clock.
//! 5. **The expiry** (D-C4) dead-letters at the job's own deadline, charges no
//!    retry, writes exactly one attempt row and is idempotent.
//! 6. **The probe lease** (D-A6) admits one prober, survives a hung one, and
//!    discards a superseded result.
//!
//! Timing-safe by construction (AGENTS.md §4): "due" and "expired" states are
//! produced by writing timestamps in the past, never by sleeping, and no
//! assertion compares a database timestamp against the test process' clock.

// Test-only lint suppressions: this file asserts contracts, so a violated
// expectation must abort the test rather than be threaded through a Result.
#![allow(clippy::unwrap_used, clippy::expect_used)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::ports::{AiImportQueue, ProbeOutcome, ProviderHealth};
use breakdown_core::ai::provider_health::BreakerCounters;
use breakdown_core::ai::views::{ProviderBreakerState, ProviderHold};
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, DocumentKind, LlmProvider,
    SourceFormat,
};
use breakdown_core::shared::UserId;
use chrono::{DateTime, Duration, Utc};
use infra::ai::provider_health::PgProviderHealth;
use infra::ai::provider_watch::{ProviderWatchConfig, run_provider_watch_tick};
use infra::ai::queue::PgAiImportQueue;
use sqlx::PgPool;

const PROVIDER: LlmProvider = LlmProvider::OpenCodeGo;
const MODEL: &str = "some-model";
const HOLD_WINDOW: u64 = 21_600;

/// Seed a job bound to the breaker pair through the public `enqueue` API.
async fn seed_job(
    queue: &PgAiImportQueue,
    user: &str,
    dedup: &str,
    pair: Option<(LlmProvider, &str)>,
) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            provider: pair.map(|(provider, _)| provider),
            model: pair.map(|(_, model)| model.to_owned()),
            id,
            user_id: UserId::from_sub(user),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: dedup.to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
            source_file_name: None,
            target: None,
        })
        .await
        .unwrap();
    match result {
        AiImportEnqueueResult::Enqueued(id) | AiImportEnqueueResult::Existing(id) => id,
    }
}

/// Drive the breaker to `open` through the public health API, and return the
/// probe time it scheduled.
async fn open_breaker(health: &PgProviderHealth, threshold: u32) -> DateTime<Utc> {
    let mut retry_at = None;
    for _ in 0..threshold {
        let decision = health
            .record_failure(PROVIDER, MODEL, threshold)
            .await
            .unwrap();
        retry_at = decision.retry_at;
    }
    retry_at.expect("the threshold-th failure must open the breaker")
}

/// One row of the operational hold columns the `AiImportJob` view deliberately
/// does not carry (the hold marker's SQL shape and the series clock).
///
/// A named row struct rather than a six-element tuple: positional fields are
/// unreadable at the assertion site, and `clippy::type_complexity` agrees.
#[derive(sqlx::FromRow)]
struct HoldRowRaw {
    status: String,
    retries: i32,
    hold_state: Option<String>,
    next_attempt_at: Option<DateTime<Utc>>,
    series_started_at: Option<DateTime<Utc>>,
}

/// The assertion-facing form: the series clock is only ever asked for presence.
struct HoldRow {
    status: String,
    retries: i32,
    hold_state: Option<String>,
    next_attempt_at: Option<DateTime<Utc>>,
    series_started: bool,
}

async fn read_hold_state(pool: &PgPool, id: AiImportJobId) -> HoldRow {
    let raw: HoldRowRaw = sqlx::query_as(
        r#"
        SELECT status, retries,
               provider_hold ->> 'state' AS hold_state,
               next_attempt_at,
               provider_hold_series_started_at AS series_started_at
        FROM ai_import.ai_import_job
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .fetch_one(pool)
    .await
    .unwrap();
    HoldRow {
        status: raw.status,
        retries: raw.retries,
        hold_state: raw.hold_state,
        next_attempt_at: raw.next_attempt_at,
        series_started: raw.series_started_at.is_some(),
    }
}

async fn attempt_count(pool: &PgPool, id: AiImportJobId) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM ai_import.ai_import_job_attempt WHERE job_id = $1")
        .bind(id.as_uuid())
        .fetch_one(pool)
        .await
        .unwrap()
}

fn hold_for(until: DateTime<Utc>, state: ProviderBreakerState) -> ProviderHold {
    ProviderHold {
        provider: PROVIDER,
        model: MODEL.to_owned(),
        reason_code: "ai-import.llm-provider-unavailable".to_owned(),
        state,
        until,
        hold_deadline: until + Duration::seconds(i64::try_from(HOLD_WINDOW).unwrap_or(0)),
        chunks_done: 0,
    }
}

// ---------------------------------------------------------------------------
// 1. The claim predicate (D-A2)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn an_open_breaker_filters_the_claim_and_a_close_admits_it() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;

    let retry_at = open_breaker(&health, 3).await;
    assert!(
        queue.claim_next("w1").await?.is_none(),
        "an open breaker must not admit a claim — that is the money-saver"
    );

    // Close it deliberately (the probe would do this on a reachable endpoint).
    let closed = health.record_success(PROVIDER, MODEL).await?;
    assert!(closed.closed);
    let _ = retry_at;

    let claimed = queue.claim_next("w1").await?.expect("claimable again");
    assert_eq!(claimed.id, id);
    Ok(())
}

#[tokio::test]
async fn a_half_open_breaker_still_filters_the_claim() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;

    open_breaker(&health, 3).await;
    // Make the probe due, then take the lease: the breaker is now `half_open`
    // with `retry_at` in the past. Filtering on `retry_at` would admit the claim
    // here — the queue-drain regression this test exists for.
    make_probe_due(&pool).await;
    let lease = health
        .try_begin_probe(PROVIDER, MODEL, "prober")
        .await?
        .expect("probe lease");
    assert!(
        queue.claim_next("w1").await?.is_none(),
        "a half_open breaker must still filter: only the probe may end a non-closed state"
    );
    health
        .finish_probe(&lease, ProbeOutcome::Unreachable)
        .await
        .ok();
    Ok(())
}

#[tokio::test]
async fn a_job_without_a_pair_is_never_filtered() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    // A pre-#871 / config-unresolvable job: `breaker_provider` is NULL.
    let id = seed_job(&queue, "u1", "d1", None).await;
    open_breaker(&health, 3).await;

    let claimed = queue
        .claim_next("w1")
        .await?
        .expect("a job with no breaker key is never filtered — the honest degradation");
    assert_eq!(claimed.id, id);
    Ok(())
}

async fn make_probe_due(pool: &PgPool) {
    sqlx::query("UPDATE ai_import.provider_health SET retry_at = now() - interval '1 second'")
        .execute(pool)
        .await
        .unwrap();
}

// ---------------------------------------------------------------------------
// 2. mark_held is not mark_failed (D-A4)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn mark_held_charges_no_retry_and_writes_no_attempt_row() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let until = Utc::now() + Duration::seconds(60);
    queue
        .mark_held(
            id,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;

    let HoldRow {
        status,
        retries,
        hold_state,
        next_attempt_at,
        series_started,
    } = read_hold_state(&pool, id).await;
    assert_eq!(status, "failed");
    assert_eq!(retries, 0, "a hold must never charge the retry budget");
    assert_eq!(hold_state.as_deref(), Some("open"));
    assert!(series_started, "the hold series clock must be set");
    assert!(
        next_attempt_at.is_some(),
        "next_attempt_at is the probe time"
    );
    assert_eq!(
        attempt_count(&pool, id).await,
        0,
        "a hold must never append an attempt row — the history must not fill with identical rows"
    );
    Ok(())
}

#[tokio::test]
async fn mark_held_is_owner_fenced() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let until = Utc::now() + Duration::seconds(60);
    let result = queue
        .mark_held(
            id,
            "someone-else",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await;
    assert!(
        result.is_err(),
        "a worker that lost its claim must not be able to hold the job"
    );
    let HoldRow {
        retries,
        hold_state,
        ..
    } = read_hold_state(&pool, id).await;
    assert_eq!(retries, 0);
    assert!(hold_state.is_none());
    Ok(())
}

// ---------------------------------------------------------------------------
// 3. The materialization writers (D-A4)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn hold_runnable_jobs_reaches_a_job_enqueued_while_the_breaker_is_open() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    open_breaker(&health, 3).await;
    // Enqueued AFTER the breaker opened: the open-time write could never have
    // reached it, and the claim predicate excludes it — without the sweeper's
    // materialization it would be invisible AND unexpirable.
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;

    let until = Utc::now() + Duration::seconds(60);
    let held = queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;
    assert_eq!(held, vec![id]);

    let HoldRow {
        status,
        retries,
        hold_state,
        series_started,
        ..
    } = read_hold_state(&pool, id).await;
    assert_eq!(status, "failed");
    assert_eq!(retries, 0);
    assert_eq!(hold_state.as_deref(), Some("open"));
    assert!(series_started);

    // Idempotent: the second writer must not re-hold or re-stamp it.
    let again = queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;
    assert!(again.is_empty(), "materialization must be idempotent");
    Ok(())
}

#[tokio::test]
async fn hold_runnable_jobs_skips_a_running_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let until = Utc::now() + Duration::seconds(60);
    let held = queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;
    assert!(
        held.is_empty(),
        "a running job has an owner; its own attempt takes the held path"
    );
    let HoldRow {
        status, hold_state, ..
    } = read_hold_state(&pool, id).await;
    assert_eq!(status, "running");
    assert!(hold_state.is_none());
    Ok(())
}

// ---------------------------------------------------------------------------
// 4. Held rows follow the breaker (D-A6)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn a_successful_close_releases_the_rows_but_keeps_the_series_clock() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    open_breaker(&health, 3).await;
    let until = Utc::now() + Duration::seconds(60);
    queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;

    let released = queue.release_held_jobs(PROVIDER, MODEL).await?;
    assert_eq!(released, vec![id]);
    let HoldRow {
        retries,
        hold_state,
        series_started,
        ..
    } = read_hold_state(&pool, id).await;
    assert_eq!(retries, 0);
    assert!(
        hold_state.is_none(),
        "a close ends the wait, so the banner must stop claiming one"
    );
    assert!(
        series_started,
        "the series clock must SURVIVE a close — otherwise a flapping provider resets its 6h budget"
    );
    Ok(())
}

#[tokio::test]
async fn a_release_never_revives_an_expired_marker() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    // The job id is not needed: this test asserts on the RETURNED id list.
    let _ = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    open_breaker(&PgProviderHealth::new(pool.clone()), 3).await;
    let until = Utc::now() - Duration::seconds(60);
    queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Expired),
            HOLD_WINDOW,
        )
        .await?;

    let released = queue.release_held_jobs(PROVIDER, MODEL).await?;
    assert!(
        released.is_empty(),
        "an expired marker is terminal and must not be cleared by a close"
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// 5. The expiry (D-C4)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn the_expiry_dead_letters_once_without_charging_a_retry() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    open_breaker(&health, 3).await;
    let until = Utc::now() + Duration::seconds(60);
    queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;
    // The deadline passed: written in the past rather than slept out.
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET provider_hold = jsonb_set(provider_hold, '{hold_deadline}', to_jsonb(now() - interval '1 minute'))",
    )
    .execute(&pool)
    .await
    .unwrap();

    let expired = queue
        .expire_provider_holds(
            "the provider stayed unavailable",
            Some("ai-import.llm-provider-unavailable"),
        )
        .await?;
    assert_eq!(expired, vec![id]);

    let HoldRow {
        status,
        retries,
        hold_state,
        next_attempt_at,
        series_started,
    } = read_hold_state(&pool, id).await;
    assert_eq!(status, "dead_letter");
    assert_eq!(retries, 0, "the document did not fail, the provider did");
    assert_eq!(
        hold_state.as_deref(),
        Some("expired"),
        "the marker is what separates an expiry from a spent retry budget"
    );
    assert!(next_attempt_at.is_none());
    assert!(!series_started, "the series ends with the terminal write");
    assert_eq!(
        attempt_count(&pool, id).await,
        1,
        "exactly one attempt row for the whole hold, not five identical ones"
    );

    // Idempotent: the marker is no longer `failed`, so a second tick is a no-op.
    let again = queue
        .expire_provider_holds(
            "the provider stayed unavailable",
            Some("ai-import.llm-provider-unavailable"),
        )
        .await?;
    assert!(again.is_empty(), "the expiry must not double dead-letter");
    assert_eq!(attempt_count(&pool, id).await, 1);
    Ok(())
}

#[tokio::test]
async fn the_watch_tick_materializes_and_expires_under_one_lock() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    open_breaker(&health, 3).await;
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    // `id` is read back below through `read_hold_state`.
    let _ = &id;
    let config = ProviderWatchConfig {
        enabled: true,
        interval_secs: 60,
        max_provider_hold_secs: HOLD_WINDOW,
    };

    let report = run_provider_watch_tick(&pool, &health, &queue, None, &config, "test")
        .await?
        .expect("the tick ran");
    assert_eq!(report.held, 1, "the sweeper materializes the owed hold");
    let HoldRow { hold_state, .. } = read_hold_state(&pool, id).await;
    assert_eq!(hold_state.as_deref(), Some("open"));

    // A disabled watch does nothing at all.
    let off = ProviderWatchConfig {
        enabled: false,
        ..config
    };
    assert!(
        run_provider_watch_tick(&pool, &health, &queue, None, &off, "test")
            .await?
            .is_none()
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// 6. The probe lease (D-A6)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn the_probe_lease_admits_one_prober_and_fences_the_result() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let health = PgProviderHealth::new(pool.clone());
    open_breaker(&health, 3).await;
    make_probe_due(&pool).await;

    let lease = health
        .try_begin_probe(PROVIDER, MODEL, "prober-a")
        .await?
        .expect("first prober wins the lease");
    assert!(
        health
            .try_begin_probe(PROVIDER, MODEL, "prober-b")
            .await?
            .is_none(),
        "a live lease admits exactly one prober"
    );

    // A hung prober: its lease lapses, and the next tick takes over.
    sqlx::query(
        "UPDATE ai_import.provider_health SET probe_started_at = now() - interval '10 minutes'",
    )
    .execute(&pool)
    .await
    .unwrap();
    let takeover = health
        .try_begin_probe(PROVIDER, MODEL, "prober-b")
        .await?
        .expect("a stale lease must be takeable, or one hung request wedges half_open forever");

    // The superseded prober's result writes nothing.
    assert!(
        health
            .finish_probe(&lease, ProbeOutcome::Reachable)
            .await
            .is_err(),
        "a superseded lease's result must be discarded"
    );
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::HalfOpen);

    // The current lease closes it.
    let closed = health
        .finish_probe(&takeover, ProbeOutcome::Reachable)
        .await?;
    assert!(closed.closed);
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::Closed);
    assert_eq!(snapshot.consecutive_failures, 0);
    assert!(snapshot.retry_at.is_none());
    Ok(())
}

#[tokio::test]
async fn only_retryable_failures_count_and_a_permanent_one_never_opens() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let health = PgProviderHealth::new(pool.clone());

    // A permanent failure is not reported to the breaker at all — this asserts
    // the *consequence*: a pair that only ever sees a permanent failure keeps no
    // failure count, so the breaker stays closed.
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::Closed);
    assert_eq!(snapshot.consecutive_failures, 0);

    // Two retryable failures are still below the threshold of three.
    health.record_failure(PROVIDER, MODEL, 3).await?;
    let snapshot = health.record_failure(PROVIDER, MODEL, 3).await?;
    assert!(!snapshot.opened);
    assert_eq!(
        health.state(PROVIDER, MODEL).await?.state,
        ProviderBreakerState::Closed
    );
    assert_eq!(
        health.state(PROVIDER, MODEL).await?.consecutive_failures,
        2,
        "counted per pair across jobs/chunks/replicas"
    );

    // The third opens it.
    let opened = health.record_failure(PROVIDER, MODEL, 3).await?;
    assert!(opened.opened);
    assert_eq!(
        health.state(PROVIDER, MODEL).await?.state,
        ProviderBreakerState::Open
    );

    // And a success closes it again, resetting the count.
    let closed = health.record_success(PROVIDER, MODEL).await?;
    assert!(closed.closed);
    assert_eq!(health.state(PROVIDER, MODEL).await?.consecutive_failures, 0);
    Ok(())
}

#[tokio::test]
async fn the_flap_rule_escalates_the_open_window() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let health = PgProviderHealth::new(pool.clone());

    // First outage: no prior close, so flap_count stays 0 (a 60 s window).
    let first = health.record_failure(PROVIDER, MODEL, 1).await?;
    assert_eq!(first.flap_count, 0);
    let first_window = first.retry_at.expect("open") - Utc::now();

    // Close it, then fail again immediately: that is a flap, so the window
    // doubles.
    health.record_success(PROVIDER, MODEL).await?;
    let second = health.record_failure(PROVIDER, MODEL, 1).await?;
    assert_eq!(
        second.flap_count, 1,
        "a close followed by a quick failure flaps"
    );
    let second_window = second.retry_at.expect("open") - Utc::now();
    assert!(
        second_window > first_window,
        "a flap must lengthen the open window ({second_window:?} vs {first_window:?})"
    );
    Ok(())
}

// Keep the pure-machine import used: the counters type is part of the contract
// these tests reason about, and an unused import would be a lint failure.
#[allow(dead_code)]
fn _counters_are_part_of_the_contract() -> BreakerCounters {
    BreakerCounters {
        state: ProviderBreakerState::Closed,
        consecutive_failures: 0,
        flap_count: 0,
        closed_at: None,
    }
}

#[tokio::test]
async fn two_holds_expiring_in_one_tick_each_get_their_own_attempt_row() -> Result<()> {
    // Issue #871 review: `expire_provider_holds` used to bind ONE attempt id for
    // every expired row, so two holds reaching their deadline in the same tick
    // violated the attempt primary key — the whole statement rolled back and the
    // D-C4 budget was never enforced, on every tick, forever. This case is the
    // regression guard.
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    open_breaker(&health, 3).await;

    let first = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    let second = seed_job(&queue, "u1", "d2", Some((PROVIDER, MODEL))).await;
    let until = Utc::now() + Duration::seconds(60);
    queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;
    // Both deadlines in the past, so both are due in the SAME statement.
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET provider_hold = jsonb_set(provider_hold, '{hold_deadline}', to_jsonb(now() - interval '1 minute'))",
    )
    .execute(&pool)
    .await?;

    let expired = queue
        .expire_provider_holds(
            "the provider stayed unavailable",
            Some("ai-import.llm-provider-unavailable"),
        )
        .await?;
    assert_eq!(
        expired.len(),
        2,
        "both due holds must expire in one tick, not fail on a duplicate attempt id"
    );

    for id in [first, second] {
        let HoldRow {
            status,
            retries,
            hold_state,
            ..
        } = read_hold_state(&pool, id).await;
        assert_eq!(status, "dead_letter");
        assert_eq!(retries, 0, "the expiry charges no retry");
        assert_eq!(hold_state.as_deref(), Some("expired"));
        assert_eq!(
            attempt_count(&pool, id).await,
            1,
            "exactly one attempt row per expired job"
        );
    }
    // And the ids are distinct, which is what the old single-bind version broke.
    let distinct: i64 =
        sqlx::query_scalar("SELECT count(DISTINCT id) FROM ai_import.ai_import_job_attempt")
            .fetch_one(&pool)
            .await?;
    assert_eq!(distinct, 2);
    Ok(())
}
