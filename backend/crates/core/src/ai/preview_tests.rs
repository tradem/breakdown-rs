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
}
