// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::DomainError;
use crate::scene::commands::{CreateScene, UpdateSceneDetails};
use crate::scene::events::SceneDetails;
use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, BlockId, EpisodeId, SeriesId};

/// A bounded section of extracted script text beginning at an INT./EXT.
/// heading. The chunker retains the heading and body so the LLM receives
/// enough local context without requiring infrastructure dependencies.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct SceneChunk {
    pub index: usize,
    pub heading: String,
    pub scene_number: Option<u32>,
    pub text: String,
}

impl SceneChunk {
    pub fn extract_scenes(document: &str) -> Vec<Self> {
        extract_scenes(document)
    }
}

/// Static LLM target for script extraction. Optional fields express the
/// null-on-doubt rule: uncertain values must not be asserted by the model.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct ScriptContext {
    pub title: Option<String>,
    pub scenes: Vec<DraftScene>,
    pub uncertainties: Vec<Uncertainty>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct DraftScene {
    pub draft_ref: String,
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub summary: Option<String>,
    pub script_day: Option<String>,
    pub characters: Vec<String>,
}

impl DraftScene {
    pub fn scene_details(&self) -> SceneDetails {
        SceneDetails {
            scene_number: self.scene_number,
            location: self.location.clone(),
            mood: self.mood.clone(),
            is_schedule_set: false,
            summary: self.summary.clone(),
            script_day: self.script_day.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct Uncertainty {
    pub scene_index: usize,
    pub field: String,
    pub note: String,
    pub suggested_value: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct ShootingSchedule {
    pub block_id: Option<BlockId>,
    pub rows: Vec<ShootingScheduleRow>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct ShootingScheduleRow {
    pub row_ref: String,
    pub scene_number: Option<u32>,
    pub shooting_day_label: Option<String>,
    pub date: Option<NaiveDate>,
    pub location: Option<String>,
    pub order: Option<u32>,
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct MergedScene {
    pub scene: SceneView,
    pub schedule_rows: Vec<ShootingScheduleRow>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, ToSchema)]
pub struct MergedPreview {
    pub scenes: Vec<MergedScene>,
    pub unmatched_schedule_rows: Vec<ShootingScheduleRow>,
    pub unmatched_script_scenes: Vec<SceneView>,
}

/// Immutable scene context for deterministic schedule merging.
///
/// Prepared at the API/query boundary (authorized read) and passed into the
/// merge worker so the write-side never queries a read-model projection
/// (CQRS boundary, AGENTS.md §1). The worker only performs a deterministic
/// join of schedule rows onto these pre-loaded scenes.
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct MergeInput {
    /// The shooting schedule to merge.
    pub schedule: ShootingSchedule,
    /// Applied scenes for the target block, pre-loaded at the API boundary.
    pub scenes: Vec<SceneView>,
}

/// User decision for one draft row. A create decision leaves the aggregate id
/// absent; an update decision carries the existing id and optimistic version.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyMapping {
    pub draft_ref: String,
    pub decision: ApplyMappingDecision,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub enum ApplyMappingDecision {
    Create,
    Update {
        aggregate_id: Uuid,
        version: AggregateVersion,
    },
}

/// Existing command payloads planned by the deterministic apply planner. The
/// API/worker dispatches these through the normal command ports; this module
/// never talks to read projections or event stores.
#[derive(Debug, Clone)]
pub enum SceneApplyCommand {
    Create(CreateScene),
    Update(UpdateSceneDetails),
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ApplyGateError {
    #[error("script preview has {0} unresolved uncertainties")]
    OpenUncertainties(usize),
    #[error("schedule preview has {0} unmatched schedule rows")]
    UnmatchedScheduleRows(usize),
    #[error("schedule preview has {0} unmatched applied scenes")]
    UnmatchedScriptScenes(usize),
    #[error("no mapping decision for draft row {0}")]
    MissingMapping(String),
}

pub fn ensure_script_applyable(preview: &ScriptContext) -> Result<(), ApplyGateError> {
    if preview.uncertainties.is_empty() {
        Ok(())
    } else {
        Err(ApplyGateError::OpenUncertainties(
            preview.uncertainties.len(),
        ))
    }
}

pub fn ensure_merge_applyable(preview: &MergedPreview) -> Result<(), ApplyGateError> {
    if !preview.unmatched_schedule_rows.is_empty() {
        return Err(ApplyGateError::UnmatchedScheduleRows(
            preview.unmatched_schedule_rows.len(),
        ));
    }
    if !preview.unmatched_script_scenes.is_empty() {
        return Err(ApplyGateError::UnmatchedScriptScenes(
            preview.unmatched_script_scenes.len(),
        ));
    }
    Ok(())
}

pub fn plan_scene_apply(
    preview: &ScriptContext,
    mappings: &[ApplyMapping],
    episode_id: EpisodeId,
    series_id: Option<SeriesId>,
) -> Result<Vec<SceneApplyCommand>, ApplyGateError> {
    ensure_script_applyable(preview)?;
    let mut ordered = Vec::with_capacity(preview.scenes.len());

    for (index, draft) in preview.scenes.iter().enumerate() {
        let draft_ref = if draft.draft_ref.is_empty() {
            format!("scene-{index}")
        } else {
            draft.draft_ref.clone()
        };
        let mapping = mappings
            .iter()
            .find(|mapping| mapping.draft_ref == draft_ref)
            .ok_or_else(|| ApplyGateError::MissingMapping(draft_ref.clone()))?;
        let details = draft.scene_details();
        let command = match mapping.decision {
            ApplyMappingDecision::Create => SceneApplyCommand::Create(CreateScene {
                id: Uuid::now_v7(),
                episode_id,
                series_id,
                details,
            }),
            ApplyMappingDecision::Update {
                aggregate_id,
                version,
            } => SceneApplyCommand::Update(UpdateSceneDetails {
                id: aggregate_id,
                details,
                series_id,
                version,
            }),
        };
        ordered.push(command);
    }
    Ok(ordered)
}

/// Deterministically split a script at fuzzy INT./EXT. heading lines.
pub fn extract_scenes(document: &str) -> Vec<SceneChunk> {
    let mut chunks: Vec<SceneChunk> = Vec::new();
    for line in document.lines() {
        let trimmed = line.trim();
        if is_scene_heading(trimmed) {
            let scene_number = leading_scene_number(trimmed);
            chunks.push(SceneChunk {
                index: chunks.len(),
                heading: trimmed.to_owned(),
                scene_number,
                text: String::new(),
            });
        } else if let Some(current) = chunks.last_mut() {
            if !current.text.is_empty() {
                current.text.push('\n');
            }
            current.text.push_str(line.trim_end());
        }
    }
    for chunk in &mut chunks {
        chunk.text = chunk.text.trim().to_owned();
    }
    chunks
}

fn is_scene_heading(line: &str) -> bool {
    let normalized = line
        .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == ' ')
        .to_ascii_uppercase();
    ["INT.", "EXT.", "INT/EXT.", "INT./EXT.", "I/E."]
        .iter()
        .any(|prefix| normalized.starts_with(prefix))
}

fn leading_scene_number(line: &str) -> Option<u32> {
    let digits: String = line.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        None
    } else {
        digits.parse().ok()
    }
}

/// Join schedule rows with applied scenes by scene number. Both inputs are
/// copied into deterministic order; no fuzzy matching or LLM call is involved.
pub fn merge_schedule_to_scenes(
    schedule: &ShootingSchedule,
    scenes: &[SceneView],
) -> MergedPreview {
    let mut ordered_scenes = scenes.to_vec();
    ordered_scenes.sort_by_key(|scene| (scene.scene_number, scene.id));

    let mut rows = schedule.rows.clone();
    rows.sort_by_key(|row| (row.scene_number, row.row_ref.clone()));

    // Group scene indices by number so duplicate scene numbers (e.g. "12" and
    // "12A" both parsed as 12) all receive rows instead of the first scene
    // capturing every row and the duplicates landing in unmatched_script_scenes.
    let mut number_to_indices: std::collections::HashMap<Option<u32>, Vec<usize>> =
        std::collections::HashMap::new();
    for (index, scene) in ordered_scenes.iter().enumerate() {
        number_to_indices
            .entry(scene.scene_number)
            .or_default()
            .push(index);
    }
    let mut next_for_number: std::collections::HashMap<Option<u32>, usize> =
        std::collections::HashMap::new();

    let mut matched: Vec<Vec<ShootingScheduleRow>> = vec![Vec::new(); ordered_scenes.len()];
    let mut unmatched_schedule_rows = Vec::new();
    for row in rows {
        let group = row
            .scene_number
            .and_then(|number| number_to_indices.get(&Some(number)))
            .filter(|indices| !indices.is_empty());
        if let Some(indices) = group {
            let cursor = next_for_number.entry(row.scene_number).or_insert(0);
            // Round-robin over the group: deterministic and keeps every
            // duplicate-numbered scene populated.
            let index = indices[*cursor % indices.len()];
            *cursor += 1;
            matched[index].push(row);
        } else {
            unmatched_schedule_rows.push(row);
        }
    }

    let mut merged = Vec::new();
    let mut unmatched_script_scenes = Vec::new();
    for (index, scene) in ordered_scenes.into_iter().enumerate() {
        if matched[index].is_empty() {
            unmatched_script_scenes.push(scene.clone());
        }
        merged.push(MergedScene {
            scene,
            schedule_rows: matched[index].clone(),
        });
    }

    MergedPreview {
        scenes: merged,
        unmatched_schedule_rows,
        unmatched_script_scenes,
    }
}

/// Merge a `MergeInput` into a `MergedPreview`.
///
/// This is the CQRS-safe entry point: the caller prepares `MergeInput` at the
/// API boundary (authorized read), and the write-side worker calls this pure
/// function without touching any projection.
pub fn merge_from_input(input: &MergeInput) -> Result<MergedPreview, DomainError> {
    if input.scenes.is_empty() {
        return Err(DomainError::Conflict(
            "merge pending: block has no applied scenes yet".to_owned(),
        ));
    }
    Ok(merge_schedule_to_scenes(&input.schedule, &input.scenes))
}

#[cfg(test)]
#[path = "preview_tests.rs"]
mod preview_tests;
