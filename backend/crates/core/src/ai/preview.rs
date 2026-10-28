// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use super::views::{AiImportJobId, DocumentKind, JobStatus};
use crate::character::category::CharacterCategory;
use crate::error::DomainError;
use crate::scene::commands::{CreateScene, UpdateSceneDetails};
use crate::scene::events::{SceneDetails, SceneSource};
use crate::scene::views::SceneView;
use crate::shared::{AggregateVersion, BlockId, CostumeCategoryId, EpisodeId, ProjectId};

/// A bounded section of extracted script text beginning at an INT./EXT.
/// heading. The chunker retains the heading and body so the LLM receives
/// enough local context without requiring infrastructure dependencies.
// `PartialEq` only: `shooting_day` carries the `f32` day score (issue #722).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct SceneChunk {
    pub index: usize,
    pub heading: String,
    pub scene_number: Option<u32>,
    /// The episode in effect at this chunk's heading, from the deterministic
    /// `Ep.:` marker scan (issue #581). `None` for a script without markers —
    /// the row then applies to the explicitly picked target episode.
    pub episode: Option<DraftEpisode>,
    /// The shooting day in effect at this chunk's heading, from the
    /// deterministic day-marker scan (issue #706). `None` for a script
    /// without markers — the row then stays unscheduled unless the model's
    /// grounded `script_day` normalizes into a day group.
    #[serde(default)]
    pub shooting_day: Option<DraftShootingDay>,
    /// The canonical set-shorthand mood (`I/T`, `A/N`, `I/D`, `I/M`, `I/AB`,
    /// `A/*`, combined `I/A/T`) parsed deterministically out of the heading's
    /// interior/exterior + time-of-day tokens (issue #721). `None` when the
    /// heading carries no parsable time token — the row then keeps the
    /// model's `mood` (grounded fallback), never an invented value.
    /// Additive on the wire: previews stored before this field existed still
    /// deserialize.
    #[serde(default)]
    pub mood: Option<String>,
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

    /// The compact progress label surfaced in `AiImportProgress::
    /// episodes_seen` (issue #664): `"Ep. {number}"` when the marker carried
    /// a number, else the trimmed title when present, else `None` — an
    /// episode with neither cannot be surfaced. Deliberately *not* the raw
    /// marker text: the label is content-free metadata safe to persist.
    #[must_use]
    pub fn display_label(&self) -> Option<String> {
        if let Some(number) = self.number {
            return Some(format!("Ep. {number}"));
        }
        match self.title.as_deref() {
            Some(title) if !title.trim().is_empty() => Some(title.trim().to_owned()),
            _ => None,
        }
    }
}

/// One shooting day of the source script, as the deterministic marker scan
/// (and, as a fallback, the LLM's grounded `script_day`) read it out of the
/// document (issue #706). Production scripts repeat day columns in the scene
/// index (`Tag 1`, `1. Spieltag` — the 294.pdf SCRIPT-REPORT format). Metadata
/// only: it groups preview rows for the reviewer and names the day an apply
/// may create; it never resolves an aggregate id (that is the reviewer's
/// per-group decision). `PartialEq` only: the `score` field (issue #722) is
/// an `f32` and cannot derive `Eq`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct DraftShootingDay {
    /// The day number the marker carried, e.g. `1` for `Tag 1` — the
    /// normalized identity that groups scenes filmed on the same day
    /// regardless of the marker's spelling.
    pub number: Option<i32>,
    /// The marker's verbatim text (or, for the LLM fallback, the model's
    /// `script_day` as written) — display-only. First occurrence wins.
    pub label: Option<String>,
    /// Hybrid quality score of the day group's day assignment (issue #722),
    /// set by the extraction worker's best-effort decision pass and shared
    /// by every row of the group. `None` without a decision model / failed
    /// pass. Additive on the wire.
    #[serde(default)]
    pub score: Option<f32>,
}

impl DraftShootingDay {
    /// The preview-wide key that groups rows of the same shooting day. The
    /// number is the identity a marker carries; a day the model reported
    /// without a parseable number groups by its verbatim label. A day with
    /// neither cannot be grouped — its rows apply unscheduled.
    #[must_use]
    pub fn group_key(&self) -> Option<String> {
        if let Some(number) = self.number {
            return Some(format!("day:{number}"));
        }
        match self.label.as_deref() {
            Some(label) if !label.trim().is_empty() => Some(format!("day-l:{}", label.trim())),
            _ => None,
        }
    }

    /// The compact reviewer-facing label: the verbatim marker text when one
    /// was captured, else the synthesized `"Tag {number}"` — a day with
    /// neither cannot be surfaced.
    #[must_use]
    pub fn display_label(&self) -> Option<String> {
        if let Some(label) = self
            .label
            .as_deref()
            .map(str::trim)
            .filter(|label| !label.is_empty())
        {
            return Some(label.to_owned());
        }
        self.number.map(|number| format!("Tag {number}"))
    }
}

/// Normalize a model-reported `script_day` into a [`DraftShootingDay`]
/// (issue #706 post-extraction guard).
///
/// The deterministic scan is authoritative; this fallback only runs when a
/// chunk carried no marker. A label the marker parser reads a number out of
/// (`"Tag 1"`) normalizes onto the same group key the scan would have
/// produced — the two sources cannot disagree about identity. An unparseable
/// label (`"Drehwoche 2"`) still groups by its verbatim text, exactly like
/// character names group verbatim; `None` (blank) stays unscheduled — never
/// invented.
#[must_use]
pub fn parse_script_day(label: &str) -> Option<DraftShootingDay> {
    if let Some(day) = day_marker(label) {
        return Some(day);
    }
    let label = label.trim();
    if label.is_empty() {
        return None;
    }
    Some(DraftShootingDay {
        number: None,
        label: Some(label.to_owned()),
        score: None,
    })
}

/// Whether `chars[start..]` begins with `kw`, ASCII-case-insensitively.
fn keyword_at(chars: &[char], start: usize, kw: &[char]) -> bool {
    start + kw.len() <= chars.len()
        && chars[start..start + kw.len()]
            .iter()
            .zip(kw.iter())
            .all(|(a, b)| a.to_lowercase().eq(b.to_lowercase()))
}

/// Whether `line` consists of the day marker and nothing else — a page
/// header or a bare scene-index day column, not prose that merely mentions
/// a day (CodeRabbit review, issue #706).
///
/// Compares the whitespace-normalized line against the label `day_marker`
/// built for the match, ASCII-case-insensitively: an uppercase page header
/// (`TAG 1`) matches the reconstructed `"Tag 1"`, while dialogue ("Tag 3
/// war schlimm.") carries trailing words and never matches.
fn is_standalone_day_marker(line: &str, day: &DraftShootingDay) -> bool {
    let collapsed = normalize_for_heading_detection(line)
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ");
    day.label
        .as_deref()
        .is_some_and(|label| label.eq_ignore_ascii_case(&collapsed))
}

/// Read one shooting-day marker out of a line (issue #706).
///
/// Detected forms: `Tag 1` / `Day 1` (a day word followed by 1-3 digits),
/// `Spieltag 1` / `Drehtag 1` (a compound day word followed by digits), and
/// `1. Spieltag` (digits, an optional dot, then the compound word). Detection
/// runs on the same normalized copy as the scene-heading detector (invisible
/// Word→PDF look-alikes folded to ASCII) and is ASCII-case-insensitive so
/// uppercase page headers (`TAG 1`) read the same as scene-index columns
/// (`Tag 1`).
///
/// The day word must be a whole token: the character before it must not be
/// alphanumeric, so a weekday (`Montag 12`, `Freitag`) or any other word
/// ending in `-tag` never parses as shooting day 12. `Spieltag`/`Drehtag`
/// are tried BEFORE the bare `Tag` word for the same reason — their trailing
/// `tag` is token-internal. A bare `TAG` as the German time-of-day in a
/// heading carries no digits and therefore never matches.
fn day_marker(line: &str) -> Option<DraftShootingDay> {
    let normalized = normalize_for_heading_detection(line);
    let chars: Vec<char> = normalized.chars().collect();
    // The compound words first: their `tag` suffix must not be re-matched by
    // the bare-day scan below.
    for (compound, display) in [("spieltag", "Spieltag"), ("drehtag", "Drehtag")] {
        let kw_len = compound.chars().count();
        let mut start = 0usize;
        while let Some(found) = find_keyword(&chars, start, compound) {
            start = found + 1;
            // Whole-token check on the left edge.
            if found > 0 && chars[found - 1].is_alphanumeric() {
                continue;
            }
            // `N. Spieltag` — digits, an optional dot and spaces before the word.
            if let Some(day) = digits_before(&chars, found) {
                return Some(DraftShootingDay {
                    number: Some(day),
                    label: Some(format!("{day}. {display}")),
                    score: None,
                });
            }
            // `Spieltag 1` — digits after the word.
            if let Some(day) = digits_after(&chars, found + kw_len) {
                return Some(DraftShootingDay {
                    number: Some(day),
                    label: Some(format!("{display} {day}")),
                    score: None,
                });
            }
        }
    }
    // Bare day word: `Tag 1` / `Day 1`.
    for bare in ["tag", "day"] {
        let kw_len = bare.chars().count();
        let mut start = 0usize;
        while let Some(found) = find_keyword(&chars, start, bare) {
            start = found + 1;
            if found > 0 && chars[found - 1].is_alphanumeric() {
                continue;
            }
            if let Some(day) = digits_after(&chars, found + kw_len) {
                return Some(DraftShootingDay {
                    number: Some(day),
                    score: None,
                    label: Some(if bare == "day" {
                        format!("Day {day}")
                    } else {
                        format!("Tag {day}")
                    }),
                });
            }
        }
    }
    None
}

