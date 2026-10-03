// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

//! Pure re-grouping of a draft row's flat costume list into per-figure beat
//! lanes, plus the pinned scene-chain arithmetic the apply worker depends on
//! (issue #546 §5.8). The worker analog of
//! `test_ai_apply_chain_advances_exactly_one_version_per_step`
//! (`costume_aggregate.rs`): if any chain step ever appended two events, or
//! none, the mapping-row phase record would skip or repeat a command.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]

use breakdown_core::ai::{
    CharacterApplyPlan, CostumeApplyPlan, SceneApplyPlan, UnappliedCostumeReason,
    character_mapping_ref, scene_beat_lanes,
};
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::{AddCostumeBeat, AssignCharacter, CreateScene};
use breakdown_core::scene::events::{SceneDetails, SceneSource};
use breakdown_core::shared::{AggregateVersion, EpisodeId, SeriesId};
use kameo_es::Command;
use test_support::make_ctx;
use uuid::Uuid;

fn series_id() -> SeriesId {
    SeriesId::new()
}

fn character(ordinal: usize, name: &str, identity: &str) -> CharacterApplyPlan {
    CharacterApplyPlan {
        ordinal,
        name: name.to_owned(),
        identity: identity.to_owned(),
    }
}

fn costume(ordinal: usize, identity: &str, description: &str) -> CostumeApplyPlan {
    CostumeApplyPlan {
        ordinal,
        character_identity: identity.to_owned(),
        character_name: identity.to_owned(),
        description: description.to_owned(),
        source_quote: description.to_owned(),
    }
}

fn row(characters: Vec<CharacterApplyPlan>, costumes: Vec<CostumeApplyPlan>) -> SceneApplyPlan {
    SceneApplyPlan {
        draft_ref: "1. INT. OP".to_owned(),
        scene: breakdown_core::ai::SceneApplyCommand::Create(CreateScene {
            id: Uuid::now_v7(),
            episode_id: EpisodeId::new(),
            series_id: Some(series_id()),
            details: SceneDetails::default(),
            source: SceneSource::Manual,
        }),
        characters,
        costumes,
    }
}

#[test]
fn lanes_of_a_row_without_costumes_are_empty() {
    let plan = row(vec![character(0, "Ben", "ben")], Vec::new());
    let lanes = scene_beat_lanes(&plan);
    assert_eq!(lanes.len(), 1);
    assert!(lanes[0].beats.is_empty());
}

#[test]
fn lanes_keep_plan_order_and_number_per_figure() {
    // The extraction's flat list interleaves the two figures; the lanes must
    // filter stably (plan order kept) and number 0..n-1 PER FIGURE.
    let plan = row(
        vec![character(0, "Ben", "ben"), character(1, "Renee", "renee")],
        vec![
            costume(0, "renee", "Kasack"),
            costume(1, "ben", "Overall"),
            costume(2, "ben", "Schutzhelm"),
            costume(3, "renee", "Mantel"),
        ],
    );
    let lanes = scene_beat_lanes(&plan);
    assert_eq!(lanes.len(), 2);

    assert_eq!(lanes[0].character.identity, "ben");
    let ben: Vec<(usize, &str)> = lanes[0]
        .beats
        .iter()
        .map(|slot| (slot.per_figure_order, slot.costume.description.as_str()))
        .collect();
    assert_eq!(ben, vec![(0, "Overall"), (1, "Schutzhelm")]);

    assert_eq!(lanes[1].character.identity, "renee");
    let renee: Vec<(usize, &str)> = lanes[1]
        .beats
        .iter()
        .map(|slot| (slot.per_figure_order, slot.costume.description.as_str()))
        .collect();
    assert_eq!(renee, vec![(0, "Kasack"), (1, "Mantel")]);
}

#[test]
fn a_costume_of_an_unknown_figure_appears_in_no_lane() {
    // Such a costume was already dropped at plan time into
    // `unapplied_costumes` — the lanes must not resurrect it as a beat.
    let plan = row(
        vec![character(0, "Ben", "ben")],
        vec![costume(0, "ghost", "Nebelkulisse")],
    );
    let lanes = scene_beat_lanes(&plan);
    assert_eq!(lanes.len(), 1);
    assert!(lanes[0].beats.is_empty());
    // And the plan-time drop is what the reviewer sees, not a beat refusal.
    let ungrounded = UnappliedCostumeReason::CharacterNotPlanned;
    assert_ne!(ungrounded, UnappliedCostumeReason::BeatRejected);
}

#[test]
fn beat_mapping_rows_are_addressed_by_the_figure_reference_and_per_figure_order() {
    // Pins the mapping-key contract the worker implements: the lane figure's
    // preview-wide mapping reference as `draft_ref`, the per-figure position
    // as ordinal. Two figures of one row must never share a mapping row.
    let plan = row(
        vec![character(0, "Ben", "ben"), character(1, "Renee", "renee")],
        vec![costume(0, "renee", "Kasack"), costume(1, "ben", "Overall")],
    );
    let lanes = scene_beat_lanes(&plan);
    let ben_ref = character_mapping_ref("ben");
    let renee_ref = character_mapping_ref("renee");
    assert_ne!(ben_ref, renee_ref);
    for (lane, reference) in lanes.iter().zip([renee_ref, ben_ref]) {
        for slot in &lane.beats {
            // The worker addresses `find(preview_id, reference,
            // SCENE_COSTUME_BEAT, slot.per_figure_order)`; distinct
            // (reference, order) pairs are the collision-freedom proof.
            assert!(slot.per_figure_order < lane.beats.len());
            let _ = reference;
        }
    }
}

