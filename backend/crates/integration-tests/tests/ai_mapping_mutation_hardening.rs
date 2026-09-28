// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

//! P3.11 — Postgres integration tests for PgAiImportMappingRepository.
//!
//! These tests kill the 8 mutations in `mapping.rs` that require a live
//! Postgres instance.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportJobId, AiImportMapping, AiImportMappingRepository, PRIMARY_ORDINAL, mapping_kind,
};
use breakdown_core::shared::AggregateVersion;
use infra::ai::mapping::PgAiImportMappingRepository;
use uuid::Uuid;

/// Helper to create a test mapping.
fn make_mapping(preview_id: AiImportJobId, draft_ref: &str) -> AiImportMapping {
    AiImportMapping {
        preview_id,
        draft_ref: draft_ref.to_owned(),
        aggregate_kind: mapping_kind::SCENE.to_owned(),
        ordinal: PRIMARY_ORDINAL,
        aggregate_id: Uuid::now_v7(),
        aggregate_version: AggregateVersion::INITIAL,
    }
}

/// Read a `scene` row by reference — the shape almost every test below needs.
async fn find_scene(
    repo: &PgAiImportMappingRepository,
    preview_id: AiImportJobId,
    draft_ref: &str,
) -> Result<Option<AiImportMapping>> {
    Ok(repo
        .find(preview_id, draft_ref, mapping_kind::SCENE, PRIMARY_ORDINAL)
        .await?)
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

    let found = find_scene(&repo, preview_id, "scene-1").await?;
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

    let found = find_scene(&repo, preview_id, "scene-1").await?.unwrap();
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

// ===========================================================================
// the row key — one draft row produces several kinds of aggregate
// ===========================================================================

/// A reviewed draft row now yields its scene, its figures and its costumes, and
/// they all share the row's `draft_ref`. The `(aggregate_kind, ordinal)` part of
/// the primary key is what keeps them apart: without it the scene's row and the
/// first costume's row would collide, and the costume would resolve to the
/// Scene's aggregate id — silently binding a garment to a scene.
///
/// Only a live Postgres proves this, because the discrimination lives in the
/// `ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal)` target: an
/// in-memory fake keyed differently cannot catch a wrong conflict target.
#[tokio::test]
async fn one_draft_ref_holds_a_scene_a_figure_and_two_costumes() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);
    let preview_id = AiImportJobId::new();
    let draft_ref = "7. I/T - OP";

    let scene = make_mapping(preview_id, draft_ref);
    let figure = AiImportMapping {
        aggregate_kind: mapping_kind::CHARACTER.to_owned(),
        aggregate_id: Uuid::now_v7(),
        ..scene.clone()
    };
    let first_costume = AiImportMapping {
        aggregate_kind: mapping_kind::COSTUME.to_owned(),
        ordinal: 0,
        aggregate_id: Uuid::now_v7(),
        ..scene.clone()
    };
    let second_costume = AiImportMapping {
        aggregate_kind: mapping_kind::COSTUME.to_owned(),
        ordinal: 1,
        aggregate_id: Uuid::now_v7(),
        ..scene.clone()
    };
    for mapping in [&scene, &figure, &first_costume, &second_costume] {
        repo.insert(mapping.clone()).await?;
    }

    let stored = repo.list_by_preview(preview_id).await?;
    assert_eq!(
        stored.len(),
        4,
        "one reference must hold four distinct rows, got {stored:?}"
    );
    assert_eq!(
        find_scene(&repo, preview_id, draft_ref)
            .await?
            .expect("scene row")
            .aggregate_id,
        scene.aggregate_id
    );
    assert_eq!(
        repo.find(preview_id, draft_ref, mapping_kind::COSTUME, 1)
            .await?
            .expect("second costume row")
            .aggregate_id,
        second_costume.aggregate_id,
        "two costumes of one figure in one scene must stay addressable"
    );

    // A reservation for one of them must converge on *that* row's id only.
    let retry = AiImportMapping::reservation(
        preview_id,
        draft_ref.to_owned(),
        mapping_kind::COSTUME.to_owned(),
        1,
        Uuid::now_v7(),
    );
    assert_eq!(
        repo.reserve(retry).await?.aggregate_id,
        second_costume.aggregate_id,
        "a costume retry must not land on the scene's aggregate"
    );
    Ok(())
}

/// Ordinals of *different* kinds must not interfere: ordinal is scoped by kind,
/// so a figure and a costume may both carry 0 for one reference.
#[tokio::test]
async fn ordinal_is_scoped_by_aggregate_kind() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let repo = PgAiImportMappingRepository::new(pool);
    let preview_id = AiImportJobId::new();

    let scene = make_mapping(preview_id, "1. INT. KITCHEN");
    let costume = AiImportMapping {
        aggregate_kind: mapping_kind::COSTUME.to_owned(),
        aggregate_id: Uuid::now_v7(),
        ..scene.clone()
    };
    repo.insert(scene.clone()).await?;
    repo.insert(costume.clone()).await?;

    assert_eq!(
        repo.find(preview_id, "1. INT. KITCHEN", mapping_kind::COSTUME, 0)
            .await?
            .expect("costume row survived the scene insert")
            .aggregate_id,
        costume.aggregate_id
    );
    assert_eq!(
        find_scene(&repo, preview_id, "1. INT. KITCHEN")
            .await?
            .expect("scene row survived the costume insert")
            .aggregate_id,
        scene.aggregate_id
    );
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
        .find(
            mapping.preview_id,
            &mapping.draft_ref,
            mapping_kind::SCENE,
            PRIMARY_ORDINAL,
        )
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
        .find(
            mapping.preview_id,
            &mapping.draft_ref,
            mapping_kind::SCENE,
            PRIMARY_ORDINAL,
        )
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

    let found = find_scene(&repo, preview_id, "scene-1").await?.unwrap();
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

    let found = find_scene(&repo, preview_id, "scene-1").await?.unwrap();
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
