// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

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
    /// The episode in effect at this chunk's heading, from the deterministic
    /// `Ep.:` marker scan (issue #581). `None` for a script without markers —
    /// the row then applies to the explicitly picked target episode.
    pub episode: Option<DraftEpisode>,
    pub text: String,
}

impl SceneChunk {
    pub fn extract_scenes(document: &str) -> Vec<Self> {
        extract_scenes(document)
    }
}

/// One episode of the source script, as the deterministic marker scan (and,
/// as a fallback, the LLM) read it out of the document. Production scripts
/// mark episodes as `Ep.: 3 (Titel)` — on the first page and repeated in the
/// page headers (issue #581). Metadata only: it groups preview rows for the
/// reviewer and names the episode an apply may create; it never resolves an
/// aggregate id (that is the reviewer's per-group decision).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct DraftEpisode {
    /// The number after `Ep.:`, when the marker carried one.
    pub number: Option<i32>,
    /// The title in the trailing parentheses, when the marker carried one.
    pub title: Option<String>,
}

impl DraftEpisode {
    /// The preview-wide key that groups rows of the same episode. Number and
    /// title are alternative identities: a script that only titles its
    /// episodes still groups, a script that only numbers them too. Rows whose
    /// marker carried neither cannot be grouped — they apply to the default
    /// target episode.
    #[must_use]
    pub fn group_key(&self) -> Option<String> {
        if let Some(number) = self.number {
            return Some(format!("ep:{number}"));
        }
        match self.title.as_deref() {
            Some(title) if !title.trim().is_empty() => Some(format!("ep-t:{}", title.trim())),
            _ => None,
        }
    }
}

/// Read one `Ep.: 3 (Titel)` / `Ep: 3 (Titel)` marker out of a line.
///
/// Detection runs on the same normalized copy as the scene-heading detector
/// (invisible Word→PDF look-alikes folded to ASCII). The marker may sit
/// anywhere in the line — page headers carry it next to the `Block:` field —
/// but the `Ep` token is matched case-sensitively so a lowercase prose mention
/// (`"ep 3 war besser"`) never flips the episode in effect. Every `Ep`
/// occurrence on the line is tried; the FIRST one that yields a number or a
/// title wins. Normalization replaces every character one-for-one, so
/// character indices align with the original line — the returned title keeps
/// the document's verbatim bytes.
fn episode_marker(line: &str) -> Option<DraftEpisode> {
    let normalized = normalize_for_heading_detection(line);
    // `Ep` + a run of separator characters (`.` / `:` / spaces — `Ep. : 2`
    // after NBSP folding) + 1-4 digits. The digit cap keeps a page number
    // glued to a stray `Ep` from parsing as a huge episode number.
    //
    // EVERY `Ep` occurrence is tried, not only the first: `Ep` also occurs
    // inside capitalized words (`Epilog – Ep.: 5 (Titel)`), and stopping at
    // the first occurrence would parse the wrong one. A candidate preceded by
    // an alphanumeric character is not a token start (`DEp`), and a candidate
    // whose number/title does not sit CLOSE to the token is prose
    // (`Episode 12`, `Epilog (Fortsetzung)`) — the scan moves on to the next
    // occurrence.
    let chars: Vec<char> = normalized.chars().collect();
    let ep_char = "Ep".chars().count();
    normalized
        .match_indices("Ep")
        .map(|(byte_offset, _)| marker_char_index(&normalized, byte_offset))
        .filter(|&start| start == 0 || !chars[start - 1].is_alphanumeric())
        .find_map(|start| parse_marker_at(line, &chars, start + ep_char))
}

