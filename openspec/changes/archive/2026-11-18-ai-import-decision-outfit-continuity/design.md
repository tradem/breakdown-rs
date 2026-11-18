<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — AI Import Pass 2: Decision-Model Outfit Continuity & Gap Analysis

## Decisions

### D1 — Plausible-Action Eligibility Gate
Outline stubs, empty scene headers, or meta-summaries (`"Keine Handlung im Block"`)
must never trigger outfit inference or false conflict uncertainties.
A `(scene_index, character_identity)` gap enters Pass 2 if and only if:
1. `character_identity` is in `scene.characters`,
2. no `DraftOutfit` in `scene.outfits` matches `character_identity`, and
3. `scene.summary` is `Some(s)` with `!s.trim().is_empty()` and
   `!is_meta_summary(&s)`.

### D2 — Decision Model Evaluation (Option A vs. Option B vs. Option C)
For each eligible `(scene_index, character_identity)` gap, the worker builds a
compact, deterministic continuity state containing:
- **Current scene:** `scene_number`, `location`, `mood`, `script_day` /
  `shooting_day`, `summary`, and the character's action lines in the chunk.
- **Prior appearance(s) of the same character:** most recent scene with an
  outfit (`scene_number`, `location`, `mood`, `script_day`, `outfit.name`,
  `outfit.pieces`).

The Decision Model (`DecisionClient`, issue `#722`) evaluates a calibrated
categorical question (`DecisionQuestion::Choice`):
- **`continue_previous` (Option A):** The character continues wearing the prior
  scene's outfit (only valid when a prior outfit exists in the script).
- **`infer_new_outfit` (Option B):** The scene's location/action implies a new
  outfit that can be derived from the scene context (e.g. entering an operating
  room `"OP"`, intensive care `"ITS"`, changing day/time/setting).
- **`report_conflict_or_gap` (Option C):** Neither continuation nor new
  inference is sufficiently certain, or both compete (e.g. a day change at the
  same workplace).

### D3 — Referencing Shared `OutfitId` on Option A (`ContinuedFromScene`)
When Option A wins:
- The `DraftOutfit` in scene `S` carries
  `DraftOutfitOrigin::ContinuedFromScene { source_draft_ref, source_scene_number, confidence }`.
- During `plan_scene_apply`, no second `OutfitAggregate` or duplicate `Piece`s
  are created. Instead, the apply worker resolves the `OutfitId` created for
  `(source_draft_ref, character_identity)` from `ai_import.apply_mapping` and
  dispatches `AddOutfitBeat` on scene `S` referencing that **exact same
  `OutfitId`**.

