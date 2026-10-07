// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Reservation reaper (ADR-036 §3.2): crash-orphan compensation for
//! reservation claims.
//!
//! The reserve→aggregate-append gap is two non-atomic appends (SierraDB has
//! no cross-stream transaction and the two streams partition differently). A
//! crash in between leaves a `ReservationReserved` claim blocking the key
//! forever. The reaper resolves such claims **against the event store
//! itself** — never projections, so projector lag can never cause a false
//! release:
//!
//! 1. Select `reserved` claims older than the claim TTL from
//!    `projection_number_reservation` (candidates only).
//! 2. Re-read the reservation stream (authoritative `last_state`) and
//!    re-verify the TTL on the stream's own timestamp; skip candidates whose
//!    authoritative state is younger or no longer `Reserved`.
//! 3. Probe the claimed aggregate's event stream (`esver`):
//!    - exists → the claim is realized permanently (numbers/pairs are not
//!      releaseable in today's domain; ADR-036 §3.2) → append
//!      `ReservationConsumed` (CAS on the observed stream version);
//!    - absent → crash orphan → append `ReservationReleased` (CAS) — the key
//!      becomes claimable again via the re-reserve CAS path.
//!
//! A CAS miss means the claim changed in the linearizable stream between
//! read and append — never an error; the next pass resolves on the fresh
//! state. A single-instance sweep is enforced by a Postgres advisory lock.

use std::time::Duration;

use sqlx::PgPool;
use uuid::Uuid;

use breakdown_core::block::events::BlockEvent;
use breakdown_core::episode::events::EpisodeEvent;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::season::events::SeasonEvent;

use super::event::{
    ReservationKind, block_number_key, episode_number_key, scene_shoot_pair_key, season_number_key,
};
use super::store::{LifecycleVariant, ReservationStore, StreamState, decode_lifecycle};

/// Reaper configuration (env; documented with the other env contract in
/// `AGENTS.md`-adjacent docs and the runbook). Default TTL 600 s: the
/// aggregate append happens seconds after the reserve, so any older
/// un-realized claim is a crash orphan.
#[derive(Debug, Clone)]
pub struct ReaperConfig {
    pub enabled: bool,
    pub interval_secs: u64,
    pub claim_ttl_secs: u64,
    pub batch_size: i64,
}

