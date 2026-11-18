<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.4 (opencode-go) -->

# flutter-ai-import-workflow Delta — Pass-2 outfit provenance & wardrobe gaps

## ADDED Requirements

### Requirement: The preview states where each look came from
The preview SHALL render exactly ONE provenance badge per outfit row, keyed on
the row's `DraftOutfit.origin`: `explicit_quote` (quoted from the script),
`derived` (derived from the script), `continued_from_scene` (continued from the
source scene named by `DraftOutfit.provenance.source_scene_number`, degrading to
"an earlier scene" when the wire carries no number) and
`inferred_from_context` (inferred from the scene context). The badge SHALL be a
visible, localized element with a per-row test key — never the raw wire slug.

An outfit row whose origin is absent (a preview stored before the field existed)
or unrecognized SHALL render NO badge: provenance is never inferred from the
presence of a quote, a scene number or a confidence value.

#### Scenario: A continued look names its source scene
- **WHEN** an outfit row carries `origin = continued_from_scene` with
  `provenance.source_scene_number = 4`
- **THEN** the row renders the badge "continued from scene 4"
- **AND** the badge is keyed for that row and ordinal

#### Scenario: An origin-less row carries no badge
- **WHEN** an outfit row carries no origin (a preview stored before the field)
- **THEN** the row renders no provenance badge and no attribution is invented

### Requirement: A Pass-2 look renders no source quote
The source-quote line SHALL render only for an outfit row whose origin carries
its own grounding evidence (`explicit_quote`, `derived`, or an absent origin on
a pre-change preview). A `continued_from_scene` or `inferred_from_context` row
SHALL NOT render the quote line, because the server leaves `source_quote` empty
for those rows and an empty evidence line would read as if the script had stated
the look.

#### Scenario: An inferred look shows no evidence line
- **WHEN** an outfit row carries `origin = inferred_from_context` and an empty
  `source_quote`
- **THEN** the row renders its provenance badge and no "Source:" line
- **AND** a quoted row of the same preview still renders its evidence

### Requirement: The reviewer resolves a wardrobe gap with one tap
For a `dropped_row` uncertainty on the `outfits` field whose `candidates` list
is non-empty, the preview SHALL render a gap card with the server's note
verbatim, ONE selectable option per candidate (the candidate's look name plus
the server's confidence) and an explicit option that leaves the scene without a
look. The default SHALL be "leave without a look". A gap whose candidate list is
empty SHALL keep the existing plain uncertainty notice, and no option beyond the
server's list SHALL ever be offered.

#### Scenario: Both script-derivable candidates are offered
- **WHEN** a scene carries a gap uncertainty with a continuation candidate and
  a context candidate
- **THEN** the gap card offers both, each rendering its own look name
- **AND** the third option leaves the scene without a look, selected by default

#### Scenario: A gap without candidates offers nothing
- **WHEN** a gap uncertainty carries an empty candidate list
- **THEN** the plain uncertainty notice renders and no gap card, chip or
  selectable option appears for it

### Requirement: A pick travels as a continuity selection
The apply request SHALL carry one `continuity_selections` entry per resolved
gap, addressed by the gap's `scene_index` and the figure's preview-wide
`character_identity` (case-folded, whitespace-collapsed character name derived
from the gap's own scene — the identity the server validates against, never a
re-normalization of the server's note prose). The field SHALL be absent when no
gap was resolved. A resolved pick SHALL count as a review edit, so
`accept_as_is` / `edit_distance` stay truthful about the review.

#### Scenario: Picking the continuation sends the selection
- **WHEN** the reviewer picks the continuation candidate for the gap of figure
  "BEN" in the preview's scene index 1
- **THEN** the apply request carries one selection with `scene_index = 1`,
  `character_identity = "ben"` and `candidate = continued`
- **AND** the request reports `accept_as_is = false`

#### Scenario: An unresolved gap applies unchanged
- **WHEN** the reviewer leaves every gap without a look
- **THEN** the apply request carries no `continuity_selections` at all
- **AND** the apply is dispatched and reported like a pre-change client's

### Requirement: The dispatch states each gap's resolution
The apply card SHALL render one summary line per preview gap, naming the scene,
the figure and the look the pick applies — or that the scene deliberately stays
without one. A `409 ai-import.apply-unknown-continuity-candidate` SHALL surface
as the localized "refresh the preview and re-apply" narrative, keyed on the
stable `code` (never the server `detail`).

#### Scenario: Refreshed preview refuses a stale pick
- **WHEN** the apply is answered with `409
  ai-import.apply-unknown-continuity-candidate`
- **THEN** the apply card renders the refresh-and-re-apply copy
- **AND** the client does not re-derive or silently drop the pick
