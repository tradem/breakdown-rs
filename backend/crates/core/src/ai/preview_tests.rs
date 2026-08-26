// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, EpisodeId};

use super::*;

fn scene(number: u32) -> SceneView {
    SceneView {
        id: Uuid::now_v7(),
        episode_id: EpisodeId::new(),
        scene_number: Some(number),
        location: None,
        mood: None,
        is_schedule_set: false,
        summary: None,
        script_day: None,
        shooting_day_ids: Vec::new(),
        assigned_characters: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: Utc.timestamp_opt(0, 0).single().unwrap(),
    }
}

#[test]
fn chunker_handles_numbered_and_unumbered_fuzzy_headings() {
    let chunks = extract_scenes(
        "1. INT. KITCHEN - DAY\nAlice enters.\n\nEXT. PARK - NIGHT\nA car waits.\n\nI/E. HOUSE - DAY\nRain.",
    );
    assert_eq!(chunks.len(), 3);
    assert_eq!(chunks[0].scene_number, Some(1));
    assert_eq!(chunks[0].text, "Alice enters.");
    assert_eq!(chunks[1].scene_number, None);
    assert_eq!(chunks[2].heading, "I/E. HOUSE - DAY");
}

#[test]
fn merge_returns_matched_and_both_unmatched_sets() {
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-2".into(),
                scene_number: Some(2),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-9".into(),
                scene_number: Some(9),
                ..Default::default()
            },
        ],
    };
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2)]);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 1);
    assert_eq!(merged.unmatched_schedule_rows[0].row_ref, "row-9");
    assert_eq!(merged.unmatched_script_scenes.len(), 1);
    assert_eq!(merged.unmatched_script_scenes[0].scene_number, Some(1));
}

#[test]
fn planner_uses_update_for_a_previously_mapped_row() {
    let preview = ScriptContext {
        title: None,
        scenes: vec![DraftScene {
            draft_ref: "scene-1".into(),
            scene_number: Some(1),
            summary: Some("revised".into()),
            ..Default::default()
        }],
        uncertainties: Vec::new(),
    };
    let existing_id = Uuid::now_v7();
    let plan = plan_scene_apply(
        &preview,
        &[ApplyMapping {
            draft_ref: "scene-1".into(),
            decision: ApplyMappingDecision::Update {
                aggregate_id: existing_id,
                version: AggregateVersion::INITIAL,
            },
        }],
        EpisodeId::new(),
        None,
    )
    .unwrap();
    assert!(
        matches!(plan.as_slice(), [SceneApplyCommand::Update(command)] if command.id == existing_id)
    );
}

#[test]
fn open_uncertainties_and_unmatched_rows_block_apply() {
    let script = ScriptContext {
        uncertainties: vec![Uncertainty {
            scene_index: 0,
            field: "location".into(),
            note: "illegible".into(),
            suggested_value: Some("Kitchen".into()),
        }],
        ..Default::default()
    };
    assert!(matches!(
        ensure_script_applyable(&script),
        Err(ApplyGateError::OpenUncertainties(1))
    ));

    let merged = MergedPreview {
        unmatched_schedule_rows: vec![ShootingScheduleRow::default()],
        ..Default::default()
    };
    assert!(matches!(
        ensure_merge_applyable(&merged),
        Err(ApplyGateError::UnmatchedScheduleRows(1))
    ));

    // Remaining apply-gate branches: unmatched script scenes and a missing
    // mapping must also block the mutation.
    let unmatched_scenes = MergedPreview {
        unmatched_script_scenes: vec![scene(1)],
        ..Default::default()
    };
    assert!(matches!(
        ensure_merge_applyable(&unmatched_scenes),
        Err(ApplyGateError::UnmatchedScriptScenes(1))
    ));

    let unmapped = ScriptContext {
        scenes: vec![DraftScene::default()],
        ..Default::default()
    };
    assert!(matches!(
        plan_scene_apply(&unmapped, &[], EpisodeId::new(), None),
        Err(ApplyGateError::MissingMapping(_))
    ));
}

#[test]
fn merge_from_input_blocks_on_empty_scenes() {
    let input = MergeInput {
        schedule: ShootingSchedule::default(),
        scenes: Vec::new(),
    };
    assert!(matches!(
        merge_from_input(&input),
        Err(DomainError::Conflict { .. })
    ));
}