pub fn reaper_config_from_env() -> ReaperConfig {
    let enabled = std::env::var("RESERVATION_REAPER_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(true);

    let interval_secs = std::env::var("RESERVATION_REAPER_INTERVAL_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(300);

    let claim_ttl_secs = std::env::var("RESERVATION_CLAIM_TTL_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(600);

    let batch_size = std::env::var("RESERVATION_REAPER_BATCH_SIZE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(200);

    ReaperConfig {
        enabled,
        interval_secs,
        claim_ttl_secs,
        batch_size,
    }
}

/// Spawns the reaper loop (composition root). Disabled via env or a zero
/// interval → no task. Failure of one pass postpones that pass's orphan
/// cleanup only — the claim lifecycle events are repeatable CAS actions, so
/// a failed pass never corrupts state.
pub fn spawn_reaper(pool: PgPool, store: ReservationStore) {
    let config = reaper_config_from_env();

    if !config.enabled {
        tracing::info!("Reservation reaper is disabled — not spawning (ADR-036 §3.2)");
        return;
    }
    let interval = Duration::from_secs(config.interval_secs);
    if interval.is_zero() {
        tracing::warn!("RESERVATION_REAPER_INTERVAL_SECS is 0 — not spawning reaper");
        return;
    }

    tracing::info!(
        interval_secs = config.interval_secs,
        claim_ttl_secs = config.claim_ttl_secs,
        "Reservation reaper spawned (ADR-036 §3.2)",
    );

    tokio::spawn(async move {
        loop {
            tokio::time::sleep(interval).await;
            if let Err(err) = run_reaper_pass(&pool, &store, &config).await {
                tracing::error!(
                    error = %err,
                    "reservation reaper pass failed (ADR-036 §3.2)",
                );
            }
        }
    });
}

/// One reaper pass. Candidates from the claim projection (bounded by TTL +
/// batch size), resolution always against the event store under an advisory
/// lock so concurrent sweeps cannot both act on one claim's CAS window
/// (the CAS guards make that merely wasteful, not incorrect — the lock keeps
/// the event-store round trips single-flight).
pub async fn run_reaper_pass(
    pool: &PgPool,
    store: &ReservationStore,
    config: &ReaperConfig,
) -> Result<(), anyhow::Error> {
    let mut locked = pool.acquire().await?;
    let owned = sqlx::query_scalar::<_, bool>(
        "SELECT pg_try_advisory_lock(hashtext('RESERVATION_REAPER'))",
    )
    .fetch_one(&mut *locked)
    .await?;

    if !owned {
        tracing::debug!("reservation reaper: another sweep is running; skipping pass");
        return Ok(());
    }

    let outcome = run_reaper_pass_locked(pool, store, config).await;

    // Always release the advisory lock — even after a failing sweep.
    if let Err(err) = sqlx::query("SELECT pg_advisory_unlock(hashtext('RESERVATION_REAPER'))")
        .execute(&mut *locked)
        .await
    {
        tracing::error!("reservation reaper: advisory lock release failed: {err}");
    }

    outcome
}

/// The actual sweep while the advisory lock is held.
async fn run_reaper_pass_locked(
    pool: &PgPool,
    store: &ReservationStore,
    config: &ReaperConfig,
) -> Result<(), anyhow::Error> {
    // Runtime is monotonically cheaper than `now() - interval` per row and
    // keeps the query an exact static literal (no string-interpolated SQL).
    let cutoff = chrono::Utc::now() - Duration::from_secs(config.claim_ttl_secs);

    let candidates = sqlx::query_as::<_, (String, Uuid)>(
        r#"
        SELECT reservation_key, aggregate_id
        FROM projection_number_reservation
        WHERE state = 'reserved'
            AND reserved_at < $1
        ORDER BY reserved_at
        LIMIT $2
        "#,
    )
    .bind(cutoff)
    .bind(config.batch_size)
    .fetch_all(pool)
    .await?;

    if candidates.is_empty() {
        return Ok(());
    }

    let mut consumed = 0usize;
    let mut released = 0usize;
    let mut skipped = 0usize;
    let mut failed = 0usize;

    for (key, claimed_aggregate) in &candidates {
        // Per-candidate isolation (CodeRabbit review, ADR-036 §3.2): one bad
        // claim (e.g. an unparsable lifecycle payload) must not abort the
        // whole pass — later candidates stay reachable, and the failed one is
        // retried on the next interval by the same CAS rules.
        match reap_claim(store, key, *claimed_aggregate, config.claim_ttl_secs).await {
            Ok(ReapDisposition::Consumed) => consumed += 1,
            Ok(ReapDisposition::Released) => released += 1,
            Ok(ReapDisposition::Skipped) => skipped += 1,
            Err(failure) => {
                failed += 1;
                tracing::error!(
                    key,
                    aggregate = %claimed_aggregate,
                    "reservation reaper: candidate failed; continuing with remaining candidates (ADR-036 §3.2): {failure}",
                );
            }
        }
    }

    tracing::info!(
        candidates = candidates.len(),
        consumed,
        released,
        skipped,
        failed,
        "reservation reaper pass completed (ADR-036 §3.2)",
    );
    Ok(())
}

enum ReapDisposition {
    /// The claimed aggregate exists — claim marked permanently true.
    Consumed,
    /// Crash orphan released — key claimable again.
    Released,
    /// Authoritative state moved on or is too young — nothing to do.
    Skipped,
}

/// Resolves one candidate claim against the event store.
async fn reap_claim(
    store: &ReservationStore,
    key: &str,
    claimed_aggregate: Uuid,
    claim_ttl_secs: u64,
) -> Result<ReapDisposition, anyhow::Error> {
    let Some(kind) = ReservationKind::from_key(key) else {
        tracing::warn!(
            key,
            "reaper candidate with unparsable key prefix; skipped (ADR-036 §3.2)"
        );
        return Ok(ReapDisposition::Skipped);
    };

    // Authoritative read of the reservation stream.
    let Some(state) = store.last_state(key).await? else {
        // Absent stream or unknown top event: the projector row is stale;
        // nothing releaseable to act on.
        return Ok(ReapDisposition::Skipped);
    };

    // Re-verify the TTL against the stream's own timestamp: the projector row
    // may lag a fresh re-reservation (candidate selected from its stale
    // `reserved_at`). The claim's identity must also still match.
    if state.variant != LifecycleVariant::Reserved
        || state.aggregate_id != claimed_aggregate
        || claim_is_too_young(&state, claim_ttl_secs)
    {
        return Ok(ReapDisposition::Skipped);
    }

    if store
        .aggregate_stream_exists(kind, claimed_aggregate)
        .await?
    {
        // The aggregate exists — but the claim only became TRUE if the
        // aggregate's persisted create event carries the claimed key's
        // (series_id, number) / pair (CodeRabbit review: a re-driven attempt
        // can claim a DIFFERENT key under the same derived aggregate id —
        // changed episode-group target — and consuming that phantom would
        // block a key no aggregate owns).
        match verify_realized_key(store, kind, key, claimed_aggregate).await? {
            RealizedKey::Matches => {
                // Realized claim: the aggregate owns the key for good — mark
                // so the reaper stops reconsidering it (and future reserves
                // still 409).
                store
                    .consume(key, claimed_aggregate, state.stream_version)
                    .await?;
                tracing::info!(
                    key,
                    aggregate = %claimed_aggregate,
                    kind = kind.as_str(),
                    "reservation claim consumed: aggregate stream exists and its create event matches the claim key (ADR-036 §3.2)",
                );
                Ok(ReapDisposition::Consumed)
            }
            RealizedKey::Mismatch => {
                // The claimed aggregate never realized THIS key (its persisted
                // create event carries a different key; numbering/pair fields
                // are immutable, so the first event decides). The claim is a
                // phantom: release it — the key becomes claimable again, and
                // its true owner will claim-and-append with a fresh aggregate.
                // Consuming here would block the key forever.
                store
                    .release(key, claimed_aggregate, state.stream_version)
                    .await?;
                tracing::warn!(
                    key,
                    aggregate = %claimed_aggregate,
                    kind = kind.as_str(),
                    "reservation claim released: claimed aggregate's persisted create event does not match the claim key (mismatched re-drive) (ADR-036 §3.2)",
                );
                Ok(ReapDisposition::Released)
            }
            RealizedKey::Undecidable => {
                // No events on the aggregate stream, or a first event that is
                // not the expected create event — never consume/release past
                // an undecidable; the next pass re-checks.
                tracing::warn!(
                    key,
                    aggregate = %claimed_aggregate,
                    kind = kind.as_str(),
                    "reservation claim: aggregate stream exists but its first event is undecidable; skipping (ADR-036 §3.2)",
                );
                Ok(ReapDisposition::Skipped)
            }
        }
    } else {
        // Crash orphan: nothing ever appended the aggregate — release.
        store
            .release(key, claimed_aggregate, state.stream_version)
            .await?;
        tracing::info!(
            key,
            aggregate = %claimed_aggregate,
            kind = kind.as_str(),
            "reservation claim released: crash orphan (aggregate stream absent) (ADR-036 §3.2)",
        );
        Ok(ReapDisposition::Released)
    }
}

/// Whether the claimed aggregate's persisted create event realizes the
/// claim key (CodeRabbit review on this PR): the mere existence of the
/// aggregate stream does not — a re-driven attempt may claim a different
/// key under the same derived aggregate id.
enum RealizedKey {
    /// First persisted event's key equals the claim key → consume.
    Matches,
    /// The aggregate exists but carries a different key → the claim is a
    /// phantom → release.
    Mismatch,
    /// No events / unexpected first event shape → conservative skip.
    Undecidable,
}

/// Reads the claimed aggregate's FIRST persisted event (version 0 — the
/// create event; numbering/pair fields are immutable afterwards) and derives
/// the key it realizes, using the same key builders that built the claim.
async fn verify_realized_key(
    store: &ReservationStore,
    kind: ReservationKind,
    key: &str,
    aggregate_id: uuid::Uuid,
) -> Result<RealizedKey, anyhow::Error> {
    let Some(first) = store.first_aggregate_event(kind, aggregate_id).await? else {
        return Ok(RealizedKey::Undecidable);
    };
    if first.stream_version != 0 {
        return Ok(RealizedKey::Undecidable);
    }

    let realized = match kind {
        ReservationKind::EpisodeNumber => {
            if first.event_name != "EpisodeCreated" {
                return Ok(RealizedKey::Undecidable);
            }
            match decode_lifecycle::<EpisodeEvent>(&first.payload, &first.stream_id)? {
                EpisodeEvent::EpisodeCreated {
                    series_id, number, ..
                } => episode_number_key(series_id.0, number),
                _ => return Ok(RealizedKey::Undecidable),
            }
        }
        ReservationKind::SeasonNumber => {
            if first.event_name != "SeasonCreated" {
                return Ok(RealizedKey::Undecidable);
            }
            match decode_lifecycle::<SeasonEvent>(&first.payload, &first.stream_id)? {
                SeasonEvent::SeasonCreated {
                    series_id, number, ..
                } => season_number_key(series_id.0, number),
                _ => return Ok(RealizedKey::Undecidable),
            }
        }
        ReservationKind::BlockNumber => {
            if first.event_name != "BlockCreated" {
                return Ok(RealizedKey::Undecidable);
            }
            match decode_lifecycle::<BlockEvent>(&first.payload, &first.stream_id)? {
                BlockEvent::BlockCreated {
                    series_id, number, ..
                } => block_number_key(series_id.0, number),
                _ => return Ok(RealizedKey::Undecidable),
            }
        }
        ReservationKind::SceneShootPair => {
            if first.event_name != "SceneShootPlanned" {
                return Ok(RealizedKey::Undecidable);
            }
            match decode_lifecycle::<SceneShootEvent>(&first.payload, &first.stream_id)? {
                SceneShootEvent::SceneShootPlanned {
                    scene_id,
                    shooting_day_id,
                    ..
                } => scene_shoot_pair_key(scene_id, shooting_day_id.0),
                _ => return Ok(RealizedKey::Undecidable),
            }
        }
    };

    Ok(if realized == key {
        RealizedKey::Matches
    } else {
        RealizedKey::Mismatch
    })
}

/// TTL re-verification against the authoritative claim timestamp.
fn claim_is_too_young(state: &StreamState, claim_ttl_secs: u64) -> bool {
    match state.timestamp.elapsed() {
        Ok(age) => age < Duration::from_secs(claim_ttl_secs),
        Err(_) => {
            // Clock skew (server timestamp ahead of local clock): treat as
            // too young — a later pass confirms.
            true
        }
    }
}
