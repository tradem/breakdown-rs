// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use breakdown_core::piece::*;
use breakdown_core::shared::{AggregateVersion, CostumeCategoryId, ProjectId, SeasonId};
use kameo_es::{Apply, Command};
use test_support::make_ctx;
use uuid::Uuid;

fn project_id() -> ProjectId {
    ProjectId::new()
}

fn make_piece() -> PieceAggregate {
    let agg = PieceAggregate::default();
    let events = agg
        .handle(
            CreatePiece {
                id: Uuid::now_v7(),
                name: "Fundus-Piece".to_string(),
                category_id: None,
                season_id: None,
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = PieceAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_piece_success() {
    let result = PieceAggregate::default().handle(
        CreatePiece {
            id: Uuid::now_v7(),
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            project_id: Some(project_id()),
        },
        make_ctx(),
    );
    assert!(result.is_ok());
    match result.unwrap().into_iter().next().unwrap() {
        PieceEvent::PieceCreated {
            id, version, name, ..
        } => {
            assert_ne!(id, Uuid::nil());
            assert_eq!(version, AggregateVersion::INITIAL);
            assert_eq!(name, "Fundus-Piece");
        }
        _ => panic!("Expected PieceCreated"),
    }
}

#[test]
fn test_update_piece_notes_success() {
    let mut agg = make_piece();
    let n: String = "Tear on sleeve".to_string();
    let events = agg
        .handle(
            UpdatePieceNotes {
                id: agg.id,
                notes: n.clone(),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.notes, n);
}

#[test]
fn test_update_piece_notes_idempotency() {
    let agg = make_piece();
    let result = agg.handle(
        UpdatePieceNotes {
            id: agg.id,
            notes: agg.notes.clone(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
}

#[test]
fn test_update_piece_notes_wrong_version() {
    let agg = make_piece();
    let result = agg.handle(
        UpdatePieceNotes {
            id: agg.id,
            notes: "X".into(),
            project_id: Some(project_id()),
            version: AggregateVersion(99),
        },
        make_ctx(),
    );
    assert!(result.is_err());
    // The stale-version guard is a typed VersionMismatch (issue #478) so the
    // API layer can surface `concurrency.version-mismatch` (409) with the
    // expected_version / current_version extensions — not a generic
    // `domain.validation` 422.
    assert!(matches!(
        result.unwrap_err(),
        PieceError::VersionMismatch {
            expected: AggregateVersion(99),
            actual: AggregateVersion::INITIAL,
        }
    ));
}

fn assert_stale_version_rejected(
    result: Result<Vec<PieceEvent>, PieceError>,
    stale: AggregateVersion,
) {
    match result {
        Err(PieceError::VersionMismatch { expected, actual }) => {
            assert_eq!(expected, stale);
            assert_eq!(actual, AggregateVersion::INITIAL);
        }
        other => panic!("expected VersionMismatch, got {other:?}"),
    }
}

#[test]
fn test_all_mutating_commands_reject_stale_version_as_version_mismatch() {
    // Regression for issue #478: every mutating piece command's
    // optimistic-concurrency guard must surface PieceError::VersionMismatch
    // (never ValidationError) so the API layer can emit 409
    // `concurrency.version-mismatch` — not a generic `domain.validation` 422.
    let agg = make_piece();
    let stale = AggregateVersion(99);
    let detail_id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();

    assert_stale_version_rejected(
        agg.handle(
            UpdatePieceNotes {
                id: agg.id,
                notes: "x".into(),
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: detail_id,
                    subject: None,
                    text: "x".into(),
                },
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            RemovePieceDetail {
                id: agg.id,
                detail_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            LinkPiecePhoto {
                id: agg.id,
                photo_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            UnlinkPiecePhoto {
                id: agg.id,
                photo_id,
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    // Issue #534: the repertoire commands join the exhaustive guard — a
    // stale version must be a VersionMismatch (409
    // `concurrency.version-mismatch`), never a generic 422.
    assert_stale_version_rejected(
        agg.handle(
            AddPieceToSeason {
                id: agg.id,
                season_id: SeasonId::new(),
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            RemovePieceFromSeason {
                id: agg.id,
                season_id: SeasonId::new(),
                project_id: Some(project_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
}

#[test]
fn test_add_detail_success() {
    let mut agg = make_piece();
    let did = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: did,
                    subject: None,
                    text: "silk".to_string(),
                },
                project_id: Some(project_id()),
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
    let mut agg = make_piece();
    let did = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: did,
                    subject: None,
                    text: "x".to_string(),
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            RemovePieceDetail {
                id: agg.id,
                detail_id: did,
                project_id: Some(project_id()),
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
    let agg = make_piece();
    let result = agg.handle(
        RemovePieceDetail {
            id: agg.id,
            detail_id: Uuid::now_v7(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    // Issue #544: a dedicated variant, not a `ValidationError` string, so the
    // HTTP edge can answer 404 `piece-detail.not-found` instead of a 422.
    assert!(matches!(
        result.unwrap_err(),
        PieceError::DetailNotFound { .. }
    ));
}

// ---------------------------------------------------------------------------
// Issue #544: detail edit (`UpdatePieceDetail`).
// ---------------------------------------------------------------------------

/// Build a piece with one detail, replayed through the aggregate.
fn piece_with_detail(text: &str) -> (PieceAggregate, Uuid) {
    let mut agg = make_piece();
    let detail_id = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: detail_id,
                    subject: Some("Jacke".to_string()),
                    text: text.to_string(),
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    (agg, detail_id)
}

#[test]
fn test_update_detail_success() {
    let (mut agg, detail_id) = piece_with_detail("seide");
    let version_before = agg.version;
    let events = agg
        .handle(
            UpdatePieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: detail_id,
                    subject: Some("Rote Lederjacke".to_string()),
                    text: "leder".to_string(),
                },
                project_id: Some(project_id()),
                version: version_before,
            },
            make_ctx(),
        )
        .unwrap();
    // Exactly ONE event — the acceptance criterion for issue #544.
    assert_eq!(events.len(), 1);
    assert!(matches!(events[0], PieceEvent::PieceDetailUpdated { .. }));
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.len(), 1, "an edit must not add a second detail");
    assert_eq!(agg.details[0].text, "leder");
    assert_eq!(agg.details[0].subject.as_deref(), Some("Rote Lederjacke"));
    assert_eq!(agg.version, version_before.next());
}

#[test]
fn test_update_detail_keeps_position_in_details() {
    // The `details` vec has no ordering key, so an update must replace the
    // entry in place rather than remove-and-append.
    let (mut agg, detail_id) = piece_with_detail("seide");
    let second = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: second,
                    subject: None,
                    text: "second".to_string(),
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    let events = agg
        .handle(
            UpdatePieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: detail_id,
                    subject: None,
                    text: "seide, geändert".to_string(),
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    assert_eq!(agg.details.len(), 2);
    assert_eq!(agg.details[0].id, detail_id, "position must be preserved");
    assert_eq!(agg.details[0].text, "seide, geändert");
    assert_eq!(agg.details[1].id, second);
}

#[test]
fn test_update_detail_not_found_emits_no_event() {
    let (agg, _) = piece_with_detail("seide");
    let missing = Uuid::now_v7();
    let result = agg.handle(
        UpdatePieceDetail {
            id: agg.id,
            detail: PieceDetail {
                id: missing,
                subject: None,
                text: "typo".to_string(),
            },
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    // The real validation the issue asks for: an unknown `detail_id` errors
    // and the aggregate never grows a second row.
    assert!(matches!(
        result.unwrap_err(),
        PieceError::DetailNotFound { id } if id == missing
    ));
    assert_eq!(agg.details.len(), 1);
    assert_eq!(agg.version, agg.version);
}

#[test]
fn test_update_detail_version_chain() {
    // Two consecutive updates each fence on the previous ack — the same chain
    // `addDetail` relies on for the client's version reconciliation.
    let (mut agg, detail_id) = piece_with_detail("v0");
    let mut version = agg.version;
    for text in ["v1", "v2"] {
        let events = agg
            .handle(
                UpdatePieceDetail {
                    id: agg.id,
                    detail: PieceDetail {
                        id: detail_id,
                        subject: None,
                        text: text.to_string(),
                    },
                    project_id: Some(project_id()),
                    version,
                },
                make_ctx(),
            )
            .unwrap();
        test_support::replay_events(&mut agg, events);
        version = agg.version;
    }
    assert_eq!(agg.details[0].text, "v2");

    // A stale version is rejected before the detail is even looked at.
    let stale = version;
    let result = agg.handle(
        UpdatePieceDetail {
            id: agg.id,
            detail: PieceDetail {
                id: detail_id,
                subject: None,
                text: "v3".to_string(),
            },
            project_id: Some(project_id()),
            version: AggregateVersion::INITIAL,
        },
        make_ctx(),
    );
    assert!(matches!(
        result.unwrap_err(),
        PieceError::VersionMismatch { .. }
    ));
    assert_ne!(stale, AggregateVersion::INITIAL);
}

#[test]
fn test_link_photo_success() {
    let mut agg = make_piece();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPiecePhoto {
                id: agg.id,
                photo_id: pid,
                project_id: Some(project_id()),
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
    let mut agg = make_piece();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPiecePhoto {
                id: agg.id,
                photo_id: pid,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let result = agg.handle(
        LinkPiecePhoto {
            id: agg.id,
            photo_id: pid,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        PieceError::ValidationError(ref m) if m.contains("already linked")
    ));
}

#[test]
fn test_unlink_photo_success() {
    let mut agg = make_piece();
    let pid = Uuid::now_v7();
    let events = agg
        .handle(
            LinkPiecePhoto {
                id: agg.id,
                photo_id: pid,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            UnlinkPiecePhoto {
                id: agg.id,
                photo_id: pid,
                project_id: Some(project_id()),
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
    let agg = make_piece();
    let result = agg.handle(
        UnlinkPiecePhoto {
            id: agg.id,
            photo_id: Uuid::now_v7(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        PieceError::ValidationError(ref m) if m.contains("not linked")
    ));
}

/// Verify that apply() actually mutates aggregate state.
///
/// Catches mutants that replace the `apply` body with `()` — if apply is a
/// no-op the assertion below fails because the piece keeps its default
/// notes.
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = PieceAggregate::default();
    let id = Uuid::now_v7();
    let notes = "Silk lining needs repair".to_string();
    agg.apply(
        PieceEvent::PieceCreated {
            id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            notes: notes.clone(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(agg.notes, notes, "apply() should set the piece notes");
    assert_eq!(agg.id, id);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

/// Verify that UnlinkPiecePhoto checks `!self.photos.contains(...)` — if the `!`
/// is deleted the guard flips and unlinking a linked photo would be
/// rejected as if it were not linked.
#[test]
fn test_unlink_photo_uses_negation() {
    use kameo_es::Metadata;
    let mut agg = PieceAggregate::default();
    let id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();
    // Create piece with one linked photo.
    agg.apply(
        PieceEvent::PieceCreated {
            id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            notes: String::new(),
            details: Vec::new(),
            photos: vec![photo_id],
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    // Unlinking the linked photo should succeed.
    let result = agg.handle(
        UnlinkPiecePhoto {
            id,
            photo_id,
            project_id: Some(project_id()),
            version: AggregateVersion::INITIAL,
        },
        make_ctx(),
    );
    assert!(
        result.is_ok(),
        "unlinking a linked photo should succeed (guards ! negation)"
    );
}

#[test]
fn test_add_detail_accepts_enriched_detail() {
    let mut agg = make_piece();
    let did = Uuid::now_v7();
    let events = agg
        .handle(
            AddPieceDetail {
                id: agg.id,
                detail: PieceDetail {
                    id: did,
                    subject: Some("Rote Jacke".into()),
                    text: "Knöpfe vorne".into(),
                },
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.len(), 1);
    let d = &agg.details[0];
    assert_eq!(d.subject.as_deref(), Some("Rote Jacke"));
    assert_eq!(d.text, "Knöpfe vorne");
}

#[test]
fn test_piece_view_serialises_category_and_detail_is_pure_description() {
    // Issue #543: the category lives on the PieceView; the detail view is
    // pure description (subject + text).
    let view = PieceView {
        id: Uuid::now_v7(),
        name: "Rote Lederjacke".to_string(),
        category_id: Some(CostumeCategoryId::new()),
        category_name: Some("Jacke".into()),
        notes: String::new(),
        details: vec![PieceDetailView {
            id: Uuid::now_v7(),
            subject: Some("Rote Lederjacke".into()),
            text: "Knöpfe vorne".into(),
        }],
        photos: vec![],
        season_ids: vec![],
        version: AggregateVersion(1),
        updated_at: chrono::Utc::now(),
    };
    let value = serde_json::to_value(&view).expect("PieceView serializes");
    assert!(value["category_id"].is_string());
    assert_eq!(value["category_name"], "Jacke");
    let detail = &value["details"][0];
    assert_eq!(detail["subject"], "Rote Lederjacke");
    assert_eq!(detail["text"], "Knöpfe vorne");
    assert!(detail.get("category_id").is_none());
    assert!(detail.get("category_name").is_none());
}
#[test]
fn test_set_piece_category_sets_and_bumps_version() {
    let agg = make_piece();
    let cat_id = CostumeCategoryId::new();
    let events = agg
        .handle(
            SetPieceCategory {
                id: agg.id,
                category_id: Some(cat_id),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1, "a real change emits exactly one event");
    match &events[0] {
        PieceEvent::PieceCategorySet {
            id,
            category_id,
            version,
        } => {
            assert_eq!(id, &agg.id);
            assert_eq!(category_id, &Some(cat_id));
            assert_eq!(version, &agg.version.next());
        }
        other => panic!("expected PieceCategorySet, got {other:?}"),
    }
    let mut applied = PieceAggregate::default();
    test_support::replay_events(&mut applied, events);
    assert_eq!(applied.category_id, Some(cat_id));
    assert_eq!(applied.version, agg.version.next());
}

#[test]
fn test_set_piece_category_none_clears() {
    let cat_id = CostumeCategoryId::new();
    // Build an aggregate that already carries the category.
    let created = PieceEvent::PieceCreated {
        id: Uuid::now_v7(),
        name: "Fundus-Piece".to_string(),
        category_id: None,
        season_id: None,
        notes: String::new(),
        details: vec![],
        photos: vec![],
        version: AggregateVersion::INITIAL,
    };
    let set = PieceEvent::PieceCategorySet {
        id: created_id(&created),
        category_id: Some(cat_id),
        version: AggregateVersion(1),
    };
    let mut agg = PieceAggregate::default();
    agg.apply(created, kameo_es::Metadata::default());
    agg.apply(set, kameo_es::Metadata::default());
    assert_eq!(agg.category_id, Some(cat_id));

    let events = agg
        .handle(
            SetPieceCategory {
                id: agg.id,
                category_id: None,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    match &events[0] {
        PieceEvent::PieceCategorySet {
            category_id,
            version,
            ..
        } => {
            assert_eq!(category_id, &None);
            assert_eq!(version, &agg.version.next());
        }
        other => panic!("expected PieceCategorySet, got {other:?}"),
    }
}

fn created_id(event: &PieceEvent) -> Uuid {
    match event {
        PieceEvent::PieceCreated { id, .. } => *id,
        other => panic!("expected PieceCreated, got {other:?}"),
    }
}

#[test]
fn test_set_piece_category_same_value_is_a_state_based_noop() {
    // Issue #515 precedent (issue #543 decision): re-setting the category the
    // piece already carries (or clearing an empty one) emits NO event and is
    // an Ok — redelivery-safe, not a version conflict or 422.
    let cat_id = CostumeCategoryId::new();
    let id = Uuid::now_v7();
    let mut agg = PieceAggregate::default();
    agg.apply(
        PieceEvent::PieceCreated {
            id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    agg.apply(
        PieceEvent::PieceCategorySet {
            id,
            category_id: Some(cat_id),
            version: AggregateVersion(1),
        },
        kameo_es::Metadata::default(),
    );
    let events = agg
        .handle(
            SetPieceCategory {
                id,
                category_id: Some(cat_id),
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(
        events.is_empty(),
        "re-setting the same category must be a no-op, got {events:?}"
    );
    // Clearing an already-empty category is also a no-op.
    let mut empty = PieceAggregate::default();
    empty.apply(
        PieceEvent::PieceCreated {
            id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    let events = empty
        .handle(
            SetPieceCategory {
                id,
                category_id: None,
                project_id: Some(project_id()),
                version: empty.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert!(
        events.is_empty(),
        "clearing an empty category must be a no-op, got {events:?}"
    );
}

#[test]
fn test_set_piece_category_version_mismatch() {
    let agg = make_piece();
    let result = agg.handle(
        SetPieceCategory {
            id: agg.id,
            category_id: Some(CostumeCategoryId::new()),
            project_id: Some(project_id()),
            version: agg.version.next(),
        },
        make_ctx(),
    );
    assert!(
        matches!(result, Err(PieceError::VersionMismatch { .. })),
        "stale version must be refused, got {result:?}"
    );
}
/// Mutation-guard for the `PieceCategorySet` apply arm (issue #543): if the
/// arm is deleted or replaced with `()`, the aggregate silently keeps its old
/// category (and version) — both must change exactly as the event says.
#[test]
fn test_apply_piece_category_set_mutates_state() {
    use kameo_es::Metadata;
    let mut agg = PieceAggregate::default();
    let id = Uuid::now_v7();
    agg.apply(
        PieceEvent::PieceCreated {
            id,
            name: "Fundus-Piece".to_string(),
            category_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    let cat_id = CostumeCategoryId::new();
    agg.apply(
        PieceEvent::PieceCategorySet {
            id,
            category_id: Some(cat_id),
            version: AggregateVersion(1),
        },
        Metadata::default(),
    );
    assert_eq!(
        agg.category_id,
        Some(cat_id),
        "apply() must set the piece category"
    );
    assert_eq!(agg.version, AggregateVersion(1));
    // Clearing via the event arm too.
    agg.apply(
        PieceEvent::PieceCategorySet {
            id,
            category_id: None,
            version: AggregateVersion(2),
        },
        Metadata::default(),
    );
    assert!(agg.category_id.is_none(), "apply(None) must clear");
    assert_eq!(agg.version, AggregateVersion(2));
}

// ---------------------------------------------------------------------------
// Season repertoire as real aggregate state (issue #534)
// ---------------------------------------------------------------------------

fn make_piece_in_season(season_id: Option<SeasonId>) -> PieceAggregate {
    let agg = PieceAggregate::default();
    let events = agg
        .handle(
            CreatePiece {
                id: Uuid::now_v7(),
                name: "Fundus-Piece".to_string(),
                category_id: None,
                season_id,
                project_id: Some(project_id()),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = PieceAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_piece_created_initializes_repertoire_from_season_id() {
    let season = SeasonId::new();
    let agg = make_piece_in_season(Some(season));
    assert_eq!(agg.seasons, vec![season]);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
    // No repertoire season on create (legacy stream shape) → empty list.
    let bare = make_piece_in_season(None);
    assert!(bare.seasons.is_empty());
}

#[test]
fn test_add_piece_to_season_success() {
    let agg = make_piece_in_season(None);
    let season = SeasonId::new();
    let events = agg
        .handle(
            AddPieceToSeason {
                id: agg.id,
                season_id: season,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    match &events[0] {
        PieceEvent::PieceAddedToSeason {
            id,
            season_id: sid,
            version,
        } => {
            assert_eq!(*id, agg.id);
            assert_eq!(*sid, season.0);
            assert_eq!(*version, agg.version.next());
        }
        other => panic!("expected PieceAddedToSeason, got {other:?}"),
    }
    let mut replayed = PieceAggregate::default();
    test_support::replay_events(&mut replayed, events);
    assert_eq!(replayed.seasons, vec![season]);
    assert_eq!(replayed.version, agg.version.next());
}

#[test]
fn test_add_piece_to_season_idempotent_no_event() {
    // Issue #515 lesson: an already-present season is a state-based no-op —
    // Ok(vec![]) (no event, no version bump), NOT an error and NOT a new
    // event. The adapter maps this to an unchanged-version success.
    let season = SeasonId::new();
    let agg = make_piece_in_season(Some(season));
    let result = agg.handle(
        AddPieceToSeason {
            id: agg.id,
            season_id: season,
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert_eq!(result.unwrap(), Vec::<PieceEvent>::new());
}

#[test]
fn test_add_second_season_extends_repertoire() {
    // The m:n lifecycle: piece built for season 1, carried into season 2 —
    // both repertoire entries coexist.
    let s1 = SeasonId::new();
    let s2 = SeasonId::new();
    let agg = make_piece_in_season(Some(s1));
    let events = agg
        .handle(
            AddPieceToSeason {
                id: agg.id,
                season_id: s2,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    // Delta-replay: the add event applies ONTO the existing state (the
    // repertoire already holds `s1` from `PieceCreated`).
    let mut replayed = agg.clone();
    test_support::replay_events(&mut replayed, events);
    assert_eq!(replayed.seasons, vec![s1, s2]);
}

#[test]
fn test_remove_piece_from_season_success() {
    let s1 = SeasonId::new();
    let s2 = SeasonId::new();
    let agg = make_piece_in_season(Some(s1));
    let events = agg
        .handle(
            AddPieceToSeason {
                id: agg.id,
                season_id: s2,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut with_two = agg.clone();
    test_support::replay_events(&mut with_two, events);

    let remove_events = with_two
        .handle(
            RemovePieceFromSeason {
                id: with_two.id,
                season_id: s1,
                project_id: Some(project_id()),
                version: with_two.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(remove_events.len(), 1);
    match &remove_events[0] {
        PieceEvent::PieceRemovedFromSeason {
            id,
            season_id: sid,
            version,
        } => {
            assert_eq!(*id, with_two.id);
            assert_eq!(*sid, s1.0);
            assert_eq!(*version, with_two.version.next());
        }
        other => panic!("expected PieceRemovedFromSeason, got {other:?}"),
    }
    let mut replayed = with_two.clone();
    test_support::replay_events(&mut replayed, remove_events);
    assert_eq!(replayed.seasons, vec![s2]);
}

#[test]
fn test_remove_piece_from_season_idempotent_no_event() {
    // Removing a season that is not in the repertoire is the mirror no-op.
    let agg = make_piece_in_season(Some(SeasonId::new()));
    let result = agg.handle(
        RemovePieceFromSeason {
            id: agg.id,
            season_id: SeasonId::new(),
            project_id: Some(project_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    assert_eq!(result.unwrap(), Vec::<PieceEvent>::new());
}

#[test]
fn test_remove_last_season_allowed_empty_repertoire() {
    // Decision (issue #534 discussion): an empty repertoire is legitimate —
    // the authz scope falls back to the character's season. No special case
    // blocks removing the final entry.
    let s1 = SeasonId::new();
    let agg = make_piece_in_season(Some(s1));
    let events = agg
        .handle(
            RemovePieceFromSeason {
                id: agg.id,
                season_id: s1,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut replayed = PieceAggregate::default();
    test_support::replay_events(&mut replayed, events);
    assert!(replayed.seasons.is_empty());
}

#[test]
fn test_repertoire_version_chain() {
    // Each repertoire mutation bumps the aggregate version exactly once —
    // the optimistic-concurrency fence stays intact across the lifecycle.
    let s1 = SeasonId::new();
    let s2 = SeasonId::new();
    let agg = make_piece_in_season(Some(s1));
    assert_eq!(agg.version, AggregateVersion::INITIAL);

    let events = agg
        .handle(
            AddPieceToSeason {
                id: agg.id,
                season_id: s2,
                project_id: Some(project_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut v2 = agg.clone();
    test_support::replay_events(&mut v2, events);
    assert_eq!(v2.version, AggregateVersion::INITIAL.next());

    let events = v2
        .handle(
            RemovePieceFromSeason {
                id: v2.id,
                season_id: s1,
                project_id: Some(project_id()),
                version: v2.version,
            },
            make_ctx(),
        )
        .unwrap();
    let mut v3 = v2.clone();
    test_support::replay_events(&mut v3, events);
    assert_eq!(v3.version, AggregateVersion::INITIAL.next().next());
    assert_eq!(v3.seasons, vec![s2]);
}

#[test]
fn test_created_event_without_season_id_replays_to_empty_repertoire() {
    // `season_id` and `category_id` are optional on the wire (`serde(default)`):
    // a piece can be catalogued without a season, and its repertoire then
    // starts empty. `name` is required by the clean-cut model.
    let json = serde_json::json!({
        "PieceCreated": {
            "id": Uuid::now_v7(),
            "name": "Rote Lederjacke",
            "notes": "",
            "details": [],
            "photos": [],
            "version": 1
        }
    });
    let event: PieceEvent = serde_json::from_value(json).expect("PieceCreated must deserialize");
    match event {
        PieceEvent::PieceCreated {
            season_id,
            category_id,
            version,
            ..
        } => {
            assert_eq!(season_id, None);
            assert_eq!(category_id, None);
            assert_eq!(version, AggregateVersion(1));
        }
        other => panic!("expected PieceCreated, got {other:?}"),
    }
    let mut agg = PieceAggregate::default();
    test_support::replay_events(&mut agg, vec![event]);
    assert!(agg.seasons.is_empty(), "no panic, empty repertoire");
}