#[test]
fn merge_from_input_joins_schedule_to_scenes() {
    let input = MergeInput {
        schedule: ShootingSchedule {
            block_id: None,
            rows: vec![ShootingScheduleRow {
                row_ref: "row-1".into(),
                scene_number: Some(1),
                ..Default::default()
            }],
        },
        scenes: vec![scene(1), scene(2)],
    };
    let merged = merge_from_input(&input).unwrap();
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
    assert_eq!(merged.unmatched_schedule_rows.len(), 0);
    assert_eq!(merged.unmatched_script_scenes.len(), 1);
    assert_eq!(merged.unmatched_script_scenes[0].scene_number, Some(2));
}

// ===========================================================================
// P3.5 — SceneChunk::extract_scenes (kills return vec![])
// ===========================================================================

#[test]
fn extract_scenes_returns_non_empty_for_valid_script() {
    let chunks = extract_scenes("INT. ROOM - DAY\nHello.");
    assert!(!chunks.is_empty(), "extract_scenes should return chunks");
}

#[test]
fn extract_scenes_returns_empty_for_no_headings() {
    let chunks = extract_scenes("Just some text without headings.");
    assert!(chunks.is_empty(), "no headings means no chunks");
}

#[test]
fn extract_scenes_preserves_heading_text() {
    let chunks = extract_scenes("EXT. GARDEN - NIGHT\nCrickets chirp.");
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].heading, "EXT. GARDEN - NIGHT");
    assert_eq!(chunks[0].text, "Crickets chirp.");
}

// ===========================================================================
// P3.5 — DraftScene::scene_details (kills return Default::default())
// ===========================================================================

#[test]
fn scene_details_maps_location() {
    let draft = DraftScene {
        location: Some("Kitchen".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.location, Some("Kitchen".into()));
}

#[test]
fn scene_details_maps_mood() {
    let draft = DraftScene {
        mood: Some("Tense".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.mood, Some("Tense".into()));
}

#[test]
fn scene_details_maps_summary() {
    let draft = DraftScene {
        summary: Some("Alice enters".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.summary, Some("Alice enters".into()));
}

#[test]
fn scene_details_maps_script_day() {
    let draft = DraftScene {
        script_day: Some("Day 1".into()),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.script_day, Some("Day 1".into()));
}

#[test]
fn scene_details_maps_scene_number() {
    let draft = DraftScene {
        scene_number: Some(42),
        ..Default::default()
    };
    let details = draft.scene_details();
    assert_eq!(details.scene_number, Some(42));
}

#[test]
fn scene_details_sets_is_schedule_set_false() {
    let draft = DraftScene::default();
    let details = draft.scene_details();
    assert!(!details.is_schedule_set);
}

// ===========================================================================
// P3.5 — merge_schedule_to_scenes (kills % → /, += → *=)
// ===========================================================================

#[test]
fn merge_distributes_multiple_rows_to_same_scene_number() {
    // This tests the modulo distribution logic (cursor % indices.len())
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-a".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-b".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-c".into(),
                scene_number: Some(1),
                ..Default::default()
            },
        ],
    };
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2)]);
    // All three rows go to scene 1
    assert_eq!(merged.scenes[0].schedule_rows.len(), 3);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 0);
}

#[test]
fn merge_rotates_rows_across_same_numbered_scenes() {
    // Two scenes with scene_number=1, three rows → distribution via modulo
    let schedule = ShootingSchedule {
        block_id: None,
        rows: vec![
            ShootingScheduleRow {
                row_ref: "row-1".into(),
                scene_number: Some(1),
                ..Default::default()
            },
            ShootingScheduleRow {
                row_ref: "row-2".into(),
                scene_number: Some(1),
                ..Default::default()
            },
        ],
    };
    // Two scene(1) entries: rows should distribute across both via modulo
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(1), scene(2)]);
    assert_eq!(merged.scenes[0].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[1].schedule_rows.len(), 1);
    assert_eq!(merged.scenes[2].schedule_rows.len(), 0);
}

#[test]
fn merge_counts_unmatched_scenes_correctly() {
    let schedule = ShootingSchedule::default();
    let merged = merge_schedule_to_scenes(&schedule, &[scene(1), scene(2), scene(3)]);
    assert_eq!(merged.unmatched_script_scenes.len(), 3);
    assert_eq!(merged.scenes.len(), 3);
}
