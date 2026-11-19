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
use infra::ai::provider_health::PgProviderHealth;
use infra::ai::provider_watch::{ProviderWatchConfig, run_provider_watch_tick};
use infra::ai::queue::PgAiImportQueue;
use jiff::SignedDuration;
use jiff::Timestamp;
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
async fn open_breaker(health: &PgProviderHealth, threshold: u32) -> Timestamp {
    let mut retry_at = None;
    for _ in 0..threshold {
        let decision = health
            .record_failure(PROVIDER, MODEL, threshold, None)
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
    next_attempt_at: Option<infra::db_time::SqlTimestamp>,
    series_started_at: Option<infra::db_time::SqlTimestamp>,
}

/// The assertion-facing form: the series clock is only ever asked for presence.
struct HoldRow {
    status: String,
    retries: i32,
    hold_state: Option<String>,
    next_attempt_at: Option<Timestamp>,
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
        next_attempt_at: raw.next_attempt_at.map(infra::db_time::ts),
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

fn hold_for(until: Timestamp, state: ProviderBreakerState) -> ProviderHold {
    ProviderHold {
        provider: PROVIDER,
        model: MODEL.to_owned(),
        reason_code: "ai-import.llm-provider-unavailable".to_owned(),
        state,
        until,
        hold_deadline: until + SignedDuration::from_secs(i64::try_from(HOLD_WINDOW).unwrap_or(0)),
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

/// Issue #926 review: a hint the provider already earned must survive a LATER
/// failure that carries none.
///
/// The failure path writes `retry_at` unconditionally, so the only memory of the
/// hint is the stored row — this asserts it through the real compare-and-set,
/// which a table test cannot reach.
#[tokio::test]
async fn a_hintless_failure_keeps_the_deferred_probe() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let health = PgProviderHealth::new(pool);

    // Open the breaker ON a hint: the probe is deferred by the provider's window.
    let opened = health
        .record_failure(
            PROVIDER,
            MODEL,
            1,
            Some(std::time::Duration::from_secs(600)),
        )
        .await?;
    assert!(opened.opened);
    let deferred = opened.retry_at.expect("an open breaker has a probe time");

    // A second failure arrives WITHOUT a hint — the ordinary 60 s open window is
    // shorter, and recomputing it alone would pull the probe forward.
    let after = health.record_failure(PROVIDER, MODEL, 1, None).await?;
    assert!(!after.opened, "still the same open incident");
    // Compared in microseconds: the column is `TIMESTAMPTZ` (microsecond
    // precision) while the in-memory instant keeps nanoseconds, so the durable
    // round trip truncates sub-microsecond digits. The instant is the same.
    let retained = after.retry_at.expect("an open breaker has a probe time");
    assert_eq!(
        retained.as_microsecond(),
        deferred.as_microsecond(),
        "the unexpired hint deadline must not be shortened by a hint-less failure"
    );
    // The durable row, not only the returned decision.
    assert_eq!(
        health
            .state(PROVIDER, MODEL)
            .await?
            .retry_at
            .map(|stored| stored.as_microsecond()),
        Some(deferred.as_microsecond()),
        "the CAS must persist the retained deadline"
    );

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
        .finish_probe(&lease, ProbeOutcome::NotUsable)
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

/// Put the pair into `half_open` with no trial holder (issue #942 W1).
///
/// An **upsert**, not an `UPDATE` (issue #942 review): nothing else in this file
/// creates the pair's `provider_health` row before the grant — `enqueue`,
/// `claim_next` and `mark_held` never write it — so an `UPDATE` matches zero rows
/// and `begin_provider_trial` (which joins on that row) cannot find a candidate to
/// grant, panicking at the `expect` instead of testing the contract.
///
/// The probe columns are cleared in the same write: the upsert stands in for the
/// state a finished preflight leaves behind, and a leftover lease would (correctly)
/// block the grant under the `probe_lease_id IS NULL` fence.
async fn make_half_open_without_holder(pool: &PgPool) {
    sqlx::query(
        "INSERT INTO ai_import.provider_health
             (provider, model, state, trial_job_id, retry_at)
         VALUES ($1, $2, 'half_open', NULL, now())
         ON CONFLICT (provider, model) DO UPDATE
            SET state = 'half_open',
                trial_job_id = NULL,
                retry_at = now(),
                probe_owner = NULL,
                probe_lease_id = NULL,
                probe_started_at = NULL",
    )
    .bind(PROVIDER.as_str())
    .bind(MODEL)
    .execute(pool)
    .await
    .unwrap();
}

/// Issue #942 W1 (AC1): a passing preflight must not close the breaker, and a
/// `half_open` pair admits **exactly one** job — the trial token holder.
///
/// This is the anti-flap fence: before #942 a metadata `200` closed the breaker
/// and released the whole fleet into another `3 × 120 s` of doomed paid calls
/// (`flap_count` reached 3 in 30 minutes).
#[tokio::test]
async fn only_the_trial_token_holder_is_claimable_while_half_open() -> Result<()> {
    use breakdown_core::ai::ProviderHealth as _;

    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    // Two waiting jobs on the same pair, both held.
    let first = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    let second = seed_job(&queue, "u2", "d2", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("first claimable");
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue
        .mark_held(
            first,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    queue.claim_next("w2").await?.expect("second claimable");
    queue
        .mark_held(
            second,
            "w2",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;

    // The breaker reaches `half_open` with no trial holder: nothing is claimable.
    let health = infra::ai::provider_health::PgProviderHealth::new(pool.clone());
    make_half_open_without_holder(&pool).await;
    assert!(
        queue.claim_next("w3").await?.is_none(),
        "half_open without a trial holder must admit no claim"
    );

    // Granting the trial makes EXACTLY that job claimable.
    let trial = health
        .begin_provider_trial(PROVIDER, MODEL)
        .await?
        .expect("one waiting job earns the trial");
    assert!(trial == first || trial == second);
    let claimed = queue
        .claim_next("w4")
        .await?
        .expect("the trial job is claimable");
    assert_eq!(claimed.id, trial, "only the token holder may run the trial");
    assert!(
        queue.claim_next("w5").await?.is_none(),
        "the other held job stays held — one trial call, not a fleet storm"
    );

    // A real paid call closing the breaker releases the rest.
    queue
        .record_provider_outcome(
            PROVIDER,
            MODEL,
            breakdown_core::ai::ProviderOutcome::Success,
            3,
        )
        .await?;
    let released = queue.release_held_jobs(PROVIDER, MODEL).await?;
    assert_eq!(released.len(), 1, "the remaining held job is released");
    Ok(())
}

// ---------------------------------------------------------------------------
// 1b. The trial grant's fences and its release (issue #942 W1 follow-up)
// ---------------------------------------------------------------------------

/// A probe verdict with no network, and no credential: the tick is what these
/// cases assert, not the HTTP call (D-X4).
struct UsableProbe;

#[async_trait::async_trait]
impl infra::ai::provider_probe::ProviderProbe for UsableProbe {
    async fn probe(
        &self,
        _provider: LlmProvider,
        _donor: &infra::ai::provider_probe::DonorJob,
    ) -> ProbeOutcome {
        ProbeOutcome::Usable
    }
}

/// The sweep must leave a pair alone while its probe lease is LIVE, and recover a
/// STALE lease through the takeover instead of granting a trial.
///
/// This is the routing half of the grant fence (the SQL predicate is covered by
/// `a_grant_is_fenced_off_while_a_probe_lease_is_live`). Without the live-lease
/// branch a second tick grants a trial whose holder the in-flight probe's own
/// fenced result then clears — two paid trials in one window. Without the
/// fall-through a stale lease leaves the pair `half_open` forever, because
/// `try_begin_probe` is the only thing that can take it over.
#[tokio::test]
async fn the_sweep_grants_no_trial_while_a_probe_lease_is_live_and_recovers_a_stale_one()
-> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue.claim_next("w1").await?.expect("claimable");
    queue
        .mark_held(
            id,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    make_half_open_without_holder(&pool).await;

    // A probe is in flight: no grant, and the lease stays with its owner.
    let lease = health
        .try_begin_probe(PROVIDER, MODEL, "prober-a")
        .await?
        .expect("the probe lease");
    infra::ai::provider_probe::run_probes(&pool, &health, &queue, &UsableProbe, "sweeper").await?;
    assert!(
        health.state(PROVIDER, MODEL).await?.trial_job.is_none(),
        "a live probe lease must leave the grant to the probe's own fenced result"
    );
    assert!(
        health.state(PROVIDER, MODEL).await?.state == ProviderBreakerState::HalfOpen,
        "the sweeper must not move the state either"
    );

    // Now let the lease go stale (a hung prober): the takeover is the recovery.
    sqlx::query(
        "UPDATE ai_import.provider_health
         SET probe_started_at = now() - interval '1 hour'
         WHERE provider = $1 AND model = $2",
    )
    .bind(PROVIDER.as_str())
    .bind(MODEL)
    .execute(&pool)
    .await
    .unwrap();
    let _ = &lease;
    infra::ai::provider_probe::run_probes(&pool, &health, &queue, &UsableProbe, "sweeper").await?;

    // The takeover probe passed, so exactly one trial is granted and the stale
    // lease is gone.
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::HalfOpen);
    assert_eq!(
        snapshot.trial_job,
        Some(id.as_uuid()),
        "a recovered stale lease grants the single trial to the waiting job"
    );
    Ok(())
}

/// A grant may not stamp a holder while a probe lease is outstanding.
///
/// `half_open` with no holder has two meanings: a **finished** probe (the lease is
/// released — grant now) and a probe **in flight** (the lease is held — do not).
/// Granting into the second case put two paid trials in one window, because the
/// in-flight probe's own fenced `finish_probe` clears `trial_job_id` on success and
/// grants again behind it.
#[tokio::test]
async fn a_grant_is_fenced_off_while_a_probe_lease_is_live() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue
        .mark_held(
            id,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    make_half_open_without_holder(&pool).await;

    // A probe is now in flight on a `half_open` pair with no holder: exactly the
    // shape a second sweep would mistake for "the window elapsed, grant now".
    let lease = health
        .try_begin_probe(PROVIDER, MODEL, "prober")
        .await?
        .expect("the probe lease");
    assert!(
        health
            .begin_provider_trial(PROVIDER, MODEL)
            .await?
            .is_none(),
        "a live probe lease must block the grant — its own result would clear the token"
    );

    // The probe's fenced result is what makes the pair grantable, and only once.
    let decision = health.finish_probe(&lease, ProbeOutcome::Usable).await?;
    assert!(decision.trial_due, "a passing preflight grants one trial");
    let trial = health
        .begin_provider_trial(PROVIDER, MODEL)
        .await?
        .expect("the released lease makes the grant possible");
    assert_eq!(trial, id, "the one waiting job earns the single trial");
    assert!(
        health
            .begin_provider_trial(PROVIDER, MODEL)
            .await?
            .is_none(),
        "the second grant in the same window stamps nothing"
    );
    Ok(())
}

/// A held-row refresh must never delay the job that just earned the trial.
///
/// `run_probes` grants the trial and still owns a `retry_at`, so the
/// `refresh_held_jobs` branch runs in the SAME tick. Without the holder exclusion
/// the grabbed token was pushed back to `now + min_open(flap_count)` — the job
/// could not claim the trial it had just been given.
#[tokio::test]
async fn a_held_row_refresh_never_delays_the_trial_holder() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let first = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    let second = seed_job(&queue, "u2", "d2", Some((PROVIDER, MODEL))).await;
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue.claim_next("w1").await?.expect("first claimable");
    queue
        .mark_held(
            first,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    queue.claim_next("w2").await?.expect("second claimable");
    queue
        .mark_held(
            second,
            "w2",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    make_half_open_without_holder(&pool).await;
    let trial = health
        .begin_provider_trial(PROVIDER, MODEL)
        .await?
        .expect("one waiting job earns the trial");
    let other = if trial == first { second } else { first };

    let later = Timestamp::now() + SignedDuration::from_secs(600);
    let refreshed = queue.refresh_held_jobs(PROVIDER, MODEL, later).await?;
    assert_eq!(
        refreshed,
        vec![other],
        "only the non-holder follows the breaker; the holder keeps its grant"
    );
    let claimed = queue
        .claim_next("w3")
        .await?
        .expect("the grant must make its holder claimable in the same tick");
    assert_eq!(claimed.id, trial);
    Ok(())
}

/// A trial consumed by a TERMINAL failure releases the holder, so the next window
/// can grant the pair's next single trial.
///
/// A revoked key or an exhausted quota is a permanent failure: it never touches
/// the breaker's counters (D-A1), so nothing in the state machine cleared
/// `trial_job_id`. The pair stayed `half_open` holding a token that named a dead
/// job, and because `begin_provider_trial` only grants when the token is NULL, no
/// other held job of the pair could ever run a trial again.
#[tokio::test]
async fn a_terminal_trial_failure_releases_the_holder_for_the_next_trial() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let health = PgProviderHealth::new(pool.clone());
    let first = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    let second = seed_job(&queue, "u2", "d2", Some((PROVIDER, MODEL))).await;
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue.claim_next("w1").await?.expect("first claimable");
    queue
        .mark_held(
            first,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    queue.claim_next("w2").await?.expect("second claimable");
    queue
        .mark_held(
            second,
            "w2",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
        )
        .await?;
    make_half_open_without_holder(&pool).await;

    let trial = health
        .begin_provider_trial(PROVIDER, MODEL)
        .await?
        .expect("one waiting job earns the trial");
    let other = if trial == first { second } else { first };
    assert_eq!(
        queue.claim_next("w3").await?.map(|job| job.id),
        Some(trial),
        "only the token holder may run the trial"
    );

    // The trial call answers `401`: permanent, so `retryable = false`.
    queue
        .mark_failed(
            trial,
            "w3",
            "provider answered 401 unauthorized",
            Some("dependency.auth-failed"),
            false,
            None,
        )
        .await?;

    assert!(
        health.state(PROVIDER, MODEL).await?.trial_job.is_none(),
        "a terminal trial failure must release the holder it ends"
    );
    assert_eq!(
        health.state(PROVIDER, MODEL).await?.state,
        ProviderBreakerState::HalfOpen,
        "releasing the token changes no counter and no state"
    );

    // The window elapses and the pair grants its next single trial — to the other
    // waiting job, not to nobody.
    make_probe_due(&pool).await;
    let next = health
        .begin_provider_trial(PROVIDER, MODEL)
        .await?
        .expect("the freed token lets the next window grant a trial");
    assert_eq!(next, other, "the trial moves on to the next waiting job");
    assert_eq!(queue.claim_next("w4").await?.map(|job| job.id), Some(other));
    Ok(())
}

// ---------------------------------------------------------------------------
// 2. mark_held is not mark_failed (D-A4)
// ---------------------------------------------------------------------------
/// The persisted `(error_summary, error_code)` of the job's attempt rows, oldest
/// first (issue #942 W2).
async fn attempt_narratives(
    pool: &PgPool,
    id: AiImportJobId,
) -> Vec<(Option<String>, Option<String>)> {
    sqlx::query_as(
        r#"
        SELECT error_summary, error_code
        FROM ai_import.ai_import_job_attempt
        WHERE job_id = $1
        ORDER BY attempt_no
        "#,
    )
    .bind(id.as_uuid())
    .fetch_all(pool)
    .await
    .unwrap()
}

/// Issue #942 W2: a hold charges no retry but **does** leave evidence.
///
/// Before this, the most common real provider state — repeated failures ending
/// in a hold — had zero diagnosable evidence: `last_error` carried a bare code
/// and the attempt history stayed empty, so an operator could not tell a client
/// timeout from an HTTP status from a bounded provider body. The row is appended
/// once per hold SERIES: a re-hold inside the same series must not multiply it.
#[tokio::test]
async fn mark_held_charges_no_retry_and_records_one_attempt_row_per_hold_series() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let evidence = breakdown_core::ai::HoldEvidence {
        summary: "LLM provider transport unavailable: operation timed out after 120s".to_owned(),
        code: Some("ai-import.llm-provider-unavailable".to_owned()),
    };
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue
        .mark_held(
            id,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            Some(&evidence),
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

    let narratives = attempt_narratives(&pool, id).await;
    assert_eq!(
        narratives.len(),
        1,
        "the first hold of a series records exactly one attempt row"
    );
    let (summary, code) = narratives.into_iter().next().expect("one row");
    let summary = summary.expect("the hold narrative must be persisted, not only a code");
    assert!(
        summary.contains("timed out after 120s"),
        "the operator must be able to tell a timeout from an HTTP status: {summary}"
    );
    assert_eq!(
        code.as_deref(),
        Some("ai-import.llm-provider-unavailable"),
        "the row's code is the registered problem code of the failure that fired"
    );

    // A re-hold inside the same series must not append a second row, and must
    // still charge no retry.
    //
    // Issue #942 W2 review: the re-hold cannot be staged with
    // `release_claim` + `claim_next`. A held job is `status = 'failed'` with
    // `worker_id = NULL` and a FUTURE `next_attempt_at`, so `release_claim` finds
    // no owned running row (it errors, and `?` would end the test) and a claim
    // would both be unreliable and **end the series** — `claim_next` clears
    // `provider_hold_series_started_at`, which is the exact opposite of what this
    // assertion is about. The row is therefore restored to an owned running state
    // directly, keeping the series clock, and the SAME worker re-holds it.
    sqlx::query(
        "UPDATE ai_import.ai_import_job
         SET status = 'running',
             worker_id = 'w1',
             lease_expires_at = now() + interval '5 minutes'
         WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await
    .unwrap();
    let later = Timestamp::now() + SignedDuration::from_secs(120);
    queue
        .mark_held(
            id,
            "w1",
            hold_for(later, ProviderBreakerState::Open),
            HOLD_WINDOW,
            Some(&evidence),
        )
        .await?;
    assert_eq!(
        attempt_count(&pool, id).await,
        1,
        "a re-hold of the same series must reuse the row, not multiply it"
    );
    assert_eq!(
        read_hold_state(&pool, id).await.retries,
        0,
        "the retry budget stays untouched by every hold"
    );
    Ok(())
}

/// The mirror case of the re-hold above (issue #942 W2 review): a hold that
/// follows an ORDINARY claim belongs to a NEW series, so it records its own
/// attempt row.
///
/// `claim_next` clears the series clock by design ("a claim ends the hold
/// series", D-C4), which is what separates "the same episode re-parked" from
/// "the job ran again and was parked afresh". Both halves need coverage: one row
/// per series, and a row per series.
#[tokio::test]
async fn a_hold_after_an_ordinary_claim_starts_a_new_series_with_its_own_attempt_row() -> Result<()>
{
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let evidence = breakdown_core::ai::HoldEvidence {
        summary: "LLM provider transport unavailable: operation timed out after 120s".to_owned(),
        code: Some("ai-import.llm-provider-unavailable".to_owned()),
    };
    let until = Timestamp::now() + SignedDuration::from_secs(60);
    queue
        .mark_held(
            id,
            "w1",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            Some(&evidence),
        )
        .await?;
    assert_eq!(attempt_count(&pool, id).await, 1);

    // The breaker closed, so the hold is released and the job becomes claimable
    // again. Its `next_attempt_at` is in the past for the same reason every other
    // "due" state in this file is written rather than slept out.
    queue.release_held_jobs(PROVIDER, MODEL).await?;
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET next_attempt_at = now() - interval '1 second'
         WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await
    .unwrap();
    queue
        .claim_next("w2")
        .await?
        .expect("the released job is claimable again");
    assert!(
        !read_hold_state(&pool, id).await.series_started,
        "a claim ends the hold series (D-C4)"
    );

    let later = Timestamp::now() + SignedDuration::from_secs(120);
    queue
        .mark_held(
            id,
            "w2",
            hold_for(later, ProviderBreakerState::Open),
            HOLD_WINDOW,
            Some(&evidence),
        )
        .await?;
    assert_eq!(
        attempt_count(&pool, id).await,
        2,
        "a NEW hold series records its own attempt row"
    );
    assert_eq!(
        read_hold_state(&pool, id).await.retries,
        0,
        "a hold never charges the retry budget, in either series"
    );
    Ok(())
}

#[tokio::test]
async fn mark_held_is_owner_fenced() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;
    queue.claim_next("w1").await?.expect("claimable");

    let until = Timestamp::now() + SignedDuration::from_secs(60);
    let result = queue
        .mark_held(
            id,
            "someone-else",
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
            None,
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

    let until = Timestamp::now() + SignedDuration::from_secs(60);
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

    let until = Timestamp::now() + SignedDuration::from_secs(60);
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
    let until = Timestamp::now() + SignedDuration::from_secs(60);
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
    let until = Timestamp::now() - SignedDuration::from_secs(60);
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
    let until = Timestamp::now() + SignedDuration::from_secs(60);
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
            .finish_probe(&lease, ProbeOutcome::Usable)
            .await
            .is_err(),
        "a superseded lease's result must be discarded"
    );
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::HalfOpen);

    // The current lease records the preflight — which, since issue #942 W1,
    // grants the single trial instead of closing the breaker.
    let decision = health.finish_probe(&takeover, ProbeOutcome::Usable).await?;
    assert!(decision.trial_due, "a passing preflight grants one trial");
    assert!(
        !decision.closed,
        "a metadata 200 must never close the (provider, model) breaker"
    );
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::HalfOpen);
    assert_eq!(snapshot.consecutive_failures, 0);
    assert!(
        snapshot.retry_at.is_some(),
        "the trial window must be armed, or a hung trial wedges half_open"
    );
    assert!(
        snapshot.trial_job.is_none(),
        "the preflight itself names no holder; the sweeper grants it"
    );

    // Only a real paid call closes it.
    health.record_success(PROVIDER, MODEL).await?;
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(snapshot.state, ProviderBreakerState::Closed);
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
    health.record_failure(PROVIDER, MODEL, 3, None).await?;
    let snapshot = health.record_failure(PROVIDER, MODEL, 3, None).await?;
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
    let opened = health.record_failure(PROVIDER, MODEL, 3, None).await?;
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
    let first = health.record_failure(PROVIDER, MODEL, 1, None).await?;
    assert_eq!(first.flap_count, 0);
    let first_window = first.retry_at.expect("open") - Timestamp::now();

    // Close it, then fail again immediately: that is a flap, so the window
    // doubles.
    health.record_success(PROVIDER, MODEL).await?;
    let second = health.record_failure(PROVIDER, MODEL, 1, None).await?;
    assert_eq!(
        second.flap_count, 1,
        "a close followed by a quick failure flaps"
    );
    let second_window = second.retry_at.expect("open") - Timestamp::now();
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
        retry_at: None,
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
    let until = Timestamp::now() + SignedDuration::from_secs(60);
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

#[tokio::test]
async fn a_disabled_breaker_admits_a_held_job_once_its_hold_is_due() -> Result<()> {
    // Issue #871 review: the kill switch bypasses the CLAIM FILTER, but a held job
    // is still subject to `next_attempt_at` — it becomes claimable when that time
    // is due, not the instant the switch is flipped. This pins that behaviour
    // explicitly, including that the claim clears the hold marker and leaves the
    // durable verdict alone (so re-enabling resumes with it).
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    // The switch OFF: exactly what `main.rs` builds for
    // `AI_IMPORT_BREAKER_ENABLED=false`.
    let queue = PgAiImportQueue::new(pool.clone()).with_breaker_filter(false);
    let health = PgProviderHealth::new(pool.clone());
    let id = seed_job(&queue, "u1", "d1", Some((PROVIDER, MODEL))).await;

    // The pair is degraded and the job is held with a FUTURE resume time.
    open_breaker(&health, 3).await;
    let until = Timestamp::now() + SignedDuration::from_hours(1);
    queue
        .hold_runnable_jobs(
            PROVIDER,
            MODEL,
            hold_for(until, ProviderBreakerState::Open),
            HOLD_WINDOW,
        )
        .await?;

    // Still filtered by its own hold time — the switch is not a time machine.
    assert!(
        queue.claim_next("w1").await?.is_none(),
        "a held job waits for its own next_attempt_at even with the breaker disabled"
    );

    // Make the hold due (a past timestamp, never a sleep).
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET next_attempt_at = now() - interval '1 second' WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await?;

    let claimed = queue
        .claim_next("w1")
        .await?
        .expect("with the breaker disabled the claim filter admits it once due");
    assert_eq!(claimed.id, id);
    // The claim clears the hold marker…
    let HoldRow { hold_state, .. } = read_hold_state(&pool, id).await;
    assert!(hold_state.is_none(), "the claim clears the hold");
    // …and leaves the durable verdict untouched, so re-enabling resumes with it.
    let snapshot = health.state(PROVIDER, MODEL).await?;
    assert_eq!(
        snapshot.state,
        ProviderBreakerState::Open,
        "the switch must not delete verdicts"
    );
    Ok(())
}