/// Next char index at which `keyword` occurs in `chars`, searching from `from`.
fn find_keyword(chars: &[char], from: usize, keyword: &str) -> Option<usize> {
    // Collected ONCE per call: `find_keyword` runs at every char index of
    // every document line, so a per-position allocation would dominate the
    // extraction of a large document (CodeRabbit review, issue #706).
    let kw: Vec<char> = keyword.chars().collect();
    (from..chars.len()).find(|&i| keyword_at(chars, i, &kw))
}

/// Read 1-3 digits (and the spaces before them) walking BACKWARD from a
/// compound day word, tolerating one trailing dot (`1. Spieltag`). Returns
/// the parsed day number, or `None` when no digit run sits directly before
/// the word.
fn digits_before(chars: &[char], word_start: usize) -> Option<i32> {
    let mut i = word_start;
    // Tolerate one dot directly attached to the digits (`1. Spieltag`) —
    // but a dot followed by more letters is prose (`Nr. 2 Spieltag` is
    // still fine; only the dot-digit gap matters).
    while i > 0 && chars[i - 1].is_whitespace() {
        i -= 1;
    }
    if i > 0 && chars[i - 1] == '.' {
        i -= 1;
    }
    while i > 0 && chars[i - 1].is_whitespace() {
        i -= 1;
    }
    let digit_end = i;
    while i > 0 && chars[i - 1].is_ascii_digit() {
        i -= 1;
    }
    let digits: String = chars[i..digit_end].iter().collect();
    if digits.is_empty() || digits.len() > 3 {
        return None;
    }
    let number = digits.parse::<i32>().ok()?;
    // The digit run's own left edge must be a token start too: `12.1.
    // Spieltag`'s trailing `1` is part of an ordinal, not a day number.
    if i > 0 && (chars[i - 1].is_alphanumeric() || chars[i - 1] == '.') {
        return None;
    }
    Some(number)
}

/// Read 1-3 digits after `from`, skipping spaces. Returns the parsed day
/// number, or `None`.
fn digits_after(chars: &[char], from: usize) -> Option<i32> {
    let mut i = from;
    while i < chars.len() && chars[i].is_whitespace() {
        i += 1;
    }
    let digit_start = i;
    while i < chars.len() && chars[i].is_ascii_digit() {
        i += 1;
    }
    let digits: String = chars[digit_start..i].iter().collect();
    if digits.is_empty() || digits.len() > 3 {
        return None;
    }
    digits.parse::<i32>().ok()
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

/// The distinct shooting-day group references of a preview, in first-seen
/// order (issue #706). Mirrors [`episode_group_refs`]: the apply endpoint
/// validates the request's per-day decisions against this list — a group the
/// preview does not carry is a client bug, not a domain refusal.
#[must_use]
pub fn shooting_day_group_refs(preview: &ScriptContext) -> Vec<String> {
    let mut refs: Vec<String> = Vec::new();
    for day in preview
        .scenes
        .iter()
        .filter_map(|scene| scene.shooting_day.as_ref())
    {
        if let Some(key) = day.group_key()
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

/// One constituent garment of a [`DraftOutfit`].
///
/// Screenplays rarely enumerate the garments of a standard look: they state
/// `DR. KOCH (in OP)` or `PATIENT (in KHK)`. The pieces are therefore
/// **context-derived** from the outfit — grounded through the outfit's quote,
/// never individually against the chunk text (design D1).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct DraftPiece {
    /// Garment name as the wardrobe department would file it (`OP-Kasack`,
    /// `KHK-Hose`, `Gummistiefel`).
    pub name: String,
    /// Category the piece belongs to, when the model could name one from the
    /// canonical vocabulary (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`,
    /// `Accessoires`). Resolved against the season's categories at the API
    /// edge; an unknown hint leaves the piece uncategorized (never an error).
    #[serde(default)]
    pub category_hint: Option<String>,
    /// Free-form detail from the script (condition, colour, material).
    #[serde(default)]
    pub description: Option<String>,
}

/// How a [`DraftOutfit`] came into existence.
///
/// The distinction is what the grounding check turns on: an explicitly quoted
/// outfit is verified verbatim against the chunk, a derived one is a look the
/// model composed from a shorthand the block named. Both are grounded at the
/// outfit level; neither carries a per-piece quote.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DraftOutfitOrigin {
    /// The block names the look (parenthetical, `Kostümbild` note, shorthand
    /// such as `OP` or `KHK`) and the outfit quotes that fragment.
    #[default]
    ExplicitQuote,
    /// The model derived the look from the block's prose; the pieces are
    /// context-derived.
    Derived,
}

/// One outfit extracted for a character of a draft scene.
///
/// Flat by design: the LLM has no domain ids, and the write side must not
/// resolve ids from a read-model projection (CQRS boundary). `character_name`
/// is matched against the same draft scene's `characters`; `source_quote` is the
/// fragment the extraction claims to be based on, which the server verifies
/// against the supplied chunk text before the row may reach the reviewer. The
/// outfit's `pieces` ride along with it: a grounded outfit may carry garment
/// names the script never wrote (design D1).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct DraftOutfit {
    /// Character the outfit belongs to, as written in the script.
    pub character_name: String,
    /// Display name of the look (`OP-Kleidung`, `Mechaniker-Overall`).
    pub name: String,
    /// Free-form notes in the script's own wording — the full description the
    /// wardrobe department needs beyond the name.
    #[serde(default)]
    pub notes: Option<String>,
    /// Quoted fragment of the chunk this outfit was extracted from.
    pub source_quote: String,
    /// Whether the block named the look explicitly (see [`DraftOutfitOrigin`]).
    #[serde(default)]
    pub origin: DraftOutfitOrigin,
    /// The constituent garments, `0..n`. Empty is a valid answer: the outfit is
    /// then applied as a look without pieces.
    #[serde(default)]
    pub pieces: Vec<DraftPiece>,
}

/// One figure a draft row names, with its extracted role type (issue #677).
///
/// The category is **grounded**: `MainCast` only when the document truly does
/// not say otherwise (the prompt classifies from the cast-section headings —
/// "Darsteller" / "Gastrollen" / "Statisten" / "Komparseren" — and inline
/// notes). A classification the model is unsure about surfaces as an
/// `Uncertainty` instead of silently shipping a wrong category.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct DraftCharacter {
    /// The name **verbatim** from the script (the same contract as the
    /// pre-#677 plain string entries).
    pub name: String,
    /// `serde(default)` so a preview (or a model response) without the field
    /// keeps the grounded default — old stored previews load unchanged.
    #[serde(default)]
    pub category: CharacterCategory,
}

impl From<&str> for DraftCharacter {
    /// The wire-compatibility construction: a plain name string becomes a
    /// figure with the grounded default category (exactly what the
    /// untagged deserializer does for pre-#677 stored previews).
    fn from(name: &str) -> Self {
        Self {
            name: name.to_owned(),
            category: CharacterCategory::default(),
        }
    }
}

/// Backward-compatible shape for the draft row's `characters` list: plain
/// name strings (pre-#677 stored previews and model responses) and the typed
/// [`DraftCharacter`] objects both deserialize.
#[derive(Deserialize)]
#[serde(untagged)]
enum DraftCharacterRepr {
    Named(String),
    Typed(DraftCharacter),
}

