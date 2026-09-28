// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
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
use breakdown_core::costume::*;
use breakdown_core::shared::{AggregateVersion, CostumeCategoryId, SeasonId, SeriesId};
use kameo_es::{Apply, Command};
use test_support::make_ctx;
use uuid::Uuid;

fn series_id() -> SeriesId {
    SeriesId::new()
}

fn make_costume() -> CostumeAggregate {
    let agg = CostumeAggregate::default();
    let events = agg
        .handle(
            CreateCostume {
                id: Uuid::now_v7(),
                season_id: None,
                series_id: Some(series_id()),
            },
            make_ctx(),
        )
        .unwrap();
    let mut applied = CostumeAggregate::default();
    test_support::replay_events(&mut applied, events);
    applied
}

#[test]
fn test_create_costume_success() {
    let result = CostumeAggregate::default().handle(
        CreateCostume {
            id: Uuid::now_v7(),
            season_id: None,
            series_id: Some(series_id()),
        },
        make_ctx(),
    );
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
        CostumeError::VersionMismatch {
            expected: AggregateVersion(99),
            actual: AggregateVersion::INITIAL,
        }
    ));
}

fn assert_stale_version_rejected(
    result: Result<Vec<CostumeEvent>, CostumeError>,
    stale: AggregateVersion,
) {
    match result {
        Err(CostumeError::VersionMismatch { expected, actual }) => {
            assert_eq!(expected, stale);
            assert_eq!(actual, AggregateVersion::INITIAL);
        }
        other => panic!("expected VersionMismatch, got {other:?}"),
    }
}