/// Try to read a `DraftEpisode` from `chars[from..]` — the characters after
/// one `Ep` token. `None` means this occurrence is not a marker; the caller
/// continues with the next.
fn parse_marker_at(line: &str, chars: &[char], from: usize) -> Option<DraftEpisode> {
    // The title's `(` must sit within this many characters of the token (or
    // of the number) — the observed format is `Ep.: 5 (Titel)`; a far-away
    // parenthesis belongs to different text, not to this marker.
    const TITLE_WINDOW: usize = 3;
    let mut i = from;
    while i < chars.len() && matches!(chars[i], '.' | ':' | ' ') {
        i += 1;
    }
    let digit_start = i;
    while i < chars.len() && chars[i].is_ascii_digit() {
        i += 1;
    }
    let digits: String = chars[digit_start..i].iter().collect();
    if !digits.is_empty() && digits.len() <= 4 {
        // Numbers parse losslessly into i32 (≤ 4 digits).
        let number = digits.parse::<i32>().ok()?;
        let title = title_in_parentheses_bounded(line, chars, i, TITLE_WINDOW);
        return Some(DraftEpisode {
            number: Some(number),
            title,
        });
    }
    // No usable number: only a closely-following `(Titel)` form is
    // recognizable — otherwise this `Ep` is a word, not a marker.
    let title = title_in_parentheses_bounded(line, chars, i, TITLE_WINDOW)?;
    Some(DraftEpisode {
        number: None,
        title: Some(title),
    })
}

/// Character index of a byte offset found in `text`.
fn marker_char_index(text: &str, byte_offset: usize) -> usize {
    text[..byte_offset].chars().count()
}

/// The first `(…)` group of `text` whose `(` opens within `window` characters
/// after character index `from`, when one is present and non-blank. Scans the
/// ORIGINAL line: character indices align with the normalized copy, but the
/// bytes must stay verbatim.
fn title_in_parentheses_bounded(
    text: &str,
    chars: &[char],
    from: usize,
    window: usize,
) -> Option<String> {
    let mut open = None;
    for (offset, character) in chars.iter().skip(from).take(window).enumerate() {
        if *character == '(' {
            open = Some(from + offset);
            break;
        }
    }
    let open = open?;
    let mut title = String::new();
    for character in text.chars().skip(open + 1) {
        if character == ')' {
            break;
        }
        title.push(character);
    }
    // No closing parenthesis means the group never closed — not a title.
    if !text
        .chars()
        .skip(open + 1)
        .any(|character| character == ')')
    {
        return None;
    }
    let title = title.trim();
    if title.is_empty() {
        return None;
    }
    Some(title.to_owned())
}

/// The distinct episode group references of a preview, in first-seen order.
///
/// The apply endpoint validates the request's per-group targets against this
/// list: a group the preview does not carry is a client bug, not a domain
/// refusal.
#[must_use]
pub fn episode_group_refs(preview: &ScriptContext) -> Vec<String> {
    let mut refs: Vec<String> = Vec::new();
    for episode in preview
        .scenes
        .iter()
        .filter_map(|scene| scene.episode.as_ref())
    {
        if let Some(key) = episode.group_key()
            && !refs.contains(&key)
        {
            refs.push(key);
        }
    }
    refs
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
    /// The episode this row belongs to (issue #581). Additive on the wire with
    /// a default so previews stored before this field existed still load;
    /// `None` applies the row to the explicitly picked target episode.
    #[serde(default)]
    pub episode: Option<DraftEpisode>,
}

/// A dropped costume and why it was dropped, surfaced as an `Uncertainty` so
/// the reviewer sees a missing entry instead of silently missing data.
#[derive(Debug, Clone, PartialEq)]
pub struct RejectedCostume {
    pub reason: RejectedCostumeReason,
    pub character_name: String,
    pub description: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RejectedCostumeReason {
    /// `source_quote` does not occur in the chunk the model was given.
    UngroundedQuote,
    /// The costume names a character the same scene does not list.
    UnlistedCharacter,
}

impl RejectedCostumeReason {
    /// Stable slug. `Display` is what the apply/preview narratives are built
    /// from, so a reviewer-facing note must not change shape when the variant is
    /// renamed — and a client can branch on it without parsing prose.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::UngroundedQuote => "ungrounded_quote",
            Self::UnlistedCharacter => "unlisted_character",
        }
    }
}