/// `serde(deserialize_with)` for [`DraftScene::characters`] (issue #677).
fn deserialize_draft_characters<'de, D>(deserializer: D) -> Result<Vec<DraftCharacter>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let reprs = Vec::<DraftCharacterRepr>::deserialize(deserializer)?;
    Ok(reprs
        .into_iter()
        .map(|repr| match repr {
            DraftCharacterRepr::Named(name) => DraftCharacter {
                name,
                category: CharacterCategory::default(),
            },
            DraftCharacterRepr::Typed(character) => character,
        })
        .collect())
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct DraftScene {
    pub draft_ref: String,
    pub scene_number: Option<u32>,
    pub location: Option<String>,
    pub mood: Option<String>,
    pub summary: Option<String>,
    pub script_day: Option<String>,
    /// The figures this row names, each with its extracted role type (issue
    /// #677). Backward compatible on the wire: a preview stored before the
    /// category existed carries plain name strings, which deserialize to the
    /// grounded `MainCast` default via [`deserialize_draft_characters`].
    #[serde(default, deserialize_with = "deserialize_draft_characters")]
    pub characters: Vec<DraftCharacter>,
    /// Outfits worn by this scene's characters (OpenSpec change
    /// `ai-import-outfit-and-pieces`). Additive on the wire with a default so
    /// previews stored before this field existed still load; a preview written
    /// by this version loses the field when read by an older binary (breaking,
    /// see the change proposal). The former `costumes` field is gone: its flat
    /// `description` cannot express the outfit/piece split.
    #[serde(default)]
    pub outfits: Vec<DraftOutfit>,
    /// The episode this row belongs to (issue #581). Additive on the wire with
    /// a default so previews stored before this field existed still load;
    /// `None` applies the row to the explicitly picked target episode.
    #[serde(default)]
    pub episode: Option<DraftEpisode>,
    /// The shooting day this row was extracted for (issue #706). Additive on
    /// the wire with a default so previews stored before this field existed
    /// still load; `None` leaves the row unscheduled. The deterministic day
    /// scan is authoritative; the model's verbatim `script_day` normalizes
    /// into this field only when the scan found no marker for the chunk.
    #[serde(default)]
    pub shooting_day: Option<DraftShootingDay>,
    /// Hybrid quality score of the extracted scene (issue #722),
    /// `0.0..=1.0` — calibrated Decision Model probabilities blended with
    /// deterministic grounding signals. `None` when no decision model is
    /// configured or the best-effort scoring pass failed (honest
    /// degradation, never a fabricated value). Additive on the wire.
    #[serde(default)]
    pub scene_score: Option<f32>,
    /// Hybrid quality score of the TL;DR `summary` (issue #722). `Some(0.0)`
    /// when `sanitize_meta_summary` had to rewrite the summary; `None` when
    /// the row has no summary (outline-only block) or no scoring pass ran.
    #[serde(default)]
    pub synopsis_score: Option<f32>,
    /// Structured rubric sub-scores (issue #722) — the reward-signal
    /// foundation for the `0.5.x` automatic prompt optimization loop.
    #[serde(default)]
    pub scoring: Option<super::decision::DecisionRubric>,
}

/// A dropped outfit and why it was dropped, surfaced as an `Uncertainty` so
/// the reviewer sees a missing entry instead of silently missing data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RejectedOutfit {
    pub reason: RejectedOutfitReason,
    pub character_name: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RejectedOutfitReason {
    /// `source_quote` does not occur in the chunk the model was given.
    UngroundedQuote,
    /// The outfit names a character the same scene does not list.
    UnlistedCharacter,
}

impl RejectedOutfitReason {
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

impl std::fmt::Display for RejectedOutfitReason {
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

/// Normalise a character name into the identity key that binds an outfit to its
/// figure and deduplicates one figure across the scenes of a single preview.
///
/// Only case and whitespace are folded away. Models write the same figure as
/// `BEN`, `Ben` and ` ben ` inside one run (observed live), and a trailing space
/// must not turn a figure's outfit into an orphan. Nothing else is normalised:
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

/// Keep only outfits that are (a) traceable to the supplied chunk text and
/// (b) attributable to a character of this scene; return the rejects so the
/// caller can record them as uncertainties.
///
/// Both checks are server-side on purpose: the prompt forbids invention, but a
/// prompt is an instruction, not a guarantee. Grounding runs at the **outfit**
/// level (design D1): screenplays name a look by shorthand (`"in OP"`) and never
/// enumerate its garments, so grounding each individual piece would reject every
/// genuinely derived garment. A rejected outfit takes its pieces with it — they
/// exist only as part of that look.
pub fn verify_draft_outfits(scene: &mut DraftScene, chunk_text: &str) -> Vec<RejectedOutfit> {
    let mut rejected = Vec::new();
    let characters: Vec<String> = scene
        .characters
        .iter()
        .map(|c| character_identity(&c.name))
        .collect();
    let haystack = grounded_text(chunk_text);

    let mut kept: Vec<DraftOutfit> = Vec::with_capacity(scene.outfits.len());
    for outfit in std::mem::take(&mut scene.outfits) {
        let quote = grounded_text(&outfit.source_quote);
        if quote.is_empty() || !haystack.contains(&quote) {
            rejected.push(RejectedOutfit {
                reason: RejectedOutfitReason::UngroundedQuote,
                character_name: outfit.character_name,
                name: outfit.name,
            });
            continue;
        }
        let name = character_identity(&outfit.character_name);
        if !characters.iter().any(|known| known == &name) {
            rejected.push(RejectedOutfit {
                reason: RejectedOutfitReason::UnlistedCharacter,
                character_name: outfit.character_name,
                name: outfit.name,
            });
            continue;
        }
        kept.push(outfit);
    }
    scene.outfits = kept;
    rejected
}

/// Conservative markers of a META-summary (issue #668): prose that describes
/// a block's *shape or emptiness* instead of its content. Matched
/// case-insensitively against the whitespace-folded summary.
const META_SUMMARY_MARKERS: &[&str] = &[
    // The six textual variants observed live (issue #668 test session,
    // mistral-large-3 via eurouter, 45 of 95 scenes) all descend from this
    // shape: "Outline-style block with heading and day marker only. No
    // characters, costumes, or props described."
    "outline-style block",
    "outline style block",
    "outline-style-block",
    "heading and day marker only",
    "no characters, costumes, or props",
    "no characters, costumes or props",
    "nothing happens in this",
    "this block contains no",
    // German variants of the same meta-sentence (the extraction prompt's
    // other language) — conservative, content-describing phrasings only.
    "keine charaktere, kostüme",
    "keine figuren, kostüme",
    "nichts passiert in dieser szene",
    "nichts passiert in diesem block",
    "kein inhalt",
    "keine handlung",
    "nur eine überschrift",
    "nur eine zwischenüberschrift",
];

/// Whether `summary` is a meta-description of the block's shape/emptiness
/// rather than scene content (issue #668).
///
/// Deliberately conservative: only the closed marker list above matches —
/// a leading-phrase heuristic ("This block …") was evaluated and rejected:
/// "This block party turns chaotic…" is a legitimate summary a false
/// positive would destroy. The cost of a missed meta-sentence is one ugly
/// list row; the cost of a false positive is a destroyed scene summary.
#[must_use]
pub fn is_meta_summary(summary: &str) -> bool {
    let folded = grounded_text(summary).to_lowercase();
    !folded.is_empty()
        && META_SUMMARY_MARKERS
            .iter()
            .any(|marker| contains_marker_word(&folded, marker))
}

/// Boundary-aware marker match (CodeRabbit review, issue #668): a marker
/// must end at a non-alphabetic boundary so a SUBSTRING of real content
/// can never trigger it — "keine handlung" must not match inside
/// "keine Handlungsmöglichkeit und flieht", which describes what the
/// scene's figure does, not the block's emptiness.
fn contains_marker_word(haystack: &str, marker: &str) -> bool {
    let mut from = 0;
    while let Some(rel) = haystack[from..].find(marker) {
        let end = from + rel + marker.len();
        let boundary = haystack[end..]
            .chars()
            .next()
            .is_none_or(|c| !c.is_alphabetic());
        if boundary {
            return true;
        }
        from = end;
    }
    false
}

/// Deterministic post-extraction guard (issue #668): the hardened prompt
/// (issue #607) bans meta-summaries, but a prompt is an instruction, not a
/// guarantee — the test session's model ignored the ban in 45 of 95 scenes
/// and the garbage flowed through preview → apply → projection → app.
///
/// This is the #607 intent enforced mechanically, independent of model
/// compliance: a summary that describes the block's shape/emptiness instead
/// of scene content is set to `null` before the preview is stored. Returns
/// whether a rewrite happened so the caller can log/count it (prompt/model
/// regression observability).
pub fn sanitize_meta_summary(scene: &mut DraftScene) -> bool {
    match scene.summary.as_deref() {
        Some(summary) if is_meta_summary(summary) => {
            scene.summary = None;
            true
        }
        _ => false,
    }
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

/// The reviewer's acknowledgement of ONE blocking uncertainty (issue #663).
///
/// Request-carried by design: a stored preview is an immutable payload blob
/// (content-addressed handle, no update path), so the resolution lives in the
/// apply request next to the other reviewer decisions (`mappings`,
/// `episode_groups`) instead of mutating the preview. Acknowledge semantics:
/// the reviewer confirms the ambiguous (or absent) value is acceptable and the
/// row applies as extracted — `Uncertainty.suggested_value` is display-only;
/// correcting a *wrong* value happens post-apply via normal scene editing.
/// Identifying pair is `(scene_index, field)` — exactly the fields the
/// extraction prompt reports an uncertainty with.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct UncertaintyAcknowledgement {
    /// The scene the uncertainty is attached to (`Uncertainty.scene_index`).
    pub scene_index: usize,
    /// The field the uncertainty names (`Uncertainty.field`).
    pub field: String,
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
    /// The episode half of a dot-separated `<Episode>.<Scene>` schedule
    /// reference (`"294.10"` → `Some(294)`, plain `"10"` → `None`) — issue
    /// #721. Additive on the wire: previews stored before this field existed
    /// still deserialize.
    #[serde(default)]
    pub episode_number: Option<i32>,
    pub shooting_day_label: Option<String>,
    pub date: Option<NaiveDate>,
    pub location: Option<String>,
    pub order: Option<u32>,
    /// Hybrid quality score of this row's day assignment (issue #722),
    /// aggregated per `DraftShootingDay` group on the script path. `None`
    /// without a decision model / failed pass. Additive on the wire.
    #[serde(default)]
    pub shooting_day_score: Option<f32>,
}

/// The lossless `(episode_number, scene_number)` split of one schedule scene
/// reference (issue #721). Production shooting schedules write scene
/// references as `<Episode>.<Scene>` (`294.01`, `294.10`, `03.05`); the
/// split runs on the DOT as two integer components — never a float coercion,
/// which read `294.10` as decimal `294.1` and silently turned scene 10 into
/// scene 1. A plain number (`"10"`, `"12A"`) carries no episode. An
/// unparseable reference yields `(None, None)` — the row stays unmatched for
/// review, never matched by accident.
#[must_use]
pub fn parse_schedule_scene_ref(raw: &str) -> (Option<i32>, Option<u32>) {
    let raw = raw.trim();
    if raw.is_empty() {
        return (None, None);
    }
    if let Some((episode, scene)) = raw.split_once('.') {
        if !episode.is_empty()
            && !scene.is_empty()
            && episode.bytes().all(|b| b.is_ascii_digit())
            && scene.bytes().all(|b| b.is_ascii_digit())
        {
            return match (episode.parse::<i32>().ok(), scene.parse::<u32>().ok()) {
                (Some(episode), Some(scene)) => (Some(episode), Some(scene)),
                // An overflowing component would half-match a wrong scene —
                // the whole reference degrades to unmatched instead.
                _ => (None, None),
            };
        }
        return (None, None);
    }
    let digits: String = raw.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return (None, None);
    }
    (None, digits.parse().ok())
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
    /// Episode numbers of the applied scenes, keyed by episode id (issue
    /// #721): lets a schedule row carrying `<Episode>.<Scene>` match the
    /// RIGHT episode's scene when a block spans several episodes that each
    /// number their scenes from 1. Prepared at the API boundary (authorized
    /// read) like the scenes themselves — the merge stays a pure join.
    /// Serde default so blobs stored before this field existed still load
    /// (episode context then counts as unavailable, see
    /// [`merge_schedule_to_scenes`]).
    #[serde(default)]
    pub episode_numbers: std::collections::HashMap<EpisodeId, i32>,
}

/// User decision for one draft row. A create decision leaves the aggregate id
/// absent; an update decision carries the existing id and optimistic version.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApplyMapping {
    pub draft_ref: String,
    pub decision: ApplyMappingDecision,
    /// Per-outfit-row decisions of this draft row. Absent ordinals default to
    /// accepted, so a request written before this field existed (or one where
    /// the reviewer touched nothing) still applies everything that was extracted.
    ///
    /// `costume_decisions` is accepted as an alias (OpenSpec change
    /// `ai-import-outfit-and-pieces`): the pre-rename client sends the same
    /// `{ordinal, accepted}` items under the old name, and silently dropping
    /// them would turn a reviewer's rejection into an applied outfit — a
    /// fail-open on the one decision surface that must never be ignored.
    #[serde(default, alias = "costume_decisions")]
    pub outfit_decisions: Vec<OutfitDecision>,
}

