<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Pass 2 runs after every chunk merged and never fails the job
After Pass 1 (chunk extraction) has finished and every chunk's rows are merged
into one `ScriptContext`, the script import worker SHALL run a second,
cross-scene pass over the merged preview before the preview is stored. The pass
SHALL run only when a Decision Model is configured for the job, SHALL issue at
most ONE decision request per eligible gap, and SHALL be best-effort: a failed
request SHALL be logged and end the pass without discarding the extracted
preview, without failing the job, and without adding fabricated rows. The pass
SHALL stop early when the job's claim was lost, so it never spends on a job
another worker now owns.

#### Scenario: No decision model configured
- **WHEN** the job carries no Decision Model configuration
- **THEN** Pass 2 SHALL NOT run
- **AND** the stored preview SHALL be byte-identical to a Pass-1-only preview apart from the fields Pass 1 itself fills

#### Scenario: The decision endpoint fails mid-pass
- **WHEN** the decision request for one gap fails permanently
- **THEN** the worker SHALL log a warning and end Pass 2
- **AND** the preview SHALL still be stored and the job SHALL still succeed
- **AND** no gap SHALL receive an outfit or an uncertainty from the failed evaluation

#### Scenario: The claim is lost during Pass 2
- **WHEN** the lease heartbeat reports the job was reclaimed while Pass 2 runs
- **THEN** the pass SHALL stop before its next decision request
- **AND** the worker SHALL abort the job as it does for a lost claim during extraction

### Requirement: Only plausible wardrobe gaps enter Pass 2
A `(scene, character)` pair SHALL be eligible for Pass 2 if and only if (a) the
character is named by that scene, (b) the scene carries no `DraftOutfit` for
that character's normalised identity, and (c) the scene has plausible action —
its `summary` is present, non-blank and is not a meta-summary per
`is_meta_summary`. Outline stubs, empty scene headers and meta-descriptions
SHALL never trigger inference; a scene without plausible action SHALL NOT be
reported as a wardrobe gap.

#### Scenario: Outline stub with no action
- **WHEN** a scene's summary is absent or is a meta-description such as "Keine Handlung im Block"
- **THEN** its characters SHALL NOT enter Pass 2
- **AND** the preview SHALL carry no continuity uncertainty for that scene

#### Scenario: Character already dressed by Pass 1
- **WHEN** a scene names a figure that Pass 1 already gave an outfit, in any case or spacing
- **THEN** that pair SHALL NOT enter Pass 2
- **AND** the explicit outfit SHALL be left untouched

#### Scenario: Figure named in a scene with action but no outfit
- **WHEN** a scene has a non-blank, non-meta summary and names a figure with no extracted outfit
- **THEN** exactly one gap SHALL be produced for that pair

### Requirement: Continuity is one calibrated choice question per gap
For each eligible gap the worker SHALL build a deterministic state payload
containing the current scene (number, location, mood, shooting/script day,
summary) and the character's most recent prior appearance carrying an outfit
(scene number, location, mood, day, outfit name, its pieces) and SHALL evaluate
exactly one `DecisionQuestion::Choice` with the options
`continue_previous`, `infer_new_outfit` and `report_conflict_or_gap`. The
winning option SHALL be the highest-probability option of the answer, and the
winning probability SHALL be recorded on the produced row. `continue_previous`
SHALL be treated as unavailable when the character has no prior outfit in the
preview, and an answer naming an unavailable option SHALL fall back to the next
highest available option.

#### Scenario: Model answers continuation
- **WHEN** the choice answer gives `continue_previous` the highest probability and the figure wore an outfit in an earlier scene
- **THEN** the gap SHALL resolve to Option A
- **AND** the produced outfit SHALL carry the winning probability as its confidence

#### Scenario: Continuation without a prior outfit
- **WHEN** the choice answer names `continue_previous` for a figure's first appearance
- **THEN** Option A SHALL be treated as unavailable
- **AND** the gap SHALL resolve to the next highest available option instead

### Requirement: A continuation carries the source outfit's provenance
A gap resolved to Option A SHALL attach a `DraftOutfit` to the scene whose
origin is `continued_from_scene`, with a `provenance` object carrying the source
draft row reference, the source scene number when the source row has one, and
the confidence. The continue-to outfit SHALL carry the source outfit's name,
SHALL carry no pieces of its own, and SHALL NOT carry an invented source quote.
Exactly one outfit SHALL be attached per resolved gap. The origin SHALL remain a
plain wire string with the source in the provenance, so no client has to decode a
union of alternatives.

