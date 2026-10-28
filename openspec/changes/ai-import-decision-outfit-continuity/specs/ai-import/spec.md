<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## ADDED Requirements

### Requirement: The preview distinguishes outfit provenance
The script preview SHALL expose, per outfit row, where the look came from, as ONE
plain wire string of `explicit_quote`, `derived`, `continued_from_scene` or
`inferred_from_context`. The Pass-2 provenance payload SHALL travel in a separate
optional `provenance` object carrying the source draft row reference, the source
scene number when known, and the confidence — never as data on the origin value
itself, because a mixed enum lowers to a `oneOf` whose two single-value string
alternatives make the generated client unable to decode `"explicit_quote"` at
all. The distinction SHALL be additive on the wire, so a preview stored before
the provenance existed still loads and keeps reading as `explicit_quote` with no
provenance.

#### Scenario: Reviewing a continued outfit
- **WHEN** a draft row's outfit continues an earlier scene's look
- **THEN** the preview SHALL report its origin as `continued_from_scene`
- **AND** its `provenance` SHALL name the source draft row and scene number
- **AND** its confidence SHALL be the probability the Decision Model reported

#### Scenario: Preview stored before provenance existed
- **WHEN** a preview stored with the former two-value origin is served
- **THEN** it SHALL deserialize without error
- **AND** every outfit row SHALL keep a valid origin and an empty provenance

#### Scenario: The origin stays client-decodable
- **WHEN** a client decodes any of the four origin values
- **THEN** each SHALL be a plain JSON string
- **AND** no origin value SHALL be modelled as a union of alternatives

### Requirement: A gap uncertainty carries only script-derivable candidates
An uncertainty of kind `dropped_row` on the `outfits` field MAY carry a list of
outfit candidates. Each candidate SHALL declare its origin, its display name,
the draft row it was derived from, and its confidence. The list SHALL be empty
when the script supports no candidate, and the preview SHALL never present an
invented option as a choice.

#### Scenario: Candidate list on a competing gap
- **WHEN** a scene carries a gap uncertainty whose figure has a prior outfit and whose location changed
- **THEN** the uncertainty SHALL carry both candidates
- **AND** each candidate SHALL name its origin and source draft row

#### Scenario: Gap without candidates
- **WHEN** the script supports no candidate for a gap
- **THEN** the uncertainty's candidate list SHALL be empty
- **AND** the preview SHALL still expose the gap as an uncertainty

### Requirement: A continued outfit reuses the source scene's OutfitId
For an outfit row whose origin is `continued_from_scene`, the apply planner
SHALL resolve the source row and the source outfit's ordinal from the immutable
preview and SHALL plan NO new pieces and NO new outfit. The apply worker SHALL
resolve the source outfit's aggregate id from the persisted apply mapping and
dispatch only the scene's outfit beat against that exact id, so the two scenes
cast the same `Outfit` (reference by identity, no duplicate aggregate). When the
source row or its outfit cannot be resolved in the preview, the plan SHALL
report the row as unapplied with a reason distinct from the create/beat
failures instead of creating a look of its own; when the source outfit's mapping
row does not exist or never reached its create, the worker SHALL report the same
distinct reason rather than fabricating an id.

#### Scenario: Two scenes share one outfit
- **WHEN** an accepted preview contains a scene-4 outfit and a scene-5 continuation of it
- **THEN** the apply SHALL create exactly one `Outfit` for that figure
- **AND** both scenes SHALL carry an outfit beat referencing it
- **AND** re-applying the preview SHALL add no second `Outfit` and no second beat

#### Scenario: Continuation whose source was rejected
- **WHEN** the reviewer rejects the source outfit row while accepting the continuation
- **THEN** no `Outfit` SHALL be created for the continuation
- **AND** the apply result SHALL report it as unapplied with the continuation reason

### Requirement: The reviewer may resolve a gap by selecting a candidate
The apply request SHALL accept, per gap, an optional selection of one of the
candidates the preview offered for that scene and character. A selection SHALL
be validated against the preview's own candidate list — an unknown scene index,
an unknown character identity or a candidate the preview does not offer SHALL be
refused as a client error. An accepted selection SHALL be planned as an outfit
row of its scene: a continuation selection plans as a
`continued_from_scene` row (no created look), a context selection plans as an
`inferred_from_context` row carrying the candidate's label and no pieces. A gap
without a selection SHALL apply without an outfit — never with an invented one.

#### Scenario: Reviewer picks the continuation
- **WHEN** the apply request selects the continuation candidate for a gap
- **THEN** the scene's beat SHALL reference the prior scene's `Outfit`
- **AND** no new `Outfit` SHALL be created for that row

#### Scenario: Reviewer picks nothing
- **WHEN** the apply request carries no selection for a gap scene
- **THEN** the scene SHALL apply without an outfit
- **AND** the apply SHALL NOT fail because of the gap

#### Scenario: Selection the preview never offered
- **WHEN** the apply request selects a candidate for a scene/character pair the preview does not carry as a gap
- **THEN** the apply SHALL be refused as a validation error
- **AND** no aggregate SHALL be dispatched