/// Reviewer decision for one outfit row of a draft row. An outfit is accepted
/// or rejected *independently of its scene* (spec `ai-import`: the preview
/// exposes each outfit row for its own decision). Rejecting an outfit rejects
/// its pieces with it — they belong to that look.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct OutfitDecision {
    /// Index into the draft row's `outfits` list.
    pub ordinal: usize,
    /// `false` rejects the outfit: no `Piece` and no `Outfit` is created and the
    /// scene row is unaffected.
    pub accepted: bool,
}

impl ApplyMapping {
    /// Whether the reviewer accepted outfit row `ordinal` of this draft row.
    #[must_use]
    pub fn outfit_accepted(&self, ordinal: usize) -> bool {
        self.outfit_decisions
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
/// against the project's existing episodes (409 `episode.number-already-exists`,
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

/// The reviewer's decision for ONE shooting-day group of a preview
/// (issue #706): create the day and schedule the group's rows onto it
/// (`accepted`), or leave every row of the group unscheduled. The day is
/// created episode-scoped on each row's resolved episode; its id is derived
/// deterministically from the group ref, so a re-apply converges.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ShootingDayPlan {
    /// The group ref the preview carries on each row (`day:<n>` /
    /// `day-l:<label>`, [`DraftShootingDay::group_key`]).
    pub day_ref: String,
    pub accepted: bool,
}

/// The shooting-day assignment one planned row carries, resolved by the
/// planner. `Group` is dispatched by the apply worker against the accepted
/// day group's mapping row; `None` covers rows without day metadata, groups
/// the reviewer rejected, and ungroupable labels — those rows apply
/// unscheduled (never invented). `label` is the group's display label
/// ([`DraftShootingDay::display_label`]) — the verbatim first occurrence —
/// carried so the worker never re-derives it from the preview.
// `PartialEq` only: `Group.score` is an `f32` (issue #722).
#[derive(Debug, Clone, PartialEq)]
pub enum PlannedShootingDay {
    None,
    Group {
        day_ref: String,
        label: Option<String>,
        /// The accepted group's hybrid day score (issue #722); threaded into
        /// `ShootingDaySource::AiExtracted.confidence` on apply. `None` stays
        /// honest `None` on the aggregate.
        score: Option<f32>,
    },
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
    /// The extracted role type (issue #677): the classification the extraction
    /// read from the document's cast sections. `MainCast` when the document
    /// does not say otherwise — the grounded default, never an invented guess.
    pub category: CharacterCategory,
}

/// One constituent garment of an [`OutfitApplyPlan`], planned as `CreatePiece`
/// plus optional `SetPieceCategory` / `UpdatePieceNotes`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieceApplyPlan {
    /// Row-flat position across the row's outfit piece lists. With the row's
    /// `draft_ref` this is the idempotency key
    /// `(preview_id, draft_ref, 'piece', ordinal)`: row-flat on purpose, because
    /// two figures may legitimately wear the same garment (`OP-Schuhe`) and a
    /// per-outfit ordinal would collapse them onto one aggregate.
    pub ordinal: usize,
    /// Position inside the owning outfit's `pieces` list (reporting only).
    pub outfit_ordinal: usize,
    /// Garment name, as the model derived it.
    pub name: String,
    /// The category the hint resolved to, when the season has a matching active
    /// category. Resolved at the API edge (CQRS boundary) and carried in here.
    pub category_id: Option<CostumeCategoryId>,
    /// The hint as extracted — kept for reporting and for the "unknown hint"
    /// case, where the piece is created uncategorized instead of failing.
    pub category_hint: Option<String>,
    /// Extracted detail, written as the piece's notes.
    pub notes: Option<String>,
}

/// One outfit of a draft row: its constituent pieces plus the look itself.
///
/// Dispatch order is pieces → outfit → beat: the outfit references the piece
/// ids, so the pieces must exist first, and the beat references the outfit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutfitApplyPlan {
    /// Position inside the row's `outfits` list. With the row's `draft_ref`
    /// this is the idempotency key `(preview_id, draft_ref, 'outfit', ordinal)`
    /// so two outfits of one figure in one scene stay distinct (design D4).
    pub ordinal: usize,
    /// The figure this outfit belongs to, by preview-wide identity.
    pub character_identity: String,
    /// The figure's name as the draft wrote it (reporting only).
    pub character_name: String,
    /// Display name of the look.
    pub name: String,
    /// Notes in the script's own wording.
    pub notes: Option<String>,
    /// Quoted fragment the extraction was based on.
    pub source_quote: String,
    /// The constituent garments, in plan order.
    pub pieces: Vec<PieceApplyPlan>,
}

/// Everything one accepted draft row applies: its scene, the figures it names,
/// and the outfits of those figures.
///
/// Deliberately without `PartialEq`: the wrapped scene commands carry freshly
/// generated aggregate ids, so a structural comparison of two plans could never
/// hold. Tests compare [`Self::characters`] and [`Self::outfits`] and `matches!`
/// on the scene command.
#[derive(Debug, Clone)]
pub struct SceneApplyPlan {
    pub draft_ref: String,
    /// The episode this row applies to, resolved from the request's group
    /// targets (issue #581). Rows without draft episode metadata — and groups
    /// the reviewer mapped to an existing episode — resolve to `Existing`.
    pub episode: PlannedEpisode,
    /// The shooting-day assignment resolved from the request's day decisions
    /// (issue #706). `None` rows apply unscheduled.
    pub shooting_day: PlannedShootingDay,
    /// The row's hybrid scene score (issue #722), threaded into
    /// `SceneSource::AiExtracted.confidence` on a `Create` dispatch.
    pub confidence: Option<f32>,
    pub scene: SceneApplyCommand,
    pub characters: Vec<CharacterApplyPlan>,
    pub outfits: Vec<OutfitApplyPlan>,
}