#### Scenario: Continuation produced
- **WHEN** the gap of scene 5 resolves to Option A and the figure's prior outfit sits in scene 4
- **THEN** scene 5 SHALL carry one outfit whose origin is `continued_from_scene`
- **AND** its source reference SHALL be the scene-4 draft row reference
- **AND** its pieces SHALL be empty

### Requirement: An inferred look is label-derived, never fabricated
A gap resolved to Option B SHALL attach a `DraftOutfit` whose origin is
`inferred_from_context`, whose provenance carries the confidence, and whose name is derived
deterministically from the scene's own extracted location (never from model
text). It SHALL carry no pieces and no source quote, because the script states
no garment. The pass SHALL record a non-blocking uncertainty naming the inferred
look so the reviewer sees that wardrobe was inferred rather than extracted.

#### Scenario: Context look inferred
- **WHEN** the gap resolves to Option B for a scene whose location is "OP-SAAL"
- **THEN** the attached outfit's origin SHALL be `inferred_from_context`
- **AND** its name SHALL contain the scene's location
- **AND** its pieces SHALL be empty
- **AND** a non-blocking uncertainty SHALL name the inferred look

#### Scenario: No location to derive from
- **WHEN** the gap resolves to Option B but the scene carries no location
- **THEN** no outfit SHALL be attached
- **AND** the preview SHALL carry a non-blocking gap uncertainty instead

### Requirement: A gap uncertainty offers only script-derivable candidates
A gap resolved to Option C, or one left unresolved because the winning
probability was below the acceptance threshold, SHALL be recorded as a
non-blocking uncertainty on its scene (field `outfits`) whose candidate list
contains ONLY looks the script actually supports: a continuation of the
figure's most recent prior outfit, and — when the scene's location differs from
that prior appearance's location or the shooting/script day changed — a
context-derived look naming the scene's location. When neither candidate is
derivable the candidate list SHALL be empty and the uncertainty SHALL describe a
plain gap. No candidate SHALL be invented to fill the list.

#### Scenario: Two competing candidates
- **WHEN** the figure wore "Zivil-Look" in scene 4 and scene 5 moves to the location "OP-SAAL"
- **THEN** the uncertainty's candidates SHALL offer the continuation of "Zivil-Look" and a context look for "OP-SAAL"
- **AND** each candidate SHALL name the source it was derived from

#### Scenario: First appearance with no script basis
- **WHEN** a figure's very first appearance happens in a scene whose location is blank
- **THEN** the uncertainty's candidate list SHALL be empty
- **AND** no choice SHALL be offered to the reviewer

### Requirement: A beat's mapping address comes from the preview
The apply SHALL address every outfit beat by a position derived from the
IMMUTABLE preview — for an extracted look, the figure's outfit position across
the whole preview (counting rows and outfits the reviewer rejected or the
planner could not attribute); for a row synthesised from a reviewer's continuity
selection, the figure's position in that draft row's own character list under its
own mapping kind. No address may be derived from the plan, because a
plan-derived position shifts as soon as a review decision changes, and the
shifted row then matches another row's confirmed mapping row and silently gets no
beat.

#### Scenario: Accepting a previously rejected outfit
- **WHEN** a preview is applied with one scene's outfit rejected and re-applied with it accepted
- **THEN** that scene SHALL receive its beat
- **AND** every later row's beat address SHALL be unchanged
- **AND** no scene SHALL gain a second beat

#### Scenario: Adding another continuity selection
- **WHEN** a later apply adds a selection for an earlier gap scene
- **THEN** the already-applied selection SHALL keep its mapping address
- **AND** only the newly selected scene SHALL append a beat

### Requirement: Pass-2 output keeps the preview appliable
Every uncertainty Pass 2 records SHALL be of the non-blocking kind, so a
preview that only gained continuity gaps remains appliable without an
acknowledgement. Pass 2 SHALL NOT modify or drop any Pass-1 row, uncertainty or
score, and SHALL NOT add a second outfit to a scene that already carries one for
the same figure.

#### Scenario: Preview with gaps applies without acknowledgement
- **WHEN** a preview carries only Pass-2 gap uncertainties
- **THEN** the apply gate SHALL accept the preview
- **AND** each gap scene SHALL apply without an outfit unless the reviewer selected a candidate

#### Scenario: Pass 1 rows are untouched
- **WHEN** Pass 2 runs over a preview that Pass 1 filled completely
- **THEN** no row, uncertainty or score SHALL change
- **AND** the pass SHALL record nothing
