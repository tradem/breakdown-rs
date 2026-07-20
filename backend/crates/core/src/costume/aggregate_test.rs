// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use test_support::make_ctx;

fn make_costume() -> CostumeAggregate {
    let agg = CostumeAggregate::default();
    let events = agg
        .handle(CreateCostume { id: Uuid::now_v7() }, make_ctx())
        .unwrap();
    let mut applied = CostumeAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_costume_success() {
    let result =
        CostumeAggregate::default().handle(CreateCostume { id: Uuid::now_v7() }, make_ctx());
    assert!(result.is_ok());
    match result.unwrap().into_iter().next().unwrap() {
        CostumeEvent::CostumeCreated {
            id,
            version,
            character_id,
            ..
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(version, AggregateVersion::INITIAL);
            assert!(character_id.is_none());
        }
        _ => panic!("Expected CostumeCreated"),
    }
}

#[test]
fn test_update_costume_notes_success() {
    let mut agg = make_costume();
    let n: String = "Tear on sleeve".to_string();
    let events = agg
        .handle(
            UpdateCostumeNotes {
                id: agg.id,
                notes: n.clone(),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.notes, n);
}

#[test]
fn test_update_costume_notes_idempotency() {
    let agg = make_costume();
    let result = agg.handle(
        UpdateCostumeNotes {
            id: agg.id,
            notes: agg.notes.clone(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
}

#[test]
fn test_update_costume_notes_wrong_version() {
    let agg = make_costume();
    let result = agg.handle(
        UpdateCostumeNotes {
            id: agg.id,
            notes: "X".into(),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

#[test]
fn test_assign_costume_success() {
    let mut agg = make_costume();
    let cid = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCostumeToCharacter {
                id: agg.id,
                character_id: cid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.character_id, Some(cid));
}

#[test]
fn test_assign_costume_conflict() {
    let mut agg = make_costume();
    let ca = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCostumeToCharacter {
                id: agg.id,
                character_id: ca,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.character_id, Some(ca));
    let result = agg.handle(
        AssignCostumeToCharacter {
            id: agg.id,
            character_id: Uuid::now_v7(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::AlreadyAssigned { assigned_to } if assigned_to == ca
    ));
}

#[test]
fn test_unassign_costume_success() {
    let mut agg = make_costume();
    let cid = Uuid::now_v7();
    let events = agg
        .handle(
            AssignCostumeToCharacter {
                id: agg.id,
                character_id: cid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.character_id, Some(cid));
    let events = agg
        .handle(
            UnassignCostume {
                id: agg.id,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.character_id, None);
}

#[test]
fn test_unassign_not_assigned() {
    let agg = make_costume();
    let result = agg.handle(
        UnassignCostume {
            id: agg.id,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::ValidationError(ref m) if m.contains("not currently assigned")
    ));
}

#[test]
fn test_add_detail_success() {
    let mut agg = make_costume();
    let did = Uuid::now_v7();
    let events = agg
        .handle(
            AddDetail {
                id: agg.id,
                detail: CostumeDetail {
                    id: did,
                    text: "silk".to_string(),
                },
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.len(), 1);
    assert_eq!(agg.details[0].text, "silk");
}

#[test]
fn test_remove_detail_success() {
    let mut agg = make_costume();
    let did = Uuid::now_v7();
    let events = agg
        .handle(
            AddDetail {
                id: agg.id,
                detail: CostumeDetail {
                    id: did,
                    text: "x".to_string(),
                },
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            RemoveDetail {
                id: agg.id,
                detail_id: did,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.details.is_empty());
}

#[test]
fn test_remove_detail_not_found() {
    let agg = make_costume();
    let result = agg.handle(
        RemoveDetail {
            id: agg.id,
            detail_id: Uuid::now_v7(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::ValidationError(ref m) if m.contains("not found")
    ));
}

#[test]
fn test_link_photo_success() {
    let mut agg = make_costume();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPhoto {
                id: agg.id,
                photo_id: pid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.photos.len(), 1);
}

#[test]
fn test_link_photo_already_linked() {
    let mut agg = make_costume();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPhoto {
                id: agg.id,
                photo_id: pid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let result = agg.handle(
        LinkPhoto {
            id: agg.id,
            photo_id: pid,
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::ValidationError(ref m) if m.contains("already linked")
    ));
}

#[test]
fn test_unlink_photo_success() {
    let mut agg = make_costume();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPhoto {
                id: agg.id,
                photo_id: pid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            UnlinkPhoto {
                id: agg.id,
                photo_id: pid,
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert!(agg.photos.is_empty());
}

#[test]
fn test_unlink_photo_not_linked() {
    let agg = make_costume();
    let result = agg.handle(
        UnlinkPhoto {
            id: agg.id,
            photo_id: Uuid::now_v7(),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CostumeError::ValidationError(ref m) if m.contains("not linked")
    ));
}

/// Verify that apply() actually mutates aggregate state.
///
/// Catches mutants that replace the `apply` body with `()` — if apply is a
/// no-op the assertion below fails because the costume keeps its default
/// notes.
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = CostumeAggregate::default();
    let id = Uuid::now_v7();
    let notes = "Silk lining needs repair".to_string();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
            notes: notes.clone(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(agg.notes, notes, "apply() should set the costume notes");
    assert_eq!(agg.id, id);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

/// Verify that UnlinkPhoto checks `!self.photos.contains(...)` — if the `!`
/// is deleted the guard flips and unlinking a linked photo would be
/// rejected as if it were not linked.
#[test]
fn test_unlink_photo_uses_negation() {
    use kameo_es::Metadata;
    let mut agg = CostumeAggregate::default();
    let id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();
    // Create costume with one linked photo.
    agg.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
            notes: String::new(),
            details: Vec::new(),
            photos: vec![photo_id],
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    // Unlinking the linked photo should succeed.
    let result = agg.handle(
        UnlinkPhoto {
            id,
            photo_id,
            version: AggregateVersion::INITIAL,
        },
        make_ctx(),
    );
    assert!(
        result.is_ok(),
        "unlinking a linked photo should succeed (guards ! negation)"
    );
}