/// The full apply plan of one reviewed preview.
#[derive(Debug, Clone, Default)]
pub struct ScriptApplyPlan {
    pub scenes: Vec<SceneApplyPlan>,
    /// Outfit rows the plan dropped because no figure of the same row carries
    /// them. Reported, never silent (design D5).
    pub unapplied_outfits: Vec<UnappliedOutfit>,
}

/// Why an outfit row did not become an `Outfit`. Shown to the reviewer as
/// *missing with a reason* instead of as a successful apply.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct UnappliedOutfit {
    pub draft_ref: String,
    pub ordinal: usize,
    pub character_name: String,
    pub name: String,
    pub reason: UnappliedOutfitReason,
    /// Short diagnostic (e.g. the rejection the aggregate returned). The UI
    /// branches on [`Self::reason`], never on this text.
    #[serde(default)]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum UnappliedOutfitReason {
    /// No figure of the same draft row carries this outfit, so it has nothing
    /// to belong to. Creating it would produce an ownerless look.
    CharacterNotPlanned,
    /// `CreateCharacter` was rejected, so the figure the outfit belongs to does
    /// not exist.
    CharacterUnavailable,
    /// One of the outfit's pieces could not be created, so the look cannot be
    /// assembled from what the script described.
    PieceRejected,
    /// The outfit itself was rejected by the aggregate, so the look does not
    /// exist at all.
    CreateRejected,
    /// The outfit exists but its extracted notes could not be written to it.
    NotesRejected,
    /// The outfit exists but its figure could not be assigned to the scene
    /// (archived target season, unresolvable season): it stays uncast.
    BindingRejected,
    /// The outfit exists and belongs to its figure, but `AddOutfitBeat` was
    /// refused by the scene (issue #546 §5.8) — e.g. a concurrent manual edit
    /// removed the figure from the scene between the assign and the beat. The
    /// scene relation is missing while the outfit itself is fine: this must
    /// never look like the plan-time drop ([`Self::CharacterNotPlanned`]),
    /// where the outfit never came into existence at all.
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
    /// The request carried no day decision for a day group the preview
    /// references (issue #706). Same client-bug class as
    /// [`ApplyGateError::MissingEpisodeGroup`]: the reviewer never sees a
    /// default invented behind their back.
    #[error("no shooting day group {0} in the preview")]
    MissingShootingDayGroup(String),
}

pub fn ensure_script_applyable(
    preview: &ScriptContext,
    acknowledged: &[UncertaintyAcknowledgement],
) -> Result<(), ApplyGateError> {
    let blocking = preview
        .uncertainties
        .iter()
        .filter(|uncertainty| uncertainty.kind.blocks_apply())
        // An acknowledged uncertainty is resolved: the reviewer confirmed the
        // ambiguous (or absent) value is acceptable (issue #663).
        .filter(|uncertainty| {
            !acknowledged.iter().any(|ack| {
                ack.scene_index == uncertainty.scene_index && ack.field == uncertainty.field
            })
        })
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

/// Per-identity category signals collected across one preview (issue #695).
struct CategorySignals {
    /// Scene index where the identity first appeared — the `scene_index` the
    /// conflict uncertainty is attached to, so the #663 acknowledgement flow
    /// can match it by `(scene_index, field)`.
    first_scene: usize,
    /// Distinct non-default category slugs in first-seen order. The default
    /// (`main_cast`) is deliberately absent: a non-default classification
    /// already *corrects* the default (see `plan_scene_apply`), so only two
    /// differing non-default signals are a genuine conflict.
    slugs: Vec<&'static str>,
}

/// Surface document-global character-category conflicts as blocking
/// `Uncertainty`s (issue #695).
///
/// The extraction classifies per scene block; a conflict — the same figure
/// named under two cast sections with differing non-default categories — is
/// only visible by comparing rows, and the apply plan's reconciliation rule
/// (first non-default wins) would silently hide it. This pure scan collects
/// the per-identity signals across the **whole** document and emits one
/// `Uncertainty` (kind `field_ambiguity`, field `category`) per conflicting
/// identity, so the reviewer decides before the apply — with the one-tap
/// acknowledgement of issue #663 as the resolution path.
///
/// `suggested_value` mirrors what the apply plan would pick (the first
/// non-default signal); it is display-only, exactly like every other
/// uncertainty's suggestion.
#[must_use]
pub fn category_conflict_uncertainties(preview: &ScriptContext) -> Vec<Uncertainty> {
    // Insertion-ordered per identity: `Vec` for the order, map for the lookup.
    let mut identities: Vec<String> = Vec::new();
    let mut signals: std::collections::HashMap<String, CategorySignals> =
        std::collections::HashMap::new();
    for (scene_index, scene) in preview.scenes.iter().enumerate() {
        for character in &scene.characters {
            let identity = character_identity(&character.name);
            if identity.is_empty() {
                continue;
            }
            let entry = signals.entry(identity.clone()).or_insert_with(|| {
                identities.push(identity.clone());
                CategorySignals {
                    first_scene: scene_index,
                    slugs: Vec::new(),
                }
            });
            if character.category != CharacterCategory::default() {
                let slug = character.category.as_str();
                if !entry.slugs.contains(&slug) {
                    entry.slugs.push(slug);
                }
            }
        }
    }
    identities
        .iter()
        .filter_map(|identity| {
            let signal = signals.get(identity)?;
            let (first, second) = match (signal.slugs.first(), signal.slugs.get(1)) {
                (Some(first), Some(second)) => (*first, *second),
                // Fewer than two non-default signals: no genuine conflict.
                _ => return None,
            };
            Some(Uncertainty {
                scene_index: signal.first_scene,
                field: "category".to_owned(),
                note: format!(
                    "{identity}: conflicting category signals across rows: {first} vs {second}"
                ),
                suggested_value: Some((*first).to_owned()),
                kind: UncertaintyKind::FieldAmbiguity,
            })
        })
        .collect()
}

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

/// The reviewer's request-side plan inputs — bundled so `plan_scene_apply`
/// stays under the `too_many_arguments` lint (an `#[allow]` would violate
/// AGENTS.md §3, cf. `ReservedSceneDraft`).
#[derive(Debug, Clone, Copy, Default)]
pub struct ReviewerDecisions<'a> {
    /// Per-episode-group targets (issue #581).
    pub episode_groups: &'a [EpisodeGroupPlan],
    /// Per-shooting-day-group decisions (issue #706).
    pub shooting_days: &'a [ShootingDayPlan],
    /// Acknowledged blocking uncertainties (issue #663).
    pub acknowledged_uncertainties: &'a [UncertaintyAcknowledgement],
    /// The target season's category vocabulary, resolved at the API edge
    /// (`CostumeCategoryView`), used to turn a piece's `category_hint` into a
    /// category id (CQRS boundary: the write side never reads that projection).
    pub categories: &'a [CategoryVocabularyEntry],
}

/// One entry of the target season's category vocabulary, as the API edge
/// loaded it for the planner. Deliberately a plain `(name, id)` pair: the
/// planner is pure and must not depend on the read-model view type.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct CategoryVocabularyEntry {
    pub name: String,
    pub id: CostumeCategoryId,
}

/// Resolve a piece's extracted `category_hint` against the season vocabulary.
///
/// Matching is case-insensitive and whitespace-trimmed: the model writes
/// `Oberteil`, `oberteil` and ` Oberteil ` for the same category, and the
/// vocabulary is authored by humans. A hint that matches nothing yields `None`
/// — an unknown hint is not an error, the piece is simply created without a
/// category (spec `ai-costume-extraction`).
#[must_use]
fn resolve_category(
    categories: &[CategoryVocabularyEntry],
    hint: Option<&str>,
) -> Option<CostumeCategoryId> {
    let hint = hint?.trim();
    if hint.is_empty() {
        return None;
    }
    categories
        .iter()
        .find(|entry| entry.name.trim().eq_ignore_ascii_case(hint))
        .map(|entry| entry.id)
}

