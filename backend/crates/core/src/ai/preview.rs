// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use super::views::{AiImportJobId, DocumentKind, JobStatus};
use crate::error::DomainError;
use crate::scene::commands::{CreateScene, UpdateSceneDetails};
use crate::scene::events::{SceneDetails, SceneSource};
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

/// One costume extracted for a character of a draft scene.
///
/// Flat by design: the LLM has no domain ids, and the write side must not
/// resolve ids from a read-model projection (CQRS boundary). `character_name`
/// is matched against the same draft scene's `characters`; `source_quote` is the
/// fragment the extraction claims to be based on, which the server verifies
/// against the supplied chunk text before the row may reach the reviewer.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct DraftCostume {
    /// Character the costume belongs to, as written in the script.
    pub character_name: String,
    /// The garment/accessory description, in the script's own wording.
    pub description: String,
    /// Quoted fragment of the chunk this entry was extracted from.
    pub source_quote: String,
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
    /// Costumes worn by this scene's characters. Additive on the wire with a
    /// default so previews stored before this field existed still load; a
    /// preview written by this version loses the field when read by an older
    /// binary (breaking, see the change proposal).
    #[serde(default)]
    pub costumes: Vec<DraftCostume>,
}

/// A dropped costume and why it was dropped, surfaced as an `Uncertainty` so
/// the reviewer sees a missing entry instead of silently missing data.
#[derive(Debug, Clone, PartialEq)]
pub struct RejectedCostume {
    pub reason: RejectedCostumeReason,
    pub character_name: String,
    pub description: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RejectedCostumeReason {
    /// `source_quote` does not occur in the chunk the model was given.
    UngroundedQuote,
    /// The costume names a character the same scene does not list.
    UnlistedCharacter,
}

/// Keep only costumes that are (a) traceable to the supplied chunk text and
/// (b) attributable to a character of this scene; return the rejects so the
/// caller can record them as uncertainties.
///
/// Both checks are server-side on purpose: the prompt forbids invention, but a
/// prompt is an instruction, not a guarantee. Verified live that a hardened
/// prompt makes the model return the description ("trägt einen leicht
/// ölverschmierten Mechaniker-Overall"); this is what makes a hallucinated
/// entry unable to reach the reviewer.
pub fn verify_draft_costumes(scene: &mut DraftScene, chunk_text: &str) -> Vec<RejectedCostume> {
    let mut rejected = Vec::new();
    let characters: Vec<String> = scene
        .characters
        .iter()
        .map(|name| name.trim().to_lowercase())
        .collect();
    let haystack = chunk_text.to_lowercase();

    let mut kept: Vec<DraftCostume> = Vec::with_capacity(scene.costumes.len());
    for costume in std::mem::take(&mut scene.costumes) {
        let quote = costume.source_quote.trim();
        if quote.is_empty() || !haystack.contains(&quote.to_lowercase()) {
            rejected.push(RejectedCostume {
                reason: RejectedCostumeReason::UngroundedQuote,
                character_name: costume.character_name,
                description: costume.description,
            });
            continue;
        }
        let name = costume.character_name.trim().to_lowercase();
        if !characters.iter().any(|known| known == &name) {
            rejected.push(RejectedCostume {
                reason: RejectedCostumeReason::UnlistedCharacter,
                character_name: costume.character_name,
                description: costume.description,
            });
            continue;
        }
        kept.push(costume);
    }
    scene.costumes = kept;
    rejected
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

/// Typed preview payload served by `GET /v1/ai-import/jobs/{id}/preview`
/// (issue #337).
///
/// Workers persist one of three shapes depending on the job's document kind
/// and stage: `Script` (`ScriptContext`, script jobs), `Schedule`
/// (`ShootingSchedule`, schedule jobs before the merge worker runs), or
/// `Merged` (`MergedPreview`, schedule jobs after the merge). The
/// externally-tagged representation lets generated clients consume preview
/// rows structurally instead of through a runtime-validated row adapter.
/// `MergeInput` is deliberately excluded: it is worker-internal scaffolding,
/// never a renderable preview.
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
#[serde(tag = "kind", content = "data", rename_all = "snake_case")]
pub enum AiPreviewPayload {
    Script(ScriptContext),
    Schedule(ShootingSchedule),
    Merged(MergedPreview),
}

/// Typed envelope for the preview endpoint: job identity plus the parsed
/// payload. Parsing happens server-side so a corrupt blob surfaces as
/// `422 domain.validation` instead of an untyped blob the client must
/// validate at runtime.
#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct AiImportPreviewResponse {
    pub job_id: Uuid,
    pub document_kind: DocumentKind,
    pub status: JobStatus,
    pub preview: AiPreviewPayload,
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
    preview_id: AiImportJobId,
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
                // Planned by the AI apply, so the provenance is AI-extracted;
                // the document id is the import job id, the draft ref the
                // external_ref (mirrors `ApplyWorker::create_scene_reserved`).
                source: SceneSource::AiExtracted {
                    document_id: preview_id.as_uuid(),
                    external_ref: Some(draft_ref.clone()),
                    confidence: None,
                },
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

/// Deterministic, unique and document-traceable reference for a preview row.
///
/// The model's own `draft_ref` is deliberately **not** trusted. Observed live
/// on a 93-page German production script: 55 of 131 preview rows carried an
/// invented placeholder (`scene_1`, `scene_2`, …), and those placeholders are
/// reused across chunks. The apply step resolves a row against its mapping with
/// `mappings.find(|m| m.draft_ref == draft_ref)`, so a repeated reference makes
/// several preview rows resolve to the SAME decision — a silent correctness
/// bug, not a cosmetic one.
///
/// The reference is therefore built from facts the server already owns: the
/// chunk's real heading (which `extract_scenes` read out of the document) and a
/// globally unique scene ordinal. The first scene of a chunk carries the bare
/// heading; further scenes split out of the same chunk are numbered, so
/// multi-scene chunks stay distinguishable without inventing a syntax the
/// model has to guess.
pub fn stable_draft_ref(
    scene_ordinal: usize,
    chunk_heading: &str,
    index_in_chunk: usize,
) -> String {
    let base = format!("{scene_ordinal}. {}", chunk_heading.trim());
    if index_in_chunk == 0 {
        base
    } else {
        format!("{base} ({})", index_in_chunk + 1)
    }
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

/// Scene-heading prefixes in the English / Hollywood convention.
const ENGLISH_HEADING_PREFIXES: [&str; 5] = ["INT.", "EXT.", "INT/EXT.", "INT./EXT.", "I/E."];

/// Scene-heading prefixes in the German (DFF / TV production) convention.
///
/// German production scripts do not use `INT.` / `EXT.`; they use the
/// short form `I`/`A` (innen/außen) plus a time token, or the spelled-out
/// `INNENAUFNAHME` / `AUSSENAUFNAHME`. Without these a perfectly valid German
/// screenplay extracts to zero scenes and the whole import dies with
/// "script did not contain an INT./EXT. scene heading" — a format gap, not a
/// document defect.
const GERMAN_HEADING_PREFIXES: [&str; 6] = [
    "INNENAUFNAHME",
    "AUSSENAUFNAHME",
    "INNEN.",
    "AUSSEN.",
    "INNEN ",
    "AUSSEN ",
];

fn is_scene_heading(line: &str) -> bool {
    let normalized = line
        .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == ' ')
        .to_ascii_uppercase();
    ENGLISH_HEADING_PREFIXES
        .iter()
        .any(|prefix| normalized.starts_with(prefix))
        || is_german_scene_heading(&normalized)
}

/// German short form: `I`/`A`, a `/`, a time token (`T`, `N`, `AB`, `D`, …),
/// then a separator or end of line.
///
/// The separator requirement is what keeps this from matching prose: a
/// time-token length cap of two rejects words that merely start with the
/// letters (`I/TAXI`), and the required trailing delimiter rejects a word
/// glued to the token.
fn is_german_scene_heading(normalized: &str) -> bool {
    if GERMAN_HEADING_PREFIXES
        .iter()
        .any(|prefix| normalized.starts_with(prefix))
    {
        return true;
    }
    let mut chars = normalized.chars();
    match chars.next() {
        Some('I') | Some('A') => {}
        _ => return false,
    }
    if chars.next() != Some('/') {
        return false;
    }
    let mut time_token = String::new();
    // The terminator must be captured INSIDE the loop: a `for` over the
    // iterator already consumed the non-alphabetic character when the body
    // breaks, so a following `chars.next()` would read the character AFTER
    // the separator ("I/T-WOHNUNG" would test 'W' and be rejected).
    let mut terminator: Option<char> = None;
    for c in chars.by_ref() {
        if c.is_ascii_alphabetic() {
            time_token.push(c);
            if time_token.len() > 2 {
                return false;
            }
        } else {
            terminator = Some(c);
            break;
        }
    }
    if time_token.is_empty() {
        return false;
    }
    match terminator {
        None => true,
        Some(c) if c == ' ' || c == '-' || c == '.' || c == '/' => true,
        Some(_) => false,
    }
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
        return Err(DomainError::conflict(
            "merge pending: block has no applied scenes yet",
        ));
    }
    Ok(merge_schedule_to_scenes(&input.schedule, &input.scenes))
}

#[cfg(test)]
#[path = "preview_tests.rs"]
mod preview_tests;