### D4 — Option C Uncertainties: Choices Only When Script-Derivable
Per Product Owner requirement, the preview UI must never present invented
multiple-choice options when the script offers no basis for them:
- **Case C1 — Competing script-derivable candidates exist** (e.g. Candidate 1:
  continuation of prior outfit `"Zivil-Look"` from Scene 4; Candidate 2:
  context-derived `"OP-Kleidung"` from Scene 5's `"I/T - OP-SAAL"` location):
  The `Uncertainty` carries those concrete `candidates: Vec<DraftOutfitCandidate>`
  so the reviewer can pick one (or choose "leave empty") in the preview.
- **Case C2 — No candidate is derivable from the script** (e.g. the character's
  very first appearance occurs in a generic corridor with zero wardrobe clues):
  `candidates` is empty (`[]`). The reviewer sees a simple gap notification
  that can be acknowledged with one tap (`#663`), leaving the scene without an
  outfit until wardrobe planning assigns one manually.

### D5 — `DraftOutfitOrigin` stays additive instead of carrying the quote

`proposal.md` asked for `ExplicitQuote { source_quote: String }`. Implementing
it literally would have broken two invariants of this module:

1. **Duplication.** `DraftOutfit.source_quote` already carries the verbatim
   fragment `verify_draft_outfits` grounds against. A second copy inside the
   origin could drift from it.
2. **Wire compatibility.** A preview is an immutable JSON blob that a later
   binary serves. Stored rows carry `"origin": "explicit_quote"`; serde cannot
   decode a unit string into a struct variant, so every previously stored
   preview would fail to load.

Decision: the enum stays **fieldless** — `explicit_quote`, `derived`,
`continued_from_scene`, `inferred_from_context` — and the Pass-2 payload moves to
a separate optional `DraftOutfit.provenance` object. The origin classifies
*where* a look came from; `source_quote` carries *what* it was read out of;
`provenance` carries the source row and the confidence. A preview stored before
the change still loads and keeps reading as `explicit_quote` with no provenance.

A first implementation carried the payload as enum arm data. CodeRabbit's review
caught the consequence: `utoipa` lowers the two unit variants to two single-value
`type: string` alternatives, the `dart-dio` generator collapses both to
`FullType(String)`, and `built_value`'s `OneOf` then throws
`Unsupported operation: more than one match found: (String, String)` on every
`"explicit_quote"` — i.e. the generated client could not decode the *common*
Pass-1 case at all (verified with a probe test before changing the contract).
Keeping the origin a plain string is therefore not a style choice but a
client-compatibility requirement.

### D6 — Option B derives a label, never garments

A Decision Model emits a probability distribution, not text, and a wardrobe gap
by definition has no script sentence naming a garment. Option B therefore
attaches a look whose name is the scene's own location
(`Kontext-Look (<LOCATION>)`) and whose piece list is **empty**, plus a
non-blocking uncertainty stating that the look was inferred. Inventing pieces
would be exactly the fabrication the Pass-1 grounding check exists to prevent,
and a wrong garment silently enters the fundus while a missing one is a visible
gap the wardrobe department fills in one edit.

The pass also never lets its own output become evidence: all decisions are
evaluated against the preview as it was when the pass started, so a continuation
can never chain out of a look this same run just invented.

### D7 — Reviewer selection rides a request field, not the immutable preview

A gap has no outfit row at all, so "the reviewer picked candidate B" cannot be an
`outfit_decision` (there is no ordinal to address). It travels as
`continuity_selections` on the apply request next to `mappings`,
`episode_groups`, `shooting_days` and `uncertainty_acknowledgements`, and the
planner validates every entry against the preview's own candidate derivation.
An entry the preview does not offer is refused with its own registered problem
code (`409 ai-import.apply-unknown-continuity-candidate`) rather than dropped,
because silently ignoring a selection would apply the exact opposite of what the
reviewer decided.

### D8 — Beat addresses are preview-derived and kind-separated

A beat's `projection_ai_import_mapping` address is
`(preview_id, draft_ref, aggregate_kind, ordinal)`. The ordinal must survive
review-decision changes, because a mapping row is the **durable record** of a
dispatched command: a shifted address silently resolves to another row's
confirmed row, and `apply_outfit_beat` then answers `Settled` — the scene never
gets its beat and nothing reports a failure.

Two consequences, both implemented as planner output rather than worker
bookkeeping:

1. An extracted outfit's ordinal is the figure's position across the **whole
   preview**, computed from the immutable draft rows: every earlier outfit of
   that figure counts, whatever its review decision or attribution.
2. A row synthesised from a reviewer's continuity selection has no preview index
   (the selection is request-carried), so it gets its **own mapping kinds**
   (`outfit_continuity`, `scene_outfit_beat_continuity`) and is addressed by the
   row's `draft_ref` plus the figure's position in the draft's own character
   list. Selection ranks were rejected: adding a selection for another gap scene
   would renumber its siblings.

### D9 — Continuity selection validation is indexed, not scanned

A request may legitimately select **every** gap, so `validate_continuity_selections`
builds one map over the gaps, sweeps the preview once in scene order to resolve
each figure's most recent earlier dressed row, and detects duplicates with a set.
Per-selection scans over the preview (the first implementation) were quadratic in
the preview's row count for a valid maximum-size request. The selection-count
guard lives inside the same pass, so the handler never re-derives the gap list.