/// Plan the apply of one reviewed script preview.
///
/// A row yields its **scene** command, the **figures** it names and the
/// **outfits** of those figures, in that dispatch order: an outfit belongs to a
/// figure the same row planned (spec `ai-costume-extraction`), so the
/// prerequisite is planned first and the worker never has to look one up. Each
/// outfit carries its own constituent pieces, which the worker creates before
/// the outfit itself.
pub fn plan_scene_apply(
    preview: &ScriptContext,
    mappings: &[ApplyMapping],
    episode_id: EpisodeId,
    project_id: Option<ProjectId>,
    preview_id: AiImportJobId,
    decisions: &ReviewerDecisions<'_>,
) -> Result<ScriptApplyPlan, ApplyGateError> {
    let ReviewerDecisions {
        episode_groups,
        shooting_days,
        acknowledged_uncertainties: acknowledged,
        categories,
    } = *decisions;
    ensure_script_applyable(preview, acknowledged)?;
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
        // A row with day metadata is resolved against the request's day
        // decisions; a group the request forgot is a client bug, not a
        // default (mirrors the episode-group rule above). Everything else —
        // no metadata, ungroupable metadata, and every rejected group —
        // applies unscheduled (issue #706).
        let shooting_day = draft
            .shooting_day
            .as_ref()
            .and_then(DraftShootingDay::group_key)
            .map(|day_ref| {
                let plan = shooting_days
                    .iter()
                    .find(|plan| plan.day_ref == day_ref)
                    .ok_or_else(|| ApplyGateError::MissingShootingDayGroup(day_ref.clone()))?;
                if plan.accepted {
                    Ok(PlannedShootingDay::Group {
                        day_ref,
                        label: draft
                            .shooting_day
                            .as_ref()
                            .and_then(DraftShootingDay::display_label),
                        score: draft.shooting_day.as_ref().and_then(|day| day.score),
                    })
                } else {
                    Ok(PlannedShootingDay::None)
                }
            })
            .transpose()?
            .unwrap_or(PlannedShootingDay::None);
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
                project_id,
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
                project_id,
                version,
            }),
        };

        // A row that names no figure plans none (the "Block 100 / Tag 1" outline
        // case), and a name written twice inside one row is still one figure.
        let mut characters: Vec<CharacterApplyPlan> = Vec::with_capacity(draft.characters.len());
        for (ordinal, character) in draft.characters.iter().enumerate() {
            let name = &character.name;
            let identity = character_identity(name);
            if identity.is_empty() {
                continue;
            }
            // The same figure is often named by several rows. A later
            // non-default classification corrects an earlier grounded
            // default: the cast section is document-global evidence the
            // first row simply lacked (CodeRabbit #692 — first-wins alone
            // would freeze a default the document later refines). Among
            // differing non-default signals the first one wins,
            // deterministic; the reviewer corrects it in the Cast screen
            // (#678).
            if let Some(known) = characters
                .iter_mut()
                .find(|known| known.identity == identity)
            {
                if known.category == CharacterCategory::default()
                    && character.category != CharacterCategory::default()
                {
                    known.category = character.category;
                }
                continue;
            }
            characters.push(CharacterApplyPlan {
                ordinal,
                name: name.clone(),
                identity,
                category: character.category,
            });
        }

        // An outfit belongs to a figure of THIS row. Extraction already rejects
        // an unattributable outfit, so an unmatched name here means a preview
        // that never went through `verify_draft_outfits`: report it instead of
        // creating a look that has nothing to belong to.
        //
        // Pieces are numbered row-flat across every outfit of the row: two
        // figures may legitimately wear the same garment (`OP-Schuhe`), and a
        // per-outfit ordinal would collapse them onto one `piece` mapping row.
        let mut next_piece_ordinal = 0usize;
        let mut outfits: Vec<OutfitApplyPlan> = Vec::with_capacity(draft.outfits.len());
        for (ordinal, outfit) in draft.outfits.iter().enumerate() {
            if !mapping.outfit_accepted(ordinal) {
                continue;
            }
            let identity = character_identity(&outfit.character_name);
            let Some(character) = characters.iter().find(|known| known.identity == identity) else {
                plan.unapplied_outfits.push(UnappliedOutfit {
                    draft_ref: draft_ref.clone(),
                    ordinal,
                    character_name: outfit.character_name.clone(),
                    name: outfit.name.clone(),
                    reason: UnappliedOutfitReason::CharacterNotPlanned,
                    detail: None,
                });
                continue;
            };
            let pieces = outfit
                .pieces
                .iter()
                .filter(|piece| !piece.name.trim().is_empty())
                .map(|piece| {
                    let piece_ordinal = next_piece_ordinal;
                    next_piece_ordinal += 1;
                    PieceApplyPlan {
                        ordinal: piece_ordinal,
                        outfit_ordinal: ordinal,
                        name: piece.name.trim().to_owned(),
                        category_id: resolve_category(categories, piece.category_hint.as_deref()),
                        category_hint: piece.category_hint.clone(),
                        notes: piece
                            .description
                            .as_deref()
                            .map(str::trim)
                            .filter(|text| !text.is_empty())
                            .map(str::to_owned),
                    }
                })
                .collect();
            outfits.push(OutfitApplyPlan {
                ordinal,
                character_identity: character.identity.clone(),
                character_name: character.name.clone(),
                name: outfit.name.trim().to_owned(),
                notes: outfit
                    .notes
                    .as_deref()
                    .map(str::trim)
                    .filter(|text| !text.is_empty())
                    .map(str::to_owned),
                source_quote: outfit.source_quote.clone(),
                pieces,
            });
        }

        plan.scenes.push(SceneApplyPlan {
            draft_ref,
            episode,
            shooting_day,
            // Issue #722: the row's hybrid scene score becomes the applied
            // scene's `SceneSource::AiExtracted.confidence` — `None` stays
            // honest `None` (no decision model / failed scoring pass).
            confidence: draft.scene_score,
            scene,
            characters,
            outfits,
        });
    }
    // Issue #677 (CodeRabbit #692): the same figure is often named by several
    // rows, and the cast section is document-global evidence. Reconcile the
    // per-row classifications preview-wide by identity: a later non-default
    // signal corrects an earlier grounded default; among differing
    // non-default signals the first one wins — deterministic, and the
    // reviewer corrects it in the Cast screen (#678). The dispatch reads the
    // plan, so the reconciled category is what every row's figure gets.
    let mut resolved_categories: std::collections::HashMap<String, CharacterCategory> =
        std::collections::HashMap::new();
    for scene in &plan.scenes {
        for character in &scene.characters {
            let entry = resolved_categories
                .entry(character.identity.clone())
                .or_insert(character.category);
            if *entry == CharacterCategory::default()
                && character.category != CharacterCategory::default()
            {
                *entry = character.category;
            }
        }
    }
    for scene in &mut plan.scenes {
        for character in &mut scene.characters {
            if let Some(category) = resolved_categories.get(&character.identity) {
                character.category = *category;
            }
        }
    }

    Ok(plan)
}

/// One outfit beat slot of a figure's lane: the outfit in plan order plus
/// its PER-FIGURE position, which is what the `scene_outfit_beat` mapping
/// rows are addressed by (issue #546 §5.8).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutfitBeatSlot<'a> {
    /// Position of this outfit among the figure's beats of the row,
    /// 0..n-1 in plan order — deliberately NOT the row-flat `ordinal`, which
    /// two figures would collide on.
    pub per_figure_order: usize,
    pub outfit: &'a OutfitApplyPlan,
}

/// One figure's lane of the scene-apply chain: the figure itself plus its
/// outfit beats, filtered from the row's flat outfit list (issue #546
/// §5.8). Pure re-grouping — no extraction behaviour, no LLM call.
#[derive(Debug, Clone)]
pub struct SceneBeatLane<'a> {
    pub character: &'a CharacterApplyPlan,
    /// The figure's outfits of this row, plan order kept, numbered per
    /// figure 0..n-1. An outfit whose identity matches no figure of the row
    /// never appears in any lane — [`ScriptApplyPlan::unapplied_outfits`]
    /// already reported it at plan time.
    pub beats: Vec<OutfitBeatSlot<'a>>,
}

