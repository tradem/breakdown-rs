// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume aggregate round-trip smoke test.
//!
//! This file documents the canonical integration-test template:
//!
//! ```text
//! spawn resource → seed via public command API → assert via public query API → drop guards
//! ```
//!
//! The full `command → sierradb event store → projector → Postgres projection`
//! round-trip is intentionally not implemented yet: the sierradb-backed event
//! store and the `Costume` projector are still being wired up in `infra`. Until
//! then, this test verifies the Postgres harness and exercises the aggregate
//! command handler in-memory. The persisted round-trip step will be added once
//! the sierradb test infrastructure is available in a follow-up feature branch.

use anyhow::Result;
use breakdown_core::{
    costume::{commands::CreateCostume, events::CostumeEvent},
    shared::ProjectId,
    testing::make_ctx,
};
use kameo_es::{Apply, Command};

// The aggregate is referenced by its fully-qualified path so future tests can
// copy the pattern directly.
use breakdown_core::costume::aggregate::CostumeAggregate;

#[tokio::test]
async fn postgres_harness_supports_costume_round_trip_template() -> Result<()> {
    // 1. Spawn the Postgres projection store. The container guard is dropped at
    //    the end of the test, tearing the database down.
    let (pool, _container) = infra::testing::spawn_postgres().await?;

    // Verify that the projection schema is present and writable.
    sqlx::query("INSERT INTO integration_test_smoke_check (id) VALUES ($1)")
        .bind(uuid::Uuid::now_v7())
        .execute(&pool)
        .await?;

    // 2. Seed via the public command API (in-memory aggregate command handler).
    let project_id = ProjectId::new();
    let aggregate = CostumeAggregate::default();
    let events = aggregate.handle(CreateCostume { project_id }, make_ctx::<CostumeAggregate>())?;

    assert_eq!(events.len(), 1);
    let created = match events[0].clone() {
        CostumeEvent::CostumeCreated {
            id,
            project_id: pid,
            ..
        } => (id, pid),
        other => panic!("expected CostumeCreated, got {other:?}"),
    };

    // UUIDv7 sanity check: the generated id and the supplied project id must be
    // non-nil UUIDv7 values.
    assert_ne!(created.0, uuid::Uuid::nil());
    assert_eq!(created.1, project_id);
    assert_eq!(created.0.get_version(), Some(uuid::Version::SortRand));

    // 3. Re-hydrate the aggregate from the emitted events to prove replay works.
    let mut replayed = CostumeAggregate::default();
    for event in events {
        replayed.apply(event, Default::default());
    }
    assert_eq!(replayed.project_id, project_id);
    assert!(replayed.character_id.is_none());

    // TODO(follow-up branch): persist the event through the sierradb-backed
    // `kameo_es` command service, run the Costume projector, and assert the
    // projection row is readable through the public `infra` query API.

    Ok(())
}
