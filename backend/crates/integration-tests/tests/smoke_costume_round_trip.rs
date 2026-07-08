// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

mod fixtures;

use anyhow::Result;
use breakdown_core::{
    costume::{commands::CreateCostume, events::CostumeEvent},
    shared::ProjectId,
};
use fixtures::spawn_postgres;
use kameo_es::{Apply, Command};
use test_support::make_ctx;

use breakdown_core::costume::aggregate::CostumeAggregate;

#[tokio::test]
async fn postgres_harness_supports_costume_round_trip_template() -> Result<()> {
    let (_pool, _container) = spawn_postgres().await?;

    let project_id = ProjectId::new();
    let costume_id = uuid::Uuid::now_v7();
    let aggregate = CostumeAggregate::default();
    let events = aggregate.handle(
        CreateCostume {
            id: costume_id,
            project_id,
        },
        make_ctx::<CostumeAggregate>(),
    )?;

    assert_eq!(events.len(), 1);
    let created = match events[0].clone() {
        CostumeEvent::CostumeCreated {
            id,
            project_id: pid,
            ..
        } => (id, pid),
        other => panic!("expected CostumeCreated, got {other:?}"),
    };

    assert_ne!(created.0, uuid::Uuid::nil());
    assert_eq!(created.0, costume_id);
    assert_eq!(created.1, project_id);
    assert_eq!(created.0.get_version(), Some(uuid::Version::SortRand));

    let mut replayed = CostumeAggregate::default();
    for event in events {
        replayed.apply(event, Default::default());
    }
    assert_eq!(replayed.project_id, project_id);
    assert!(replayed.character_id.is_none());

    Ok(())
}