/// Re-group a draft row's flat outfit list into per-figure beat lanes.
///
/// The extraction produces `outfits` flat across all figures with the
/// ordinal as a PER-SCENE position, while `AddOutfitBeat` orders per figure
/// (aggregate-computed `max + 1`) and the beat mapping rows need a
/// collision-free per-figure address. This function is the single place
/// that defines the mapping between the two: filter the row's outfits by
/// the lane figure's identity, keep the plan order, number 0..n-1 per
/// figure.
pub fn scene_beat_lanes(row: &SceneApplyPlan) -> Vec<SceneBeatLane<'_>> {
    row.characters
        .iter()
        .map(|character| {
            let mut per_figure_order = 0usize;
            let beats = row
                .outfits
                .iter()
                .filter(|outfit| outfit.character_identity == character.identity)
                .map(|outfit| {
                    let slot = OutfitBeatSlot {
                        per_figure_order,
                        outfit,
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
    // The shooting day in effect at the current line: the last day marker
    // seen so far (issue #706). Day columns repeat across a day's pages,
    // which is harmless — same group. The FIRST occurrence's label wins, so
    // a repeated `Tag 1` never rewrites the reviewer-facing label.
    let mut current_day: Option<DraftShootingDay> = None;
    // Episode titles from the title page (`(294) "Freundschaft"`): the `Ep.:`
    // page-header markers carry a bare number, but the reviewer expects the
    // episode HEADING to flow into the created episode. Collected in a FIRST
    // pass over the whole document — the title page can sit AFTER the first
    // `Ep.:` marker (the page header on page 1 precedes the title block), so
    // an inline single-pass scan would miss it.
    let mut episode_titles: std::collections::HashMap<i32, String> =
        std::collections::HashMap::new();
    for line in document.lines() {
        if let Some((number, title)) = title_page_entry(line.trim()) {
            episode_titles.entry(number).or_insert(title);
        }
    }
    for line in document.lines() {
        let trimmed = line.trim();
        if let Some(episode) = episode_marker(trimmed) {
            let mut episode = episode;
            if episode.title.is_none() {
                episode.title = episode.number.and_then(|n| episode_titles.get(&n)).cloned();
            }
            current_episode = Some(episode);
        }
        if let Some(day) = day_marker(trimmed)
            && (is_scene_heading(trimmed) || is_standalone_day_marker(trimmed, &day))
        {
            // Day markers live in scene-index columns (heading lines) and in
            // page headers (a line that IS the marker). A non-heading line
            // only updates `current_day` when the whole whitespace-
            // normalized line matches the marker's label — short dialogue
            // like "Tag 3 war schlimm." must not re-group every following
            // scene (CodeRabbit review, issue #706). First occurrence's
            // label wins: a repeated `Tag 1` (page headers) never rewrites
            // the reviewer-facing label.
            if current_day.as_ref().and_then(DraftShootingDay::group_key) != day.group_key() {
                current_day = Some(day);
            }
        }
        if is_scene_heading(trimmed) {
            let scene_number = leading_scene_number(&normalize_for_heading_detection(trimmed));
            chunks.push(SceneChunk {
                index: chunks.len(),
                heading: trimmed.to_owned(),
                scene_number,
                episode: current_episode.clone(),
                shooting_day: current_day.clone(),
                mood: parse_mood_from_heading(trimmed),
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
    merge_duplicate_scene_numbers(chunks)
}

/// Merge chunks that carry the SAME document scene number (SCRIPT REPORT
/// format, found via the 294.pdf user import): these documents open with a
/// scene INDEX (every scene listed as `1    A/T - ORT` + `Tag 1`) BEFORE the
/// scene bodies, so the deterministic splitter creates one stub per index
/// entry PLUS one real chunk per body heading — the preview doubled every
/// scene. With the number now parsed from both occurrences (`pdftotext
/// -layout` keeps the number column on the heading line), a repeated number
/// is the same scene: merge into the FIRST occurrence (index order = number
/// order). Scenes without a document number (headings like `INT. ROOM - DAY`)
/// are never merged.
///
/// The merge key is **(document scene label, episode group key)**:
///
/// - The LABEL is the full leading scene identity — digits plus any
///   alphanumeric suffix up to the first whitespace (`12`, `12A`). Scripts
///   commonly use letter suffixes for inserted scenes; `12 I/T - KÜCHE` and
///   `12A I/T - FLUR` are DISTINCT scenes even though both carry the numeric
///   part 12 (CodeRabbit review: before this, the suffix chunk was folded
///   into the plain-number chunk and lost its preview row). Unnumbered
///   chunks (headings like `INT. ROOM - DAY`) are never merged.
/// - The EPISODE part is [`DraftEpisode::group_key`] — two episodes can both
///   contain a scene `1`, and merging across episodes would fold two
///   distinct scenes into one (CodeRabbit review: the second scene would
///   lose its model request and preview row). The group key also keeps
///   title-only markers (`Ep (Der Unfall)`) distinct from each other AND
///   from episode-less chunks, matching the doc contract.
///
/// When merging, the LONGER occurrence's body wins, but lines that appear
/// ONLY in the shorter one are preserved (the index entry may carry
/// metadata — e.g. its `Tag 3` day column — that the body occurrence lacks;
/// the model reads the merged text and would otherwise never see it).
fn merge_duplicate_scene_numbers(chunks: Vec<SceneChunk>) -> Vec<SceneChunk> {
    let mut merged: Vec<SceneChunk> = Vec::with_capacity(chunks.len());
    // Key → index into `merged` (CodeRabbit review: the chunk-count limit is
    // checked only AFTER this merge, and the extractor accepts up to 20 MiB
    // of text — a crafted document with many distinct numbered headings must
    // not make this pre-validation pass quadratic).
    let mut indices: std::collections::HashMap<(Option<String>, Option<String>), usize> =
        std::collections::HashMap::new();
    for chunk in chunks {
        // Full document label ("12", "12A"): a suffix is a distinct scene.
        // `scene_number` (the numeric part) stays the display/backfill field.
        let label = leading_scene_label(&chunk.heading);
        let key = (
            label,
            chunk.episode.as_ref().and_then(DraftEpisode::group_key),
        );
        let existing = match &key {
            // Overflowing digit runs never parsed as a scene number and never
            // merged — keep that contract (`scene_number` is the parse gate).
            (Some(_), _) if chunk.scene_number.is_some() => {
                indices.get(&key).copied().map(|i| &mut merged[i])
            }
            _ => None,
        };
        match existing {
            Some(existing) => {
                let (longer, shorter) = if chunk.text.len() >= existing.text.len() {
                    (chunk.text.clone(), existing.text.clone())
                } else {
                    (existing.text.clone(), chunk.text.clone())
                };
                let longer_lines: std::collections::HashSet<&str> = longer.lines().collect();
                let mut union: Vec<&str> = longer.lines().collect();
                for line in shorter.lines() {
                    if !longer_lines.contains(&line) {
                        union.push(line);
                    }
                }
                existing.text = union.join("\n");
                if existing.episode.is_none() {
                    existing.episode = chunk.episode;
                }
                if existing.shooting_day.is_none() {
                    existing.shooting_day = chunk.shooting_day;
                }
            }
            None => {
                // Only labeled chunks are indexed — unnumbered chunks never
                // merge, so they need no lookup entry.
                if key.0.is_some() {
                    indices.insert(key, merged.len());
                }
                merged.push(chunk);
            }
        }
    }
    for (index, chunk) in merged.iter_mut().enumerate() {
        chunk.index = index;
    }
    merged
}

/// A title-page episode entry: `(` + 1-4 digits + `)` + a quoted title —
/// the ARD/telenovela title-page convention (`(294) "Freundschaft"`, also
/// German low-9 quotes). The 1-4 digit cap mirrors [`episode_marker`]'s
/// number bound; the quote pair is required so a prose parenthesis ("(vgl.
/// 294)") never becomes an episode title.
fn title_page_entry(line: &str) -> Option<(i32, String)> {
    let open = line.find('(')?;
    let after_open = &line[open + 1..];
    let digits: String = after_open
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    if digits.is_empty() || digits.len() > 4 {
        return None;
    }
    let rest = &after_open[digits.len()..];
    let rest = rest.strip_prefix(")")?;
    let rest = rest.trim_start();
    for (open_q, close_q) in [
        ('"', '"'),
        ('\u{201E}', '\u{201C}'), // „ … “
        ('\u{201C}', '\u{201D}'), // “ … ”
        ('\'', '\''),
    ] {
        if let Some(title) = rest
            .strip_prefix(open_q)
            .and_then(|t| t.find(close_q).map(|end| (t, end)))
        {
            let (title, end) = title;
            let title = title[..end].trim();
            if !title.is_empty() {
                return Some((digits.parse().ok()?, title.to_owned()));
            }
        }
    }
    None
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

/// Strip a leading scene label from a heading line — the digits/`.`/`-`/
/// space run the old detector consumed, PLUS an optional SHORT alphanumeric
/// suffix glued to the digits (`12A`, `12b`). Scripts use letter suffixes
/// for inserted scenes; without suffix handling `12A I/T - FLUR` was never
/// detected as a heading at all and its body glued onto scene `12`'s chunk
/// (CodeRabbit review). The suffix run is capped at 2 characters and must
/// be followed by a separator, so a prose first word ("3 Akte später …")
/// is never consumed and the line stays a non-heading.
fn strip_leading_scene_label(s: &str) -> &str {
    let after_suffix = scene_label_end(s).unwrap_or(0);
    let bytes = s.as_bytes();
    // The remaining mixed digit/`.`/`-`/space run (the old detector's
    // `trim_start_matches`, e.g. `1. INT.` or `12 - I/T`).
    let mut k = after_suffix;
    while k < bytes.len()
        && (bytes[k].is_ascii_digit() || bytes[k] == b'.' || bytes[k] == b'-' || bytes[k] == b' ')
    {
        k += 1;
    }
    &s[k..]
}

/// End byte of the leading scene label — the SINGLE source of truth for the
/// label boundary, shared by [`strip_leading_scene_label`] (heading
/// detection) and [`leading_scene_label`] (the merge key) so the two can
/// never disagree on where the number ends and the heading token begins
/// (CodeRabbit review).
///
/// The label is the leading digit run plus an OPTIONAL glued suffix of at
/// most 2 ASCII alphanumerics (`12A`, `12b`). The suffix counts only when a
/// separator follows — ` `/`.`/`-` or end of line. `/` is deliberately NOT
/// a suffix separator: the German short-form heading glues its interior /
/// exterior token to the number (`12I/T - KÜCHE`), and accepting `/` would
/// read the `I` as a scene suffix and mangle the line into "/T - KÜCHE",
/// which no longer matches the German heading rule (a regression against
/// the digits-only detector). A prose first word ("3 Akte später …") is
/// never consumed — without a separator after the ≤2-char run the suffix
/// is rejected and the label ends at the digits.
/// `None` when the line has no leading digit.
fn scene_label_end(s: &str) -> Option<usize> {
    let bytes = s.as_bytes();
    let digits_end = bytes.iter().take_while(|b| b.is_ascii_digit()).count();
    if digits_end == 0 {
        return None;
    }
    let suffix_end = digits_end
        + bytes[digits_end..]
            .iter()
            .take(2)
            .take_while(|b| b.is_ascii_alphanumeric())
            .count();
    let separated = suffix_end == bytes.len() || matches!(bytes[suffix_end], b' ' | b'.' | b'-');
    Some(if suffix_end > digits_end && separated {
        suffix_end
    } else {
        digits_end
    })
}

fn is_scene_heading(line: &str) -> bool {
    // Word→PDF export artifacts are normalized INSIDE the detector so every
    // caller (chunk splitting and direct tests alike) gets the robust
    // behavior; the stored heading stays verbatim (see `extract_scenes`).
    let trimmed = strip_leading_scene_label(&normalize_for_heading_detection(line)).to_owned();
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

/// One time-of-day token of a scene heading, in canonical set-shorthand form
/// (issue #721): the `T`/`N`/`D`/`M`/`AB` half of `I/T`, `A/N`, …. Matched
/// case-insensitively over German and English spellings; the comparison runs
/// on the Unicode lowercase of the token so `DÄMMERUNG` (its Ä survives the
/// ASCII-only uppercase of heading detection) still normalizes.
fn time_shorthand(token: &str) -> Option<&'static str> {
    match token.to_lowercase().as_str() {
        "t" | "tag" | "day" => Some("T"),
        "n" | "nacht" | "night" => Some("N"),
        "d" | "d\u{e4}mmerung" | "dusk" | "dawn" => Some("D"),
        "m" | "morgen" | "morning" => Some("M"),
        "ab" | "abend" | "evening" => Some("AB"),
        _ => None,
    }
}

/// The canonical set-shorthand mood (`I/T`, `A/N`, `I/D`, `I/M`, `I/AB`, the
/// `A/*` counterparts, combined `I/A/T`) carried by a scene heading (issue
/// #721). Screenplay headings already state interior/exterior and
/// time-of-day — German short form (`12 I/T - WERKSTATT`), German long form
/// (`INNEN WOHNUNG - NACHT`), English (`INT. KITCHEN - DAY`,
/// `EXT. STREET - NIGHT`, combined `INT/EXT. WORKSHOP - DAY`) — and the old
/// chunker discarded them, leaving `mood` null on nearly every imported
/// scene. Deterministic: the heading is server-truth, no LLM involved, and a
/// heading whose tokens do not normalize into the canonical set (no time
/// token, an unknown abbreviation) yields `None` — the model's grounded
/// `mood` then stands, an invented one is never papered over.
#[must_use]
pub fn parse_mood_from_heading(line: &str) -> Option<String> {
    let normalized_line = normalize_for_heading_detection(line);
    let stripped = strip_leading_scene_label(&normalized_line);
    let normalized = stripped.to_ascii_uppercase();

    // Long forms: an explicit interior/exterior prefix, the time-of-day
    // somewhere in the remainder (usually the last `-` segment).
    let (location, remainder): (&'static str, &str) = if let Some(rest) = normalized
        .strip_prefix("INT/EXT.")
        .or_else(|| normalized.strip_prefix("INT./EXT."))
        .or_else(|| normalized.strip_prefix("I/E."))
    {
        ("I/A", rest)
    } else if let Some(rest) = normalized.strip_prefix("INT.") {
        ("I", rest)
    } else if let Some(rest) = normalized.strip_prefix("EXT.") {
        ("A", rest)
    } else if let Some(rest) = normalized
        .strip_prefix("INNENAUFNAHME")
        .or_else(|| normalized.strip_prefix("INNEN."))
    {
        ("I", rest)
    } else if let Some(rest) = normalized
        .strip_prefix("AUSSENAUFNAHME")
        .or_else(|| normalized.strip_prefix("AUSSEN."))
    {
        ("A", rest)
    } else if let Some(rest) = normalized.strip_prefix("INNEN ") {
        ("I", rest)
    } else if let Some(rest) = normalized.strip_prefix("AUSSEN ") {
        ("A", rest)
    } else {
        // German short form `I/T` / `A/N`: the time token follows the `/`
        // directly (same grammar as [`is_german_scene_heading`] — 1–2
        // alphabetic characters, then a separator or end of line).
        let mut chars = normalized.chars();
        match (chars.next(), chars.next()) {
            (Some('I') | Some('A'), Some('/')) => {}
            _ => return None,
        }
        let location = if normalized.starts_with('I') {
            "I"
        } else {
            "A"
        };
        let mut token = String::new();
        for c in chars {
            if c.is_ascii_alphabetic() {
                token.push(c);
                if token.len() > 2 {
                    return None;
                }
            } else {
                break;
            }
        }
        let time = time_shorthand(&token)?;
        return Some(format!("{location}/{time}"));
    };

    // Long form: the LAST whitespace-separated word that normalizes into a
    // canonical time token wins ("INNEN WOHNUNG - NACHT" → N,
    // "EXT. STREET - NIGHT (FLASHBACK)" → N; a word that merely CONTAINS a
    // token — "ABENDBLATT" — never matches, whole tokens only).
    //
    // Shooting-day markers are NOT time of day: a heading column like
    // "INT. KITCHEN - TAG 1" (script-report day column, issue #706's
    // territory) carries the day NUMBER after the word — exactly "TAG"/"DAY"
    // followed by a digit is disqualified, every other recognized token
    // keeps its normal handling (CodeRabbit review, PR #725).
    let words: Vec<&str> = remainder.split_whitespace().collect();
    let mut time: Option<&'static str> = None;
    for (index, word) in words.iter().enumerate() {
        let token = word.trim_matches(['.', ',', ':']);
        let Some(shorthand) = time_shorthand(token) else {
            continue;
        };
        if matches!(token.to_lowercase().as_str(), "tag" | "day")
            && words
                .get(index + 1)
                .is_some_and(|next| next.starts_with(|c: char| c.is_ascii_digit()))
        {
            continue;
        }
        time = Some(shorthand);
    }
    let time = time?;
    Some(format!("{location}/{time}"))
}

/// The full leading scene label of a heading: the leading digits PLUS any
/// glued alphanumeric suffix accepted by [`scene_label_end`] — `12`, `12A`,
/// `12b`. A letter suffix marks an inserted scene, a scene of its own: the
/// merge key must not fold `12A` into `12` (CodeRabbit review). Detection
/// runs on the normalized copy (invisible Word→PDF look-alikes folded to
/// ASCII) and shares the exact boundary rule with the heading detector, so
/// the merge key can never disagree with chunk splitting. Returns `None`
/// for headings without a leading digit.
fn leading_scene_label(line: &str) -> Option<String> {
    let normalized = normalize_for_heading_detection(line);
    scene_label_end(&normalized).map(|end| normalized[..end].to_owned())
}

/// Join schedule rows with applied scenes by scene number. Both inputs are
/// copied into deterministic order; no fuzzy matching or LLM call is involved.
///
/// Episode-aware when context is available (issue #721): a row carrying an
/// `episode_number` matches `(episode_number, scene_number)` against the
/// `episode_numbers` map, so Scene 10 of Episode 295 never steals the row of
/// Scene 10 in Episode 294 — and a row whose pair matches NO scene stays
/// unmatched rather than falling back across the episode boundary.
/// Scene-number-only matching applies exactly when episode context is
/// unavailable: the row carries no episode, or the map is empty/absent.
pub fn merge_schedule_to_scenes(
    schedule: &ShootingSchedule,
    scenes: &[SceneView],
    episode_numbers: &std::collections::HashMap<EpisodeId, i32>,
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
    // Scenes with a KNOWN episode number group additionally by the episode:
    // scenes whose episode is absent from the map are invisible to
    // episode-bearing rows (a pair match against an unknown episode would be
    // a guess, not a join).
    let mut pair_to_indices: std::collections::HashMap<(i32, u32), Vec<usize>> =
        std::collections::HashMap::new();
    for (index, scene) in ordered_scenes.iter().enumerate() {
        number_to_indices
            .entry(scene.scene_number)
            .or_default()
            .push(index);
        if let (Some(&episode), Some(number)) =
            (episode_numbers.get(&scene.episode_id), scene.scene_number)
        {
            pair_to_indices
                .entry((episode, number))
                .or_default()
                .push(index);
        }
    }
    let mut next_for_group: std::collections::HashMap<(Option<i32>, Option<u32>), usize> =
        std::collections::HashMap::new();

    let mut matched: Vec<Vec<ShootingScheduleRow>> = vec![Vec::new(); ordered_scenes.len()];
    let mut unmatched_schedule_rows = Vec::new();
    for row in rows {
        let group = match row.episode_number {
            Some(episode) if !episode_numbers.is_empty() => row
                .scene_number
                .and_then(|number| pair_to_indices.get(&(episode, number)))
                .filter(|indices| !indices.is_empty()),
            _ => row
                .scene_number
                .and_then(|number| number_to_indices.get(&Some(number)))
                .filter(|indices| !indices.is_empty()),
        };
        if let Some(indices) = group {
            let cursor = next_for_group
                .entry((row.episode_number, row.scene_number))
                .or_insert(0);
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
    Ok(merge_schedule_to_scenes(
        &input.schedule,
        &input.scenes,
        &input.episode_numbers,
    ))
}

#[cfg(test)]
#[path = "preview_tests.rs"]
mod preview_tests;