impl std::fmt::Display for RejectedCostumeReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Fold a quoted fragment for the grounding check: case-insensitively, and with
/// every run of whitespace collapsed to a single space.
///
/// Whitespace must be folded because a screenplay wraps dialogue and action over
/// lines and a model quoting across the wrap emits one space where the document
/// has a newline. Without this a genuinely quoted fragment fails the check purely
/// because of the line break — a false rejection, and the more typeset the
/// script, the more often it fires. Word content is still compared verbatim: no
/// stemming and no Unicode folding of `ss`/`ß` or `ae`/`ä`, because past this
/// point the check stops proving the text actually said it.
fn grounded_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut pending_space = false;
    for ch in text.chars() {
        if ch.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.extend(ch.to_lowercase());
    }
    out
}

/// Normalise a character name into the identity key that binds a costume to its
/// figure and deduplicates one figure across the scenes of a single preview.
///
/// Only case and whitespace are folded away. Models write the same figure as
/// `BEN`, `Ben` and ` ben ` inside one run (observed live), and a trailing space
/// must not turn a figure's costume into an orphan. Nothing else is normalised:
/// `Anna Maria` and `Ann Maria` stay distinct on purpose, because folding more
/// would be the fuzzy matching the apply spec forbids.
pub fn character_identity(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut pending_space = false;
    for ch in name.chars() {
        if ch.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.extend(ch.to_lowercase());
    }
    out
}

/// Prefix of the mapping `draft_ref` that holds a figure shared by several draft
/// rows.
///
/// A `Character` is a **season** concept, not a scene concept: one script names
/// the same figures in dozens of scenes (measured live: 268 character mentions
/// over 131 scenes). Keying the idempotency row by the scene row that mentioned
/// the name would therefore create one aggregate per mention and destroy exactly
/// the continuity this application exists to manage, so the figure's row is keyed
/// by its normalised name under this prefix instead.
///
/// The prefix keeps the two key spaces disjoint by construction: a scene
/// reference produced by [`stable_draft_ref`] always begins with the scene
/// ordinal, never with `@`.
pub const CHARACTER_REF_PREFIX: &str = "@character/";

