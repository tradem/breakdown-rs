// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! P3.11 — Postgres integration tests for PgAiImportMappingRepository.
//!
//! These tests kill the 8 mutations in `mapping.rs` that require a live
//! Postgres instance.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{AiImportJobId, AiImportMapping, AiImportMappingRepository};
use breakdown_core::shared::AggregateVersion;
use infra::ai::mapping::PgAiImportMappingRepository;
use uuid::Uuid;

/// Helper to create a test mapping.
fn make_mapping(preview_id: AiImportJobId, draft_ref: &str) -> AiImportMapping {
    AiImportMapping {
        preview_id,
        draft_ref: draft_ref.to_owned(),
        aggregate_kind: "scene".to_owned(),
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion::INITIAL,
    }
}

// ===========================================================================
// insert — kills Ok(()) replacement
// ===========================================================================

#[tokio::test]
async fn insert_persists_mapping() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();
    let mapping = make_mapping(preview_id, "scene-1");

    repo.insert(mapping.clone()).await?;

    let found = repo.find(preview_id, "scene-1").await?;
    assert!(found.is_some(), "mapping should be found after insert");
    let found = found.unwrap();
    assert_eq!(found.aggregate_id, mapping.aggregate_id);
    assert_eq!(found.aggregate_version, AggregateVersion::INITIAL);

    Ok(())
}

#[tokio::test]
async fn insert_updates_version_on_conflict() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();
    let mut mapping = make_mapping(preview_id, "scene-1");

    repo.insert(mapping.clone()).await?;

    // Insert again with higher version
    mapping.aggregate_version = AggregateVersion(1);
    mapping.aggregate_id = Uuid::now_v7(); // different aggregate
    repo.insert(mapping).await?;

    let found = repo.find(preview_id, "scene-1").await?.unwrap();
    assert_eq!(
        found.aggregate_version,
        AggregateVersion(1),
        "version should be updated"
    );

    Ok(())
}

// ===========================================================================
// list_by_preview — kills Ok(vec![]) replacement
// ===========================================================================

#[tokio::test]
async fn list_by_preview_returns_all_mappings() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();

    repo.insert(make_mapping(preview_id, "scene-1")).await?;
    repo.insert(make_mapping(preview_id, "scene-2")).await?;
    repo.insert(make_mapping(preview_id, "scene-3")).await?;

    let mappings = repo.list_by_preview(preview_id).await?;
    assert_eq!(mappings.len(), 3, "should return all 3 mappings");

    // Should be ordered by draft_ref
    assert_eq!(mappings[0].draft_ref, "scene-1");
    assert_eq!(mappings[1].draft_ref, "scene-2");
    assert_eq!(mappings[2].draft_ref, "scene-3");

    Ok(())
}

#[tokio::test]
async fn list_by_preview_returns_empty_for_unknown_preview() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let mappings = repo.list_by_preview(AiImportJobId::new()).await?;
    assert!(
        mappings.is_empty(),
        "should return empty for unknown preview"
    );

    Ok(())
}

// ===========================================================================
// version_to_db — kills Ok(-1), Ok(0), Ok(1) replacement
// ===========================================================================

#[tokio::test]
async fn insert_with_zero_version_succeeds() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let mapping = AiImportMapping {
        aggregate_version: AggregateVersion(0),
        ..make_mapping(AiImportJobId::new(), "scene-1")
    };

    repo.insert(mapping.clone()).await?;

    let found = repo
        .find(mapping.preview_id, &mapping.draft_ref)
        .await?
        .unwrap();
    assert_eq!(
        found.aggregate_version,
        AggregateVersion(0),
        "version 0 should be persisted"
    );

    Ok(())
}

#[tokio::test]
async fn insert_with_high_version_succeeds() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let mapping = AiImportMapping {
        aggregate_version: AggregateVersion(999_999),
        ..make_mapping(AiImportJobId::new(), "scene-1")
    };

    repo.insert(mapping.clone()).await?;

    let found = repo
        .find(mapping.preview_id, &mapping.draft_ref)
        .await?
        .unwrap();
    assert_eq!(
        found.aggregate_version,
        AggregateVersion(999_999),
        "high version should be persisted"
    );

    Ok(())
}

// ===========================================================================
// map_mapping — kills < → <=, ==, > for negative version check
// ===========================================================================

#[tokio::test]
async fn find_returns_mapping_with_zero_version() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();
    let mapping = AiImportMapping {
        aggregate_version: AggregateVersion(0),
        ..make_mapping(preview_id, "scene-1")
    };

    repo.insert(mapping.clone()).await?;

    let found = repo.find(preview_id, "scene-1").await?.unwrap();
    assert_eq!(found.aggregate_version, AggregateVersion(0));

    Ok(())
}

#[tokio::test]
async fn find_returns_mapping_with_high_version() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();
    let mapping = AiImportMapping {
        aggregate_version: AggregateVersion(42),
        ..make_mapping(preview_id, "scene-1")
    };

    repo.insert(mapping.clone()).await?;

    let found = repo.find(preview_id, "scene-1").await?.unwrap();
    assert_eq!(found.aggregate_version, AggregateVersion(42));

    Ok(())
}

// ===========================================================================
// reserve — idempotent insert-if-absent
// ===========================================================================

#[tokio::test]
async fn reserve_creates_new_mapping() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let mapping = make_mapping(AiImportJobId::new(), "scene-1");
    let returned = repo.reserve(mapping.clone()).await?;

    assert_eq!(returned.aggregate_id, mapping.aggregate_id);
    // reserve preserves the version from the input mapping
    assert_eq!(returned.aggregate_version, mapping.aggregate_version);

    Ok(())
}

#[tokio::test]
async fn reserve_returns_existing_on_duplicate() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);

    let preview_id = AiImportJobId::new();
    let mapping1 = make_mapping(preview_id, "scene-1");
    let returned1 = repo.reserve(mapping1.clone()).await?;

    // Reserve again with different aggregate_id
    let mapping2 = AiImportMapping {
        aggregate_id: Uuid::now_v7(),
        ..make_mapping(preview_id, "scene-1")
    };
    let returned2 = repo.reserve(mapping2).await?;

    // Should return the first mapping (idempotent) -- both id and version preserved
    assert_eq!(
        returned2.aggregate_id, returned1.aggregate_id,
        "id should be preserved"
    );
    assert_eq!(
        returned2.aggregate_version, returned1.aggregate_version,
        "version should be preserved"
    );

    Ok(())
}
