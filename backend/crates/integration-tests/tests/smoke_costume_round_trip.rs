// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
use breakdown_core::{
    piece::{commands::CreatePiece, events::PieceEvent},
    shared::AggregateVersion,
};
use fixtures::spawn_postgres;
use kameo_es::{Apply, Command};
use test_support::make_ctx;

use breakdown_core::piece::aggregate::PieceAggregate;

#[tokio::test]
async fn postgres_harness_supports_piece_round_trip_template() -> Result<()> {
    let (_pool, _container) = spawn_postgres().await?;

    let piece_id = uuid::Uuid::now_v7();
    let aggregate = PieceAggregate::default();
    let events = aggregate.handle(
        CreatePiece {
            id: piece_id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            project_id: None,
        },
        make_ctx::<PieceAggregate>(),
    )?;

    assert_eq!(events.len(), 1);
    let created = match events[0].clone() {
        PieceEvent::PieceCreated { id, .. } => id,
        other => panic!("expected PieceCreated, got {other:?}"),
    };

    assert_ne!(created, uuid::Uuid::nil());
    assert_eq!(created, piece_id);
    assert_eq!(created.get_version(), Some(uuid::Version::SortRand));

    let mut replayed = PieceAggregate::default();
    for event in events {
        replayed.apply(event, Default::default());
    }
    // A piece is character-free: the character binding lives on the outfit.
    assert!(replayed.seasons.is_empty());
    let _ = AggregateVersion::INITIAL;

    Ok(())
}