/// The mapping reference for the figure identified by `identity`.
pub fn character_mapping_ref(identity: &str) -> String {
    format!("{CHARACTER_REF_PREFIX}{identity}")
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
        .map(|n| character_identity(n))
        .collect();
    let haystack = grounded_text(chunk_text);

    let mut kept: Vec<DraftCostume> = Vec::with_capacity(scene.costumes.len());
    for costume in std::mem::take(&mut scene.costumes) {
        let quote = grounded_text(&costume.source_quote);
        if quote.is_empty() || !haystack.contains(&quote) {
            rejected.push(RejectedCostume {
                reason: RejectedCostumeReason::UngroundedQuote,
                character_name: costume.character_name,
                description: costume.description,
            });
            continue;
        }
        let name = character_identity(&costume.character_name);
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

/// Why the reviewer is shown an uncertainty.
///
/// The distinction is what the apply gate turns on. It did not exist before the
/// costume work: the gate blocked a whole preview on *any* uncertainty, which is
/// right for a field the model could not read, but would have made a single
/// rejected costume row unappliable for an entire 85-chunk import — with a paid
/// re-import as the only remedy, since a stored preview is immutable and a
/// reviewer has no way to dismiss an entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum UncertaintyKind {
    /// The extraction could not decide a field with certainty. Blocking: the
    /// value the row would take is genuinely unknown.
    #[default]
    FieldAmbiguity,
    /// A row the server removed — a costume whose quote is not in the supplied
    /// text, or that named a figure the scene does not list. Recorded so the
    /// reviewer sees a *missing entry* instead of concluding the script had no
    /// costuming (design D5), but the data that survived is not uncertain, so it
    /// does not gate the apply.
    DroppedRow,
}

impl UncertaintyKind {
    /// Whether an entry of this kind blocks an apply.
    #[must_use]
    pub fn blocks_apply(self) -> bool {
        matches!(self, Self::FieldAmbiguity)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct Uncertainty {
    pub scene_index: usize,
    pub field: String,
    pub note: String,
    pub suggested_value: Option<String>,
    /// `serde(default)` so a preview stored before this field existed keeps
    /// blocking exactly as it did: an absent kind is a `FieldAmbiguity`.
    #[serde(default)]
    pub kind: UncertaintyKind,
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
    /// Per-costume-row decisions of this draft row. Absent ordinals default to
    /// accepted, so a request written before this field existed (or one where
    /// the reviewer touched nothing) still applies everything that was extracted.
    #[serde(default)]
    pub costume_decisions: Vec<CostumeDecision>,
}

/// Reviewer decision for one costume row of a draft row. A costume is accepted
/// or rejected *independently of its scene* (spec `ai-import`: the preview
/// exposes each costume row for its own decision).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct CostumeDecision {
    /// Index into the draft row's `costumes` list.
    pub ordinal: usize,
    /// `false` rejects the costume: no `Costume` is created and the scene row is
    /// unaffected.
    pub accepted: bool,
}

impl ApplyMapping {
    /// Whether the reviewer accepted costume row `ordinal` of this draft row.
    #[must_use]
    pub fn costume_accepted(&self, ordinal: usize) -> bool {
        self.costume_decisions
            .iter()
            .find(|decision| decision.ordinal == ordinal)
            .is_none_or(|decision| decision.accepted)
    }
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

/// The reviewer's decision for ONE episode group of a preview (issue #581):
/// apply the group's rows to an existing episode, or create a new one. The
/// number comes from the document's `Ep.:` marker; the API edge pre-checks it
/// against the series' existing episodes (409 `episode.number-already-exists`,
/// #404 doctrine).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EpisodeTarget {
    Existing { episode_id: EpisodeId },
    Create { number: i32, name: Option<String> },
}

/// One episode group's target, keyed by the group reference
/// ([`DraftEpisode::group_key`]) the preview carries per row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct EpisodeGroupPlan {
    pub episode_ref: String,
    pub target: EpisodeTarget,
}

/// The episode one planned row applies to, resolved by the planner.
///
/// `Existing` covers both the explicit default target and a group mapped to
/// an existing episode — dispatch is identical. `New` carries the group's
/// create payload; the apply worker creates the episode (idempotently, via
/// the `episode` mapping row) before the row's scene dispatches. The wrapped
/// `CreateScene` of a `New` row still carries the request's default episode
/// id as a placeholder — dispatch resolves the real id from the created
/// aggregate and never reads the placeholder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlannedEpisode {
    Existing(EpisodeId),
    New {
        episode_ref: String,
        number: i32,
        name: Option<String>,
    },
}

/// One figure a draft row names, planned for creation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CharacterApplyPlan {
    /// Position of the name inside the draft row's own `characters` list; used
    /// for reporting only — the idempotency row is keyed by [`Self::identity`].
    pub ordinal: usize,
    /// Name **verbatim** from the draft. The aggregate stores the script's own
    /// wording untouched: a figure extracted as `BEN` stays `BEN`, one extracted
    /// as `Ben` stays `Ben`. Normalisation happens in [`character_identity`],
    /// which is a *matching* key and never what gets written.
    pub name: String,
    /// [`character_identity`] of `name` — the preview-wide key of this figure.
    pub identity: String,
}

/// One costume of a draft row, planned as `CreateCostume` +
/// `UpdateCostumeNotes` + `AssignCostumeToCharacter`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CostumeApplyPlan {
    /// Position inside the row's `costumes` list. With the row's `draft_ref`
    /// this is the idempotency key `(preview_id, draft_ref, 'costume', ordinal)`
    /// so two costumes of one figure in one scene stay distinct (design D4).
    pub ordinal: usize,
    /// The figure this costume binds to, by preview-wide identity.
    pub character_identity: String,
    /// The figure's name as the draft wrote it (reporting only).
    pub character_name: String,
    /// Garment description in the script's own wording; carried into the domain
    /// as the costume's notes (design D8).
    pub description: String,
    /// Quoted fragment the extraction was based on.
    pub source_quote: String,
}