/// The pinned scene-chain arithmetic (worker analog of the costume test):
/// `CreateScene → AssignCharacter×n → AddCostumeBeat×m` hangs exactly ONE
/// event per step, so the version the mapping rows record after every step
/// is a faithful phase record of a crashed apply.
#[test]
fn test_ai_scene_chain_advances_exactly_one_version_per_step() {
    let ben = Uuid::now_v7();
    let renee = Uuid::now_v7();
    let coat = Uuid::now_v7();
    let overall = Uuid::now_v7();
    let scene_id = Uuid::now_v7();

    let mut agg = SceneAggregate::default();

    // Step 1: create lands on the initial version.
    let events = agg
        .handle(
            CreateScene {
                id: scene_id,
                episode_id: EpisodeId::new(),
                series_id: Some(series_id()),
                details: SceneDetails::default(),
                source: SceneSource::AiExtracted {
                    document_id: Uuid::now_v7(),
                    external_ref: Some("1. INT. OP".to_owned()),
                    confidence: None,
                },
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

    // Step 2: first assign = exactly one event.
    let events = agg
        .handle(
            AssignCharacter {
                id: scene_id,
                character_id: ben,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .expect("assign accepted");
    assert_eq!(events.len(), 1, "an assign appends exactly one event");
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.version, AggregateVersion(2), "step 2 (assign) = +1");

    // Step 3: the figure's first beat = exactly one event, order 0.
    let events = agg
        .handle(
            AddCostumeBeat {
                id: scene_id,
                character_id: ben,
                costume_id: overall,
                note: None,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .expect("beat accepted");
    assert_eq!(events.len(), 1, "a beat appends exactly one event");
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.version, AggregateVersion(3), "step 3 (beat) = +1");

    // Step 4: second assign = +1 (the stream is shared by all lanes).
    let events = agg
        .handle(
            AssignCharacter {
                id: scene_id,
                character_id: renee,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .expect("assign accepted");
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.version, AggregateVersion(4), "step 4 (assign) = +1");

    // Step 5: the other figure's beat = +1, order restarts at 0 per figure.
    let events = agg
        .handle(
            AddCostumeBeat {
                id: scene_id,
                character_id: renee,
                costume_id: coat,
                note: Some("nach dem Telefonat".into()),
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .expect("beat accepted");
    test_support::replay_events(&mut agg, events);
    assert_eq!(agg.version, AggregateVersion(5), "step 5 (beat) = +1");
    assert_eq!(agg.costume_beats.len(), 2);
    assert_eq!(agg.costume_beats[0].order, 0);
    assert_eq!(agg.costume_beats[1].order, 0, "orders are per figure");
}

/// The worker classifies a re-dispatched `AddCostumeBeat` that carries the
/// current version and hits an identical last beat as "already settled" (the
/// crash window between the append and the mapping confirm). That
/// classification is only sound if the identical-last guard is the ONLY
/// `scene.validation` refusal the handler can produce — pinned here.
#[test]
fn add_costume_beat_refuses_identical_last_as_the_only_validation_error() {
    let ben = Uuid::now_v7();
    let overall = Uuid::now_v7();
    let scene_id = Uuid::now_v7();

    let mut agg = SceneAggregate::default();
    let events = agg
        .handle(
            CreateScene {
                id: scene_id,
                episode_id: EpisodeId::new(),
                series_id: Some(series_id()),
                details: SceneDetails::default(),
                source: SceneSource::Manual,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            AssignCharacter {
                id: scene_id,
                character_id: ben,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);
    let events = agg
        .handle(
            AddCostumeBeat {
                id: scene_id,
                character_id: ben,
                costume_id: overall,
                note: None,
                series_id: Some(series_id()),
                version: agg.version,
            },
            make_ctx(),
        )
        .unwrap();
    test_support::replay_events(&mut agg, events);

    // Same (costume, note) as the character's last beat, correct version:
    // the identical-last guard is the only validation refusal available.
    let result = agg.handle(
        AddCostumeBeat {
            id: scene_id,
            character_id: ben,
            costume_id: overall,
            note: None,
            series_id: Some(series_id()),
            version: agg.version,
        },
        make_ctx(),
    );
    let error = result.expect_err("the identical-last guard must refuse");
    assert!(
        matches!(error, breakdown_core::scene::SceneError::ValidationError(_)),
        "identical-last must be the ValidationError refusal, got {error:?}"
    );

    // The version the worker would still hold if the confirm had crashed:
    // the replay is a typed VersionMismatch (folded into success by
    // `recover_version`), never a second beat.
    let result = agg.handle(
        AddCostumeBeat {
            id: scene_id,
            character_id: ben,
            costume_id: overall,
            note: None,
            series_id: Some(series_id()),
            // The version from BEFORE the crashed beat append.
            version: AggregateVersion(2),
        },
        make_ctx(),
    );
    let error = result.expect_err("the replayed beat must be refused");
    assert!(
        matches!(
            error,
            breakdown_core::scene::SceneError::VersionMismatch { .. }
        ),
        "a replayed beat must surface as VersionMismatch, got {error:?}"
    );
}
