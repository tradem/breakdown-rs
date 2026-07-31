// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

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
    costume::{commands::CreateCostume, events::CostumeEvent},
    shared::AggregateVersion,
};
use fixtures::spawn_postgres;
use kameo_es::{Apply, Command};
use test_support::make_ctx;

use breakdown_core::costume::aggregate::CostumeAggregate;

#[tokio::test]
async fn postgres_harness_supports_costume_round_trip_template() -> Result<()> {
    let (_pool, _container) = spawn_postgres().await?;

    let costume_id = uuid::Uuid::now_v7();
    let aggregate = CostumeAggregate::default();
    let events = aggregate.handle(
        CreateCostume {
            id: costume_id,
            series_id: None,
        },
        make_ctx::<CostumeAggregate>(),
    )?;

    assert_eq!(events.len(), 1);
    let created = match events[0].clone() {
        CostumeEvent::CostumeCreated { id, .. } => id,
        other => panic!("expected CostumeCreated, got {other:?}"),
    };

    assert_ne!(created, uuid::Uuid::nil());
    assert_eq!(created, costume_id);
    assert_eq!(created.get_version(), Some(uuid::Version::SortRand));

    let mut replayed = CostumeAggregate::default();
    for event in events {
        replayed.apply(event, Default::default());
    }
    assert!(replayed.character_id.is_none());
    // Costume is scope-free: there is no project_id / season_id to assert.
    let _ = AggregateVersion::INITIAL;

    Ok(())
}