/// Everything one accepted draft row applies: its scene, the figures it names,
/// and the costumes of those figures.
///
/// Deliberately without `PartialEq`: the wrapped scene commands carry freshly
/// generated aggregate ids, so a structural comparison of two plans could never
/// hold. Tests compare [`Self::characters`] and [`Self::costumes`] and `matches!`
/// on the scene command.
#[derive(Debug, Clone)]
pub struct SceneApplyPlan {
    pub draft_ref: String,
    /// The episode this row applies to, resolved from the request's group
    /// targets (issue #581). Rows without draft episode metadata — and groups
    /// the reviewer mapped to an existing episode — resolve to `Existing`.
    pub episode: PlannedEpisode,
    pub scene: SceneApplyCommand,
    pub characters: Vec<CharacterApplyPlan>,
    pub costumes: Vec<CostumeApplyPlan>,
}

/// The full apply plan of one reviewed preview.
#[derive(Debug, Clone, Default)]
pub struct ScriptApplyPlan {
    pub scenes: Vec<SceneApplyPlan>,
    /// Costume rows the plan dropped because no figure of the same row carries
    /// them. Reported, never silent (design D5).
    pub unapplied_costumes: Vec<UnappliedCostume>,
}

/// Why a costume row did not become a `Costume`. Shown to the reviewer as
/// *missing with a reason* instead of as a successful apply.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct UnappliedCostume {
    pub draft_ref: String,
    pub ordinal: usize,
    pub character_name: String,
    pub description: String,
    pub reason: UnappliedCostumeReason,
    /// Short diagnostic (e.g. the rejection the aggregate returned). The UI
    /// branches on [`Self::reason`], never on this text.
    #[serde(default)]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum UnappliedCostumeReason {
    /// No figure of the same draft row carries this costume, so it has nothing
    /// to bind to. Creating it would produce an ownerless costume.
    CharacterNotPlanned,
    /// `CreateCharacter` was rejected, so the figure the costume belongs to does
    /// not exist.
    CharacterUnavailable,
    /// `CreateCostume` itself was rejected, so the costume does not exist at all.
    CreateRejected,
    /// The costume exists but its extracted description could not be written to
    /// it, so the row stopped before the binding.
    NotesRejected,
    /// The costume exists but `AssignCostumeToCharacter` was rejected; it stays
    /// unassigned and correctable (spec `costume-character-binding`).
    BindingRejected,
    /// The costume exists and is bound to its figure, but `AddCostumeBeat` was
    /// refused by the scene (issue #546 §5.8) — e.g. a concurrent manual edit
    /// removed the figure from the scene between the assign and the beat. The
    /// scene relation is missing while the costume itself is fine: this must
    /// never look like the plan-time drop ([`Self::CharacterNotPlanned`]),
    /// where the costume never came into existence at all.
    BeatRejected,
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
    /// The request mapped a group the preview does not carry (issue #581).
    /// A client bug surfaced as its own refusal so the grouped apply screen
    /// can point at the stale group instead of failing the whole apply.
    #[error("no episode group {0} in the preview")]
    MissingEpisodeGroup(String),
}

