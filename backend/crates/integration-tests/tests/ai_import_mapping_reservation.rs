// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Database-backed contract for the AI import mapping **reservation** protocol
//! (issue #179).
//!
//! `ScheduleApplyWorker` closes its crash window by reserving an aggregate id
//! *before* dispatching a create-style command and confirming the resulting
//! version afterwards. Two Postgres-level properties carry that protocol, and
//! neither is observable against an in-memory fake:
//!
//! 1. `reserve` is insert-if-absent **and returns the winning row** — this
//!    relies on the `ON CONFLICT ... DO UPDATE ... RETURNING` trick (a plain
//!    `DO NOTHING` returns no row on conflict). If that regressed, retries
//!    would each mint a fresh aggregate id and duplicate the aggregate.
//! 2. `insert` only ever *advances* `aggregate_version`, so a late duplicate
//!    confirm cannot roll a confirmed row back to a reservation.
//!
//! Exercises only the public `AiImportMappingRepository` API.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{AiImportJobId, AiImportMapping, AiImportMappingRepository};
use breakdown_core::shared::AggregateVersion;
use infra::ai::PgAiImportMappingRepository;
use uuid::Uuid;

fn reservation(preview_id: AiImportJobId, draft_ref: &str) -> AiImportMapping {
    AiImportMapping::reservation(
        preview_id,
        draft_ref.to_owned(),
        "scene_shoot".to_owned(),
        Uuid::now_v7(),
    )
}

/// The core anti-duplication property: a second `reserve` for the same
/// `(preview_id, draft_ref)` must return the *first* aggregate id, never the
/// freshly-minted one it was called with.
#[tokio::test]
async fn reserve_is_insert_if_absent_and_returns_the_winning_row() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);
    let preview_id = AiImportJobId::new();

    let first = repo
        .reserve(reservation(preview_id, "scene-shoot:a:b"))
        .await?;
    assert!(first.is_reserved(), "a fresh reservation carries version 0");

    // Simulates the retry after a crash: a new SceneShootId is generated, but
    // the durable reservation must win.
    let retry_candidate = reservation(preview_id, "scene-shoot:a:b");
    assert_ne!(
        retry_candidate.aggregate_id, first.aggregate_id,
        "the retry really does offer a different id"
    );
    let second = repo.reserve(retry_candidate).await?;

    assert_eq!(
        second.aggregate_id, first.aggregate_id,
        "the retry must converge on the reserved aggregate id"
    );
    assert!(second.is_reserved());
    Ok(())
}

/// A reservation that has already been confirmed must not be reopened by a
/// later `reserve` — the retry has to see the confirmed version and skip.
#[tokio::test]
async fn reserve_returns_a_confirmed_row_unchanged() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);
    let preview_id = AiImportJobId::new();

    let reserved = repo
        .reserve(reservation(preview_id, "scene-shoot:c:d"))
        .await?;
    repo.insert(AiImportMapping {
        aggregate_version: AggregateVersion::INITIAL,
        ..reserved.clone()
    })
    .await?;

    let after = repo
        .reserve(reservation(preview_id, "scene-shoot:c:d"))
        .await?;

    assert_eq!(after.aggregate_id, reserved.aggregate_id);
    assert!(
        !after.is_reserved(),
        "a confirmed mapping must not be downgraded to a reservation"
    );
    assert_eq!(after.aggregate_version, AggregateVersion::INITIAL);
    Ok(())
}

/// The confirm write is monotonic: a replayed confirm carrying the reservation
/// sentinel (or any lower version) must not roll the row back.
#[tokio::test]
async fn insert_never_rolls_a_confirmed_version_back() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);
    let preview_id = AiImportJobId::new();

    let reserved = repo
        .reserve(reservation(preview_id, "scene-shoot:e:f"))
        .await?;
    repo.insert(AiImportMapping {
        aggregate_version: AggregateVersion(5),
        ..reserved.clone()
    })
    .await?;

    // A stale/duplicate confirm from a slow retry.
    repo.insert(AiImportMapping {
        aggregate_version: AggregateVersion(2),
        ..reserved.clone()
    })
    .await?;
    // …and the reservation sentinel itself.
    repo.insert(reserved.clone()).await?;

    let stored = repo
        .find(preview_id, "scene-shoot:e:f")
        .await?
        .expect("the mapping must still exist");
    assert_eq!(
        stored.aggregate_version,
        AggregateVersion(5),
        "aggregate_version must only ever advance"
    );
    assert!(!stored.is_reserved());
    Ok(())
}