#[test]
fn test_all_mutating_commands_reject_stale_version_as_version_mismatch() {
    // Regression for issue #478: every mutating costume command's
    // optimistic-concurrency guard must surface CostumeError::VersionMismatch
    // (never ValidationError) so the API layer can emit 409
    // `concurrency.version-mismatch` — not a generic `domain.validation` 422.
    let agg = make_costume();
    let stale = AggregateVersion(99);
    let detail_id = Uuid::now_v7();
    let photo_id = Uuid::now_v7();

    assert_stale_version_rejected(
        agg.handle(
            UpdateCostumeNotes {
                id: agg.id,
                notes: "x".into(),
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            AssignCostumeToCharacter {
                id: agg.id,
                character_id: Uuid::now_v7(),
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            UnassignCostume {
                id: agg.id,
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            AddDetail {
                id: agg.id,
                detail: CostumeDetail {
                    id: detail_id,
                    subject: None,
                    category_id: None,
                    text: "x".into(),
                },
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            RemoveDetail {
                id: agg.id,
                detail_id,
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            LinkPhoto {
                id: agg.id,
                photo_id,
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
    assert_stale_version_rejected(
        agg.handle(
            UnlinkPhoto {
                id: agg.id,
                photo_id,
                series_id: Some(series_id()),
                version: stale,
            },
            make_ctx(),
        ),
        stale,
    );
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
                series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
                    subject: None,
                    category_id: None,
                    text: "silk".to_string(),
                },
                series_id: Some(series_id()),
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
                    subject: None,
                    category_id: None,
                    text: "x".to_string(),
                },
                series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
                series_id: Some(series_id()),
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
            series_id: Some(series_id()),
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
            season_id: None,
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
        UnlinkPhoto {
            id,
            photo_id,
            series_id: Some(series_id()),
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
    let mut agg = make_costume();
    let did = Uuid::now_v7();
    let cat_id = CostumeCategoryId::new();
    let events = agg
        .handle(
            AddDetail {
                id: agg.id,
                detail: CostumeDetail {
                    id: did,
                    subject: Some("Rote Jacke".into()),
                    category_id: Some(cat_id),
                    text: "Knöpfe vorne".into(),
                },
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.details.len(), 1);
    let d = &agg.details[0];
    assert_eq!(d.subject.as_deref(), Some("Rote Jacke"));
    assert_eq!(d.category_id, Some(cat_id));
    assert_eq!(d.text, "Knöpfe vorne");
}

#[test]
fn test_costume_view_serialises_category_and_detail_is_pure_description() {
    // Issue #543: the category lives on the CostumeView; the detail view is
    // pure description (subject + text).
    let view = CostumeView {
        id: Uuid::now_v7(),
        character_id: None,
        category_id: Some(CostumeCategoryId::new()),
        category_name: Some("Jacke".into()),
        notes: String::new(),
        details: vec![CostumeDetailView {
            id: Uuid::now_v7(),
            subject: Some("Rote Lederjacke".into()),
            text: "Knöpfe vorne".into(),
        }],
        photos: vec![],
        version: AggregateVersion(1),
        updated_at: chrono::Utc::now(),
    };
    let value = serde_json::to_value(&view).expect("CostumeView serializes");
    assert!(value["category_id"].is_string());
    assert_eq!(value["category_name"], "Jacke");
    let detail = &value["details"][0];
    assert_eq!(detail["subject"], "Rote Lederjacke");
    assert_eq!(detail["text"], "Knöpfe vorne");
    assert!(detail.get("category_id").is_none());
    assert!(detail.get("category_name").is_none());
}

#[test]
fn test_legacy_detail_event_deserialises_with_defaults() {
    // A pre-change DetailAdded payload carrying only id + text.
    let json = r#"{"id":"11111111-1111-1111-1111-111111111111","text":"old text"}"#;
    let detail: CostumeDetail = serde_json::from_str(json).expect("legacy detail parses");
    assert_eq!(detail.subject, None);
    assert_eq!(detail.category_id, None);
    assert_eq!(detail.text, "old text");
}

// ===========================================================================
// AI import apply: the create -> notes -> bind chain and its version semantics
// (openspec: ai-import-character-costumes, spec `costume-character-binding`)
// ===========================================================================

fn notes(agg: &CostumeAggregate, text: &str) -> Vec<CostumeEvent> {
    agg.handle(
        UpdateCostumeNotes {
            id: agg.id,
            notes: text.to_string(),
            series_id: Some(series_id()),
            version: agg.version,
        },
        make_ctx(),
    )
    .expect("notes accepted")
}

fn bind(agg: &CostumeAggregate, character_id: Uuid) -> Vec<CostumeEvent> {
    agg.handle(
        AssignCostumeToCharacter {
            id: agg.id,
            character_id,
            series_id: Some(series_id()),
            version: agg.version,
        },
        make_ctx(),
    )
    .expect("bind accepted")
}

/// The apply worker drives one costume through three commands and records the
/// aggregate version after each step in `projection_ai_import_mapping`. That
/// makes the **version the phase record** of a crashed apply: a retry reads the
/// stored version and re-drives only the steps that have not appended yet. This
/// test fixes the arithmetic the worker depends on — if any step ever appended
/// two events, or none, the recovery would skip or repeat a command.
#[test]
fn test_ai_apply_chain_advances_exactly_one_version_per_step() {
    let character_id = Uuid::now_v7();
    let mut agg = CostumeAggregate::default();
    let events = agg
        .handle(
            CreateCostume {
                id: Uuid::now_v7(),
                // The AI apply passes the season it resolved at the API edge so
                // a costume that cannot be bound stays visible as unassigned.
                season_id: Some(SeasonId::new()),
                series_id: Some(series_id()),
            },
            make_ctx(),
        )
        .expect("create accepted");
    test_support::replay_events(&mut agg, events);
    assert_eq!(
        agg.version,
        AggregateVersion::INITIAL,
        "step 1 (create) must land on the initial version"
    );
    assert!(
        agg.character_id.is_none(),
        "an AI costume must be created **unassigned** (D3)"
    );

    let notes_events = notes(&agg, "ölverschmierter Mechaniker-Overall");
    test_support::replay_events(&mut agg, notes_events);
    assert_eq!(agg.version, AggregateVersion(2), "step 2 (notes) = +1");
    assert_eq!(agg.notes, "ölverschmierter Mechaniker-Overall");

    let bind_events = bind(&agg, character_id);
    test_support::replay_events(&mut agg, bind_events);
    assert_eq!(agg.version, AggregateVersion(3), "step 3 (bind) = +1");
    assert_eq!(agg.character_id, Some(character_id));
}

/// Binding a costume that was created moments earlier — the normal AI-apply
/// path — must not need any version other than the one `CreateCostume` returned,
/// and a stale version must be refused as a typed `VersionMismatch` (409
/// `concurrency.version-mismatch`), never as a generic validation error.
#[test]
fn test_bind_to_a_freshly_created_costume_uses_the_created_version() {
    let character_id = Uuid::now_v7();

    // Straight after create: the created version is the only correct one.
    let mut agg = make_costume();
    assert_eq!(agg.version, AggregateVersion::INITIAL);
    let bind_events = bind(&agg, character_id);
    test_support::replay_events(&mut agg, bind_events);
    assert_eq!(agg.character_id, Some(character_id));

    // A version from before the create (0) or after a later append (2) is a
    // mismatch on the version-1 stream the apply would have been holding.
    let stale = make_costume();
    for wrong in [
        AggregateVersion(0),
        AggregateVersion(2),
        AggregateVersion(99),
    ] {
        let result = stale.handle(
            AssignCostumeToCharacter {
                id: stale.id,
                character_id,
                series_id: Some(series_id()),
                version: wrong,
            },
            make_ctx(),
        );
        assert!(
            matches!(
                result,
                Err(CostumeError::VersionMismatch { actual, .. })
                    if actual == AggregateVersion::INITIAL
            ),
            "version {wrong:?} must be a typed VersionMismatch, got {result:?}"
        );
    }
}

/// A retried apply must never bind twice. The second dispatch carries the
/// post-bind version, so it fails as a mismatch rather than appending a second
/// `CostumeAssignedToCharacter` — the worker treats the mismatch's `current`
/// version as "already applied" and does not create a second costume.
#[test]
fn test_replayed_bind_is_refused_as_a_version_mismatch_not_a_second_assignment() {
    let character_id = Uuid::now_v7();
    let mut agg = make_costume();
    let bind_events = bind(&agg, character_id);
    test_support::replay_events(&mut agg, bind_events);
    let result = agg.handle(
        AssignCostumeToCharacter {
            id: agg.id,
            character_id,
            series_id: Some(series_id()),
            // The version the worker would still be holding if the confirm
            // mapping write had crashed after the append.
            version: AggregateVersion::INITIAL,
        },
        make_ctx(),
    );
    assert!(
        matches!(
            result,
            Err(CostumeError::VersionMismatch {
                expected: AggregateVersion::INITIAL,
                actual: AggregateVersion(2),
            })
        ),
        "a replayed bind must surface as VersionMismatch, got {result:?}"
    );
}

/// The binding stays exactly what the manual path is: `character_id`, and
/// nothing else. A repertoire `season_id` on create is the pre-existing
/// issue-#453 binding (a costume may stand in several seasons) and does not make
/// the aggregate season-scoped, so an AI costume is reachable through the same
/// queries as a hand-written one.
#[test]
fn test_ai_created_costume_carries_only_the_character_binding() {
    let agg = make_costume();
    assert!(agg.character_id.is_none());
    assert!(agg.details.is_empty());
    assert!(agg.photos.is_empty());
    // No season/episode/scene field exists on the aggregate to carry one.
    let fields = format!("{agg:?}");
    for forbidden in ["season_id", "episode_id", "scene_id", "draft_ref"] {
        assert!(
            !fields.contains(forbidden),
            "the Costume aggregate must not gain a {forbidden} scope field, got {fields}"
        );
    }
}

// ===========================================================================
// Issue #543 — one costume = one category: `SetCostumeCategory` and the
// replay-derivation rule (first detail category wins while the costume has
// none; within one event: `detail_id` ASC).
// ===========================================================================

fn detail_with(id: Uuid, category: Option<CostumeCategoryId>) -> CostumeDetail {
    CostumeDetail {
        id,
        subject: None,
        category_id: category,
        text: "Beschreibung".into(),
    }
}

#[test]
fn test_set_costume_category_sets_and_bumps_version() {
    let agg = make_costume();
    let cat_id = CostumeCategoryId::new();
    let events = agg
        .handle(
            SetCostumeCategory {
                id: agg.id,
                category_id: Some(cat_id),
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1, "a real change emits exactly one event");
    match &events[0] {
        CostumeEvent::CostumeCategorySet {
            id,
            category_id,
            version,
        } => {
            assert_eq!(id, &agg.id);
            assert_eq!(category_id, &Some(cat_id));
            assert_eq!(version, &agg.version.next());
        }
        other => panic!("expected CostumeCategorySet, got {other:?}"),
    }
    let mut applied = CostumeAggregate::default();
    test_support::replay_events(&mut applied, events);
    assert_eq!(applied.category_id, Some(cat_id));
    assert_eq!(applied.version, agg.version.next());
}

#[test]
fn test_set_costume_category_none_clears() {
    let cat_id = CostumeCategoryId::new();
    // Build an aggregate that already carries the category.
    let created = CostumeEvent::CostumeCreated {
        id: Uuid::now_v7(),
        character_id: None,
        season_id: None,
        notes: String::new(),
        details: vec![],
        photos: vec![],
        version: AggregateVersion::INITIAL,
    };
    let set = CostumeEvent::CostumeCategorySet {
        id: created_id(&created),
        category_id: Some(cat_id),
        version: AggregateVersion(1),
    };
    let mut agg = CostumeAggregate::default();
    agg.apply(created, kameo_es::Metadata::default());
    agg.apply(set, kameo_es::Metadata::default());
    assert_eq!(agg.category_id, Some(cat_id));

    let events = agg
        .handle(
            SetCostumeCategory {
                id: agg.id,
                category_id: None,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    assert_eq!(events.len(), 1);
    match &events[0] {
        CostumeEvent::CostumeCategorySet {
            category_id,
            version,
            ..
        } => {
            assert_eq!(category_id, &None);
            assert_eq!(version, &agg.version.next());
        }
        other => panic!("expected CostumeCategorySet, got {other:?}"),
    }
}

fn created_id(event: &CostumeEvent) -> Uuid {
    match event {
        CostumeEvent::CostumeCreated { id, .. } => *id,
        other => panic!("expected CostumeCreated, got {other:?}"),
    }
}

#[test]
fn test_set_costume_category_same_value_is_a_state_based_noop() {
    // Issue #515 precedent (issue #543 decision): re-setting the category the
    // costume already carries (or clearing an empty one) emits NO event and is
    // an Ok — redelivery-safe, not a version conflict or 422.
    let cat_id = CostumeCategoryId::new();
    let id = Uuid::now_v7();
    let mut agg = CostumeAggregate::default();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    agg.apply(
        CostumeEvent::CostumeCategorySet {
            id,
            category_id: Some(cat_id),
            version: AggregateVersion(1),
        },
        kameo_es::Metadata::default(),
    );
    let events = agg
        .handle(
            SetCostumeCategory {
                id,
                category_id: Some(cat_id),
                series_id: Some(series_id()),
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
    let mut empty = CostumeAggregate::default();
    empty.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
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
            SetCostumeCategory {
                id,
                category_id: None,
                series_id: Some(series_id()),
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
fn test_set_costume_category_version_mismatch() {
    let agg = make_costume();
    let result = agg.handle(
        SetCostumeCategory {
            id: agg.id,
            category_id: Some(CostumeCategoryId::new()),
            series_id: Some(series_id()),
            version: agg.version.next(),
        },
        make_ctx(),
    );
    assert!(
        matches!(result, Err(CostumeError::VersionMismatch { .. })),
        "stale version must be refused, got {result:?}"
    );
}

#[test]
fn test_legacy_created_with_categorized_detail_derives_category() {
    // Legacy stream (issue #543 replay rule): only `CostumeCreated` with a
    // categorized detail, no `CostumeCategorySet` — the aggregate derives the
    // costume category from the detail.
    let cat_id = CostumeCategoryId::new();
    let detail_id = Uuid::now_v7();
    let mut agg = CostumeAggregate::default();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id: Uuid::now_v7(),
            character_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![detail_with(detail_id, Some(cat_id))],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    assert_eq!(
        agg.category_id,
        Some(cat_id),
        "the aggregate must derive the costume category from the legacy detail"
    );
}

#[test]
fn test_legacy_created_with_uncategorized_detail_stays_uncategorised() {
    let mut agg = CostumeAggregate::default();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id: Uuid::now_v7(),
            character_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![detail_with(Uuid::now_v7(), None)],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    assert!(agg.category_id.is_none());
}

#[test]
fn test_derivation_contradictory_details_first_detail_id_wins() {
    // Within one event: `detail_id` ASC — the detail with the lowest id wins.
    let first = CostumeCategoryId::new();
    let second = CostumeCategoryId::new();
    let low_detail = Uuid::now_v7();
    let high_detail = Uuid::now_v7();
    assert!(low_detail < high_detail, "UUIDv7 ordering precondition");
    // Deliberately out of order in the event payload.
    let details = vec![
        detail_with(high_detail, Some(second)),
        detail_with(low_detail, Some(first)),
    ];
    let mut agg = CostumeAggregate::default();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id: Uuid::now_v7(),
            character_id: None,
            season_id: None,
            notes: String::new(),
            details,
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    assert_eq!(
        agg.category_id,
        Some(first),
        "the lowest detail_id's category must win within one event"
    );
}

#[test]
fn test_detail_added_adopts_category_while_empty_and_never_overwrites() {
    let adopted = CostumeCategoryId::new();
    let later = CostumeCategoryId::new();
    let id = Uuid::now_v7();
    let mut agg = CostumeAggregate::default();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
            season_id: None,
            notes: String::new(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion::INITIAL,
        },
        kameo_es::Metadata::default(),
    );
    // First categorized detail is adopted.
    agg.apply(
        CostumeEvent::DetailAdded {
            id,
            detail: detail_with(Uuid::now_v7(), Some(adopted)),
            version: AggregateVersion(1),
        },
        kameo_es::Metadata::default(),
    );
    assert_eq!(agg.category_id, Some(adopted));
    // A later categorized detail never overwrites the adopted category.
    agg.apply(
        CostumeEvent::DetailAdded {
            id,
            detail: detail_with(Uuid::now_v7(), Some(later)),
            version: AggregateVersion(2),
        },
        kameo_es::Metadata::default(),
    );
    assert_eq!(
        agg.category_id,
        Some(adopted),
        "first-wins: a later categorized detail must not overwrite"
    );
    // An explicit CostumeCategorySet always wins over the derivation.
    let explicit = CostumeCategoryId::new();
    agg.apply(
        CostumeEvent::CostumeCategorySet {
            id,
            category_id: Some(explicit),
            version: AggregateVersion(3),
        },
        kameo_es::Metadata::default(),
    );
    assert_eq!(agg.category_id, Some(explicit));
}

/// Mutation-guard for the `CostumeCategorySet` apply arm (issue #543): if the
/// arm is deleted or replaced with `()`, the aggregate silently keeps its old
/// category (and version) — both must change exactly as the event says.
#[test]
fn test_apply_costume_category_set_mutates_state() {
    use kameo_es::Metadata;
    let mut agg = CostumeAggregate::default();
    let id = Uuid::now_v7();
    agg.apply(
        CostumeEvent::CostumeCreated {
            id,
            character_id: None,
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
        CostumeEvent::CostumeCategorySet {
            id,
            category_id: Some(cat_id),
            version: AggregateVersion(1),
        },
        Metadata::default(),
    );
    assert_eq!(
        agg.category_id,
        Some(cat_id),
        "apply() must set the costume category"
    );
    assert_eq!(agg.version, AggregateVersion(1));
    // Clearing via the event arm too.
    agg.apply(
        CostumeEvent::CostumeCategorySet {
            id,
            category_id: None,
            version: AggregateVersion(2),
        },
        Metadata::default(),
    );
    assert!(agg.category_id.is_none(), "apply(None) must clear");
    assert_eq!(agg.version, AggregateVersion(2));
}
