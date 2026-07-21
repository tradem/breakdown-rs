// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use crate::shared::{LexicalSortKey, SeasonId};
use test_support::make_ctx;

fn create_category() -> CostumeCategoryAggregate {
    let season_id = SeasonId::new();
    let agg = CostumeCategoryAggregate::default();
    let events = agg
        .handle(
            CreateCostumeCategory {
                id: Uuid::now_v7(),
                season_id,
                name: "Oberteil".to_string(),
                order_key: LexicalSortKey::from_static("a"),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = CostumeCategoryAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_category_success() {
    let season_id = SeasonId::new();
    let id = Uuid::now_v7();
    let result = CostumeCategoryAggregate::default()
        .handle(
            CreateCostumeCategory {
                id,
                season_id,
                name: "Schuhe".to_string(),
                order_key: LexicalSortKey::from_static("b"),
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(result.len(), 1);
    match result.into_iter().next().unwrap() {
        CostumeCategoryEvent::CostumeCategoryCreated {
            id: eid,
            season_id: es,
            name,
            order_key,
            version,
        } => {
            assert_eq!(eid, id);
            assert_eq!(es, season_id);
            assert_eq!(name, "Schuhe");
            assert_eq!(order_key, LexicalSortKey::from_static("b"));
            assert_eq!(version, AggregateVersion::INITIAL);
        }
        _ => panic!("Expected CostumeCategoryCreated"),
    }
}

#[test]
fn test_create_category_rejects_empty_name() {
    let result = CostumeCategoryAggregate::default().handle(
        CreateCostumeCategory {
            id: Uuid::now_v7(),
            season_id: SeasonId::new(),
            name: "   ".to_string(),
            order_key: LexicalSortKey::from_static("a"),
        },
        make_ctx(),
    );
    assert!(matches!(
        result,
        Err(CostumeCategoryError::ValidationError(_))
    ));
}

#[test]
fn test_rename_preserves_order() {
    let mut agg = create_category();
    let events = agg
        .handle(
            RenameCostumeCategory {
                id: agg.id,
                name: "Obertreiber".to_string(),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.name, "Obertreiber");
    assert_eq!(agg.order_key, LexicalSortKey::from_static("a"));
}

#[test]
fn test_reorder_midpoint_is_single_event() {
    let mut agg = create_category();
    let events = agg
        .handle(
            ReorderCostumeCategory {
                id: agg.id,
                order_key: LexicalSortKey::from_static("a0"),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    match events.into_iter().next().unwrap() {
        CostumeCategoryEvent::CostumeCategoryReordered { order_key, .. } => {
            assert_eq!(order_key, LexicalSortKey::from_static("a0"));
        }
        _ => panic!("Expected CostumeCategoryReordered"),
    }
    let id = agg.id;
    let version = agg.version.next();
    test_support::replay_events(
        &mut agg,
        vec![CostumeCategoryEvent::CostumeCategoryReordered {
            id,
            order_key: LexicalSortKey::from_static("a0"),
            version,
        }],
    );
    assert_eq!(agg.order_key, LexicalSortKey::from_static("a0"));
}

#[test]
fn test_archive_is_terminal_and_rejects_mutations() {
    let mut agg = create_category();
    // Archive.
    let events = agg
        .handle(
            ArchiveCostumeCategory {
                id: agg.id,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.archived);

    // Re-archiving (idempotent reject) is an error.
    let again = agg.handle(
        ArchiveCostumeCategory {
            id: agg.id,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        again,
        Err(CostumeCategoryError::ArchivedCannotBeMutated { .. })
    ));

    // Renaming an archived category is rejected.
    let rename = agg.handle(
        RenameCostumeCategory {
            id: agg.id,
            name: "Nope".to_string(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        rename,
        Err(CostumeCategoryError::ArchivedCannotBeMutated { .. })
    ));

    // Reordering an archived category is rejected.
    let reorder = agg.handle(
        ReorderCostumeCategory {
            id: agg.id,
            order_key: LexicalSortKey::from_static("z"),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(matches!(
        reorder,
        Err(CostumeCategoryError::ArchivedCannotBeMutated { .. })
    ));
}

#[test]
fn test_version_mismatch_rejection() {
    let agg = create_category();
    let result = agg.handle(
        RenameCostumeCategory {
            id: agg.id,
            name: "X".into(),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(matches!(
        result,
        Err(CostumeCategoryError::VersionMismatch { .. })
    ));
}