pub fn ensure_script_applyable(preview: &ScriptContext) -> Result<(), ApplyGateError> {
    let blocking = preview
        .uncertainties
        .iter()
        .filter(|uncertainty| uncertainty.kind.blocks_apply())
        .count();
    if blocking == 0 {
        Ok(())
    } else {
        Err(ApplyGateError::OpenUncertainties(blocking))
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

/// Plan the apply of one reviewed script preview.
///
/// A row yields its **scene** command, the **figures** it names and the
/// **costumes** of those figures, in that dispatch order: a costume binds only
/// to a figure the same row planned (spec `costume-character-binding`), so the
/// prerequisite is planned first and the worker never has to look one up.
/// The mapping reference of one draft row, falling back to its position for a
/// row the model left without a reference.
///
/// Shared by the planner and the apply worker: they must resolve a row to the
/// same reference the mapping is keyed by, or a retry would look one row up or
/// down and silently re-dispatch the wrong aggregate.
#[must_use]
pub fn draft_row_ref(draft: &DraftScene, index: usize) -> String {
    if draft.draft_ref.is_empty() {
        format!("scene-{index}")
    } else {
        draft.draft_ref.clone()
    }
}

pub fn plan_scene_apply(
    preview: &ScriptContext,
    mappings: &[ApplyMapping],
    episode_id: EpisodeId,
    series_id: Option<SeriesId>,
    preview_id: AiImportJobId,
    episode_groups: &[EpisodeGroupPlan],
) -> Result<ScriptApplyPlan, ApplyGateError> {
    ensure_script_applyable(preview)?;
    let mut plan = ScriptApplyPlan::default();

    for (index, draft) in preview.scenes.iter().enumerate() {
        let draft_ref = draft_row_ref(draft, index);
        let mapping = mappings
            .iter()
            .find(|mapping| mapping.draft_ref == draft_ref)
            .ok_or_else(|| ApplyGateError::MissingMapping(draft_ref.clone()))?;
        // A row with episode metadata is resolved against the request's group
        // targets; a group the request forgot is a client bug, not a default.
        // Everything else — no metadata, ungroupable metadata, and every
        // `Update` decision — applies to the explicitly picked target episode.
        let episode = draft
            .episode
            .as_ref()
            .and_then(DraftEpisode::group_key)
            .map(|group_ref| {
                let group = episode_groups
                    .iter()
                    .find(|group| group.episode_ref == group_ref)
                    .ok_or_else(|| ApplyGateError::MissingEpisodeGroup(group_ref.clone()))?;
                match &group.target {
                    EpisodeTarget::Existing { episode_id } => {
                        Ok(PlannedEpisode::Existing(*episode_id))
                    }
                    EpisodeTarget::Create { number, name } => Ok(PlannedEpisode::New {
                        episode_ref: group_ref,
                        number: *number,
                        name: name.clone(),
                    }),
                }
            })
            .transpose()?
            .unwrap_or(PlannedEpisode::Existing(episode_id));
        let details = draft.scene_details();
        let scene = match mapping.decision {
            ApplyMappingDecision::Create => SceneApplyCommand::Create(CreateScene {
                id: Uuid::now_v7(),
                // Placeholder for `PlannedEpisode::New` rows — dispatch
                // resolves the created episode's id and ignores this field.
                episode_id: match &episode {
                    PlannedEpisode::Existing(episode_id) => *episode_id,
                    PlannedEpisode::New { .. } => episode_id,
                },
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

        // A row that names no figure plans none (the "Block 100 / Tag 1" outline
        // case), and a name written twice inside one row is still one figure.
        let mut characters: Vec<CharacterApplyPlan> = Vec::with_capacity(draft.characters.len());
        for (ordinal, name) in draft.characters.iter().enumerate() {
            let identity = character_identity(name);
            if identity.is_empty() || characters.iter().any(|known| known.identity == identity) {
                continue;
            }
            characters.push(CharacterApplyPlan {
                ordinal,
                name: name.clone(),
                identity,
            });
        }

        // A costume binds to a figure of THIS row. Extraction already rejects an
        // unattributable costume, so an unmatched name here means a preview that
        // never went through `verify_draft_costumes`: report it instead of
        // creating a costume that has nothing to bind to.
        let mut costumes: Vec<CostumeApplyPlan> = Vec::with_capacity(draft.costumes.len());
        for (ordinal, costume) in draft.costumes.iter().enumerate() {
            if !mapping.costume_accepted(ordinal) {
                continue;
            }
            let identity = character_identity(&costume.character_name);
            let Some(character) = characters.iter().find(|known| known.identity == identity) else {
                plan.unapplied_costumes.push(UnappliedCostume {
                    draft_ref: draft_ref.clone(),
                    ordinal,
                    character_name: costume.character_name.clone(),
                    description: costume.description.clone(),
                    reason: UnappliedCostumeReason::CharacterNotPlanned,
                    detail: None,
                });
                continue;
            };
            costumes.push(CostumeApplyPlan {
                ordinal,
                character_identity: character.identity.clone(),
                character_name: character.name.clone(),
                description: costume.description.clone(),
                source_quote: costume.source_quote.clone(),
            });
        }

        plan.scenes.push(SceneApplyPlan {
            draft_ref,
            episode,
            scene,
            characters,
            costumes,
        });
    }
    Ok(plan)
}

/// One costume beat slot of a figure's lane: the costume in plan order plus
/// its PER-FIGURE position, which is what the `scene_costume_beat` mapping
/// rows are addressed by (issue #546 §5.8).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CostumeBeatSlot<'a> {
    /// Position of this costume among the figure's beats of the row,
    /// 0..n-1 in plan order — deliberately NOT the row-flat `ordinal`, which
    /// two figures would collide on.
    pub per_figure_order: usize,
    pub costume: &'a CostumeApplyPlan,
}

/// One figure's lane of the scene-apply chain: the figure itself plus its
/// costume beats, filtered from the row's flat costume list (issue #546
/// §5.8). Pure re-grouping — no extraction behaviour, no LLM call.
#[derive(Debug, Clone)]
pub struct SceneBeatLane<'a> {
    pub character: &'a CharacterApplyPlan,
    /// The figure's costumes of this row, plan order kept, numbered per
    /// figure 0..n-1. A costume whose identity matches no figure of the row
    /// never appears in any lane — [`ScriptApplyPlan::unapplied_costumes`]
    /// already reported it at plan time.
    pub beats: Vec<CostumeBeatSlot<'a>>,
}

/// Re-group a draft row's flat costume list into per-figure beat lanes.
///
/// The extraction produces `costumes` flat across all figures with the
/// ordinal as a PER-SCENE position, while `AddCostumeBeat` orders per figure
/// (aggregate-computed `max + 1`) and the beat mapping rows need a
/// collision-free per-figure address. This function is the single place
/// that defines the mapping between the two: filter the row's costumes by
/// the lane figure's identity, keep the plan order, number 0..n-1 per
/// figure.
pub fn scene_beat_lanes(row: &SceneApplyPlan) -> Vec<SceneBeatLane<'_>> {
    row.characters
        .iter()
        .map(|character| {
            let mut per_figure_order = 0usize;
            let beats = row
                .costumes
                .iter()
                .filter(|costume| costume.character_identity == character.identity)
                .map(|costume| {
                    let slot = CostumeBeatSlot {
                        per_figure_order,
                        costume,
                    };
                    per_figure_order += 1;
                    slot
                })
                .collect();
            SceneBeatLane { character, beats }
        })
        .collect()
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
///
/// Heading *detection* runs on a normalized copy of each line (see
/// [`normalize_for_heading_detection`]); the stored heading stays the
/// document's verbatim bytes — it is the identity (`stable_draft_ref`) and
/// the grounding text the model receives, so silently rewriting it would
/// desynchronize `source_quote` verification.
pub fn extract_scenes(document: &str) -> Vec<SceneChunk> {
    let mut chunks: Vec<SceneChunk> = Vec::new();
    // The episode in effect at the current line: the last `Ep.:` marker seen
    // so far (page headers repeat it, which is harmless — same value). A chunk
    // stamps the episode that was in effect at its heading line (issue #581).
    let mut current_episode: Option<DraftEpisode> = None;
    for line in document.lines() {
        let trimmed = line.trim();
        if let Some(episode) = episode_marker(trimmed) {
            current_episode = Some(episode);
        }
        if is_scene_heading(trimmed) {
            let scene_number = leading_scene_number(&normalize_for_heading_detection(trimmed));
            chunks.push(SceneChunk {
                index: chunks.len(),
                heading: trimmed.to_owned(),
                scene_number,
                episode: current_episode.clone(),
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

/// Word→PDF text extraction substitutes invisible look-alikes for the plain
/// ASCII separators the heading grammar expects: non-breaking spaces
/// (U+00A0, U+202F, …) for spaces, en/em/figure dashes (U+2013, U+2014,
/// U+2212) and the non-breaking hyphen (U+2011) for `-`. A production script
/// exported from Word arrives with exactly these bytes, and the ASCII-strict
/// detector then rejected every heading — the whole import died with
/// "script did not contain an INT./EXT. scene heading" (issue #581 user
/// report: `1 I/T - KLINIKUM / OP / Waschraum` with NBSP + en dash).
///
/// Detection-only: case is preserved (the German space-form check needs the
/// original casing to tell `INNEN WOHNUNG` from prose), and the result is
/// never stored — only fed to [`is_scene_heading`] and
/// [`leading_scene_number`].
fn normalize_for_heading_detection(line: &str) -> String {
    line.chars()
        .map(|c| match c {
            '\t' | '\u{00A0}' | '\u{2007}' | '\u{2009}' | '\u{202F}' => ' ',
            '\u{2011}' | '\u{2013}' | '\u{2014}' | '\u{2212}' => '-',
            other => other,
        })
        .collect()
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
const GERMAN_HEADING_PREFIXES: [&str; 4] = ["INNENAUFNAHME", "AUSSENAUFNAHME", "INNEN.", "AUSSEN."];

/// The spelled-out form with the place name separated by a SPACE rather than a
/// period (`INNEN WOHNUNG - TAG`). These need one more piece of evidence, see
/// [`space_form_is_heading`]: `is_scene_heading` folds case before comparing, so
/// on the folded text alone the prose line "Innen brennt noch Licht." is
/// indistinguishable from a slug line — and a false split costs a scene
/// boundary in the wrong place, one extra paid LLM call, and shifts every later
/// `stable_draft_ref` ordinal.
const GERMAN_SPACE_HEADING_PREFIXES: [&str; 2] = ["INNEN ", "AUSSEN "];

fn is_scene_heading(line: &str) -> bool {
    // Word→PDF export artifacts are normalized INSIDE the detector so every
    // caller (chunk splitting and direct tests alike) gets the robust
    // behavior; the stored heading stays verbatim (see `extract_scenes`).
    let trimmed = normalize_for_heading_detection(line)
        .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == ' ')
        .to_owned();
    let normalized = trimmed.to_ascii_uppercase();
    ENGLISH_HEADING_PREFIXES
        .iter()
        .any(|prefix| normalized.starts_with(prefix))
        || is_german_scene_heading(&normalized, &trimmed)
}

/// The discriminator for the space-separated German forms: a production script
/// writes the place name in caps (`INNEN WOHNUNG - TAG`), prose does not
/// (`Innen brennt noch Licht.`). Checked against the ORIGINAL line because
/// `normalized` has already lost exactly that information.
///
/// Byte-slicing is safe here: `to_ascii_uppercase` neither changes byte length
/// nor touches non-ASCII bytes, so an ASCII prefix matched in `normalized` sits
/// at the same byte offsets in `original`.
fn space_form_is_heading(normalized: &str, original: &str) -> bool {
    GERMAN_SPACE_HEADING_PREFIXES
        .iter()
        .find(|prefix| normalized.starts_with(**prefix))
        .is_some_and(|prefix| original[prefix.len()..].chars().all(|c| !c.is_lowercase()))
}

/// German short form: `I`/`A`, a `/`, a time token (`T`, `N`, `AB`, `D`, …),
/// then a separator or end of line.
///
/// The separator requirement is what keeps this from matching prose: a
/// time-token length cap of two rejects words that merely start with the
/// letters (`I/TAXI`), and the required trailing delimiter rejects a word
/// glued to the token.
fn is_german_scene_heading(normalized: &str, original: &str) -> bool {
    if GERMAN_HEADING_PREFIXES
        .iter()
        .any(|prefix| normalized.starts_with(prefix))
    {
        return true;
    }
    if space_form_is_heading(normalized, original) {
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
