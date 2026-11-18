// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Aggregate tests for the `Outfit` (character look) domain
//! (OpenSpec change `separate-piece-and-outfit-domain`).

use breakdown_core::outfit::*;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use kameo_es::{Apply, Command};
use test_support::make_ctx;
use uuid::Uuid;

fn project_id() -> ProjectId {
    ProjectId::new()
}

fn make_outfit(name: &str, piece_ids: Vec<Uuid>) -> OutfitAggregate {
    let agg = OutfitAggregate::default();
    let events = agg
        .handle(
            CreateOutfit {
                id: Uuid::now_v7(),
                character_id: Uuid::now_v7(),
                name: name.to_string(),
                piece_ids,
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = OutfitAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_outfit_binds_exactly_one_character() {
    let character_id = Uuid::now_v7();
    let id = Uuid::now_v7();
    let events = OutfitAggregate::default()
        .handle(
            CreateOutfit {
                id,
                character_id,
                name: "Alltagslook Tag 1".into(),
                piece_ids: Vec::new(),
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    match &events[0] {
        OutfitEvent::OutfitCreated {
            character_id: bound,
            name,
            version,
            piece_ids,
            ..
        } => {
            assert_eq!(*bound, character_id);
            assert_eq!(name, "Alltagslook Tag 1");
            assert_eq!(*version, AggregateVersion::INITIAL);
            assert!(piece_ids.is_empty());
        }
        other => panic!("expected OutfitCreated, got {other:?}"),
    }
}

#[test]
fn test_empty_shell_outfit_is_allowed() {
    let agg = make_outfit("OP-Kleidung", Vec::new());
    assert!(agg.piece_ids.is_empty());
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

#[test]
fn test_blank_name_is_rejected() {
    let err = OutfitAggregate::default()
        .handle(
            CreateOutfit {
                id: Uuid::now_v7(),
                character_id: Uuid::now_v7(),
                name: "   ".into(),
                piece_ids: Vec::new(),
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap_err();
    assert_eq!(err, OutfitError::EmptyName);
}

#[test]
fn test_layering_two_pieces_of_one_category_is_allowed() {
    let a = Uuid::now_v7();
    let b = Uuid::now_v7();
    let agg = make_outfit("Büro", vec![a, b]);
    assert_eq!(agg.piece_ids, vec![a, b]);
}

#[test]
fn test_create_deduplicates_piece_ids_keeping_first_occurrence() {
    let a = Uuid::now_v7();
    let b = Uuid::now_v7();
    let agg = make_outfit("Büro", vec![a, b, a]);
    assert_eq!(agg.piece_ids, vec![a, b]);
}

#[test]
fn test_add_piece_is_idempotent() {
    let a = Uuid::now_v7();
    let agg = make_outfit("Büro", vec![a]);
    let events = agg
        .handle(
            AddPieceToOutfit {
                id: agg.id,
                piece_id: a,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(events.is_empty(), "adding an existing piece emits no event");
}

#[test]
fn test_add_piece_appends_with_aggregate_computed_position() {
    let mut agg = make_outfit("Büro", vec![Uuid::now_v7()]);
    let b = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceToOutfit {
                id: agg.id,
                piece_id: b,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    match &events[0] {
        OutfitEvent::OutfitPieceAdded {
            piece_id, position, ..
        } => {
            assert_eq!(*piece_id, b);
            assert_eq!(*position, 1);
        }
        other => panic!("expected OutfitPieceAdded, got {other:?}"),
    }
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.piece_ids, vec![agg.piece_ids[0], b]);
}

#[test]
fn test_remove_absent_piece_is_a_noop() {
    let agg = make_outfit("Büro", vec![Uuid::now_v7()]);
    let events = agg
        .handle(
            RemovePieceFromOutfit {
                id: agg.id,
                piece_id: Uuid::now_v7(),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(events.is_empty());
}

#[test]
fn test_variant_is_an_independent_copy() {
    let source_piece = Uuid::now_v7();
    let source = make_outfit("Alltagslook Tag 1", vec![source_piece]);
    let source_id = source.id;

    let variant_events = source
        .handle(
            CreateOutfitVariant {
                id: Uuid::now_v7(),
                source_outfit_id: source_id,
                character_id: source.character_id,
                name: "Alltagslook Tag 1 (Variante)".into(),
                piece_ids: source.piece_ids.clone(),
                notes: source.notes.clone(),
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap();
    let mut variant = OutfitAggregate::default();
    test_support::replay_events(&mut variant, variant_events);

    assert_eq!(variant.variant_of, Some(source_id));
    assert_eq!(variant.version, AggregateVersion::INITIAL);

    // Editing the variant must not touch the source.
    let extra = Uuid::now_v7();
    let events = variant
        .handle(
            AddPieceToOutfit {
                id: variant.id,
                piece_id: extra,
                project_id: Some(project_id()),
                version: variant.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut variant, events);
    assert_eq!(variant.piece_ids, vec![source_piece, extra]);
    assert_eq!(
        source.piece_ids,
        vec![source_piece],
        "the source outfit must stay untouched"
    );
    assert_eq!(source.version, AggregateVersion::INITIAL);
}

#[test]
fn test_rename_identical_name_is_a_noop() {
    let agg = make_outfit("OP", Vec::new());
    let events = agg
        .handle(
            RenameOutfit {
                id: agg.id,
                name: "OP".into(),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(events.is_empty());
}

#[test]
fn test_stale_version_is_a_typed_mismatch() {
    let agg = make_outfit("OP", Vec::new());
    let stale = AggregateVersion(0);
    let err = agg
        .handle(
            AddPieceToOutfit {
                id: agg.id,
                piece_id: Uuid::now_v7(),
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        )
        .unwrap_err();
    assert_eq!(
        err,
        OutfitError::VersionMismatch {
            expected: stale,
            actual: AggregateVersion::INITIAL,
        }
    );
}

#[test]
fn test_photo_link_and_unlink_are_idempotent() {
    use kameo_es::Metadata;
    let mut agg = OutfitAggregate::default();
    let photo_id = Uuid::now_v7();
    agg.apply(
        OutfitEvent::OutfitCreated {
            id: Uuid::now_v7(),
            character_id: Uuid::now_v7(),
            name: "OP".into(),
            piece_ids: Vec::new(),
            photos: vec![photo_id],
            notes: String::new(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    let events = agg
        .handle(
            LinkOutfitPhoto {
                id: agg.id,
                photo_id,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(events.is_empty(), "a repeat link emits no event");

    let events = agg
        .handle(
            UnlinkOutfitPhoto {
                id: agg.id,
                photo_id: Uuid::now_v7(),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(
        events.is_empty(),
        "unlinking an absent photo emits no event"
    );
}
