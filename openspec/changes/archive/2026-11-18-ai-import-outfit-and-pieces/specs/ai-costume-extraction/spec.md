<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## MODIFIED Requirements

### Requirement: Costume extraction is a named-entity task over named evidence sources
The script import prompt SHALL specify outfit extraction as an entity-recognition
task over an explicit, ordered list of evidence sources in the screenplay text, and
SHALL NOT leave the decision to extract wardrobe to the model's initiative. The
evidence sources are: (1) a character parenthetical that names clothing
(`ANNA (30, Lederjacke)`), (2) a `Kostümbild` / `Kostüme` note, (3) clothing
attached to a person in an action line ("der ölverschmierten Mechaniker-Overall"),
(4) an occupational or medical wardrobe shorthand (`KHK`, `OP`, `ITS`, `OP-Grün`,
`Bereichskleidung`, `Flügelhemd`, police uniform, doctor's coat, paramedics).
Accessories (Schmuck, Hut, Brille, Tasche) SHALL count as wardrobe. `location`,
`scene_number`, `script_day` and `mood` SHALL be taken from the scene heading or the
literal text, never inferred.

#### Scenario: Wardrobe written as a character parenthetical
- **WHEN** a scene block contains `RENEE SANDERS (39) … ölverschmierter Mechaniker-Overall`
- **THEN** the draft scene for that block SHALL carry a draft outfit with the
  character name, an outfit name and the quoted source text
- **AND** the outfit and its piece names SHALL preserve the script's own wording

#### Scenario: Wardrobe written as a Kostümbild note
- **WHEN** a scene block contains a `Kostümbild: BEN in Marineblau, Schmuck: Silberkette` note
- **THEN** each named entry SHALL be extracted as its own draft outfit
- **AND** the accessory SHALL be recorded as wardrobe, not discarded as set dressing

#### Scenario: Wardrobe written as a medical shorthand
- **WHEN** a scene block reads `DR. KOCH (in OP)` and states no further clothing
- **THEN** the draft scene SHALL carry a draft outfit for `DR. KOCH` whose
  `source_quote` is the parenthetical naming the shorthand
- **AND** the draft outfit SHALL decompose into its constituent pieces even though
  the block names none of them individually

#### Scenario: Block without any wardrobe
- **WHEN** a scene block names a location and a day marker but no clothing
- **THEN** the draft scene SHALL carry an empty outfit list
- **AND** the import SHALL NOT be treated as a failure for that block

### Requirement: The model must not invent wardrobe
The prompt SHALL forbid inventing an outfit, piece, character, location or prop that
the text does not state, and SHALL require every extracted outfit to be traceable to
a quoted fragment of the supplied text. A draft outfit whose source text is not
present in the input block SHALL be rejected rather than stored. Grounding SHALL be
enforced at the **outfit** level, not at the individual piece level, because
screenplays name a look by shorthand (`"in OP"`) and never enumerate its garments.
The bound on the LLM call (retry budget, truncation growth) SHALL remain as specified
for the script import; outfit extraction SHALL NOT add a second paid pass.

#### Scenario: Model returns an outfit that the text does not support
- **WHEN** a returned outfit carries a `source_quote` that does not occur in the
  supplied scene block
- **THEN** the outfit and all of its pieces SHALL be dropped from the draft and
  recorded as an uncertainty instead of being presented to the reviewer as
  extracted data
- **AND** the uncertainty SHALL carry the reason as a stable machine-readable
  value, not prose only

#### Scenario: A derived piece of a grounded outfit is kept
- **WHEN** a scene block states only `PATIENT (in KHK)` and the model returns an
  outfit for `PATIENT` quoting that fragment with the pieces `KHK-Hemd` and
  `KHK-Hose`
- **THEN** the outfit SHALL be kept, and its pieces SHALL be kept with it
- **AND** the pieces SHALL NOT be rejected for not appearing verbatim in the block

#### Scenario: A quote taken across a line wrap still grounds
- **WHEN** a returned `source_quote` differs from the document only by whitespace
  runs or letter case, because the model quoted across a line break
- **THEN** the outfit SHALL be kept: the check compares folded text, so a
  genuinely quoted fragment is never dropped for a formatting difference

### Requirement: A draft outfit names its character
Each extracted outfit SHALL be attributable to exactly one character of the same
draft scene. The system SHALL reject an outfit whose character is not in the scene's
own character list and SHALL record it as an uncertainty, because an outfit without
its figure has no meaning in the costume-continuity domain (`outfit`: an `Outfit`
carries a mandatory `character_id`).

#### Scenario: Outfit references an unlisted character
- **WHEN** a returned outfit names a character that the same draft scene does not list
- **THEN** the outfit SHALL NOT become a draft outfit row
- **AND** an uncertainty SHALL be recorded naming the unmatched character
- **AND** that uncertainty SHALL NOT block applying the rest of the preview

## ADDED Requirements

### Requirement: A draft outfit decomposes into constituent pieces with category hints
Each draft outfit SHALL carry `0..n` constituent pieces, and each piece SHALL carry
a name plus an optional `category_hint` and an optional description. The prompt SHALL
derive the pieces from the outfit itself when the block names only the look, using
German garment names (`OP-Kasack`, `OP-Hose`, `OP-Haube`), and SHALL name the
category hint from the canonical vocabulary the season seeds (`Oberteil`,
`Unterteil`, `Schuhe`, `Jacke`, `Accessoires`). The decomposition SHALL be driven by
prompt rules, not by a hardcoded glossary: spelling variants of one look
(`OP`, `OP-Grün`, `Kasack`, `KHK`, `Flügelhemd`) SHALL NOT require a server-side
dictionary entry to be recognized.

#### Scenario: Shorthand outfit yields its typical pieces
- **WHEN** a block states `SCHWESTER ANKE (in OP)` and nothing else about clothing
- **THEN** the draft outfit for `SCHWESTER ANKE` SHALL carry at least a top piece
  and a bottom piece with German garment names
- **AND** the top piece's `category_hint` SHALL be `Oberteil` and the bottom
  piece's SHALL be `Unterteil`

#### Scenario: Prose wardrobe description yields pieces too
- **WHEN** a block describes `im abgetragenen Bademantel und Gummistiefeln`
- **THEN** the draft outfit SHALL carry a piece for the robe and a piece for the
  boots
- **AND** the boots' `category_hint` SHALL be `Schuhe`

#### Scenario: An unknown category hint is not an error
- **WHEN** a returned piece carries a `category_hint` that the target season's
  category vocabulary does not contain
- **THEN** the piece SHALL still be extracted and applied
- **AND** it SHALL be created without a category (`category_id` absent)

#### Scenario: An outfit with no pieces stays applicable
- **WHEN** a returned outfit carries an empty piece list
- **THEN** the outfit SHALL be applied as an outfit without pieces
- **AND** the import SHALL NOT be treated as a failure for that outfit
