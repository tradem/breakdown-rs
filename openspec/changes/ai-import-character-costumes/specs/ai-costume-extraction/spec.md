## ADDED Requirements

### Requirement: Costume extraction is a named-entity task over named evidence sources
The script import prompt SHALL specify costume extraction as an
entity-recognition task over an explicit, ordered list of evidence sources in
the screenplay text, and SHALL NOT leave the decision to extract costuming to
the model's initiative. The evidence sources are: (1) a character parenthetical
that names clothing (`ANNA (30, Lederjacke)`), (2) a `Kostümbild` /
`Kostüme` note, (3) clothing attached to a person in an action line
("der ölverschmierten Mechaniker-Overall"). Accessories (Schmuck, Hut, Brille,
Tasche) SHALL count as costume. `location`, `scene_number`, `script_day` and
`mood` SHALL be taken from the scene heading or the literal text, never inferred.

#### Scenario: Costuming written as a character parenthetical
- **WHEN** a scene block contains `RENEE SANDERS (39) … ölverschmierter Mechaniker-Overall`
- **THEN** the draft scene for that block SHALL carry a costume entry with the
  character name, the clothing description and the quoted source text
- **AND** the description SHALL preserve the script's own wording

#### Scenario: Costuming written as a Kostümbild note
- **WHEN** a scene block contains a `Kostümbild: BEN in Marineblau, Schmuck: Silberkette` note
- **THEN** each named costume entry SHALL be extracted as its own draft costume
- **AND** the accessory SHALL be recorded as costume, not discarded as set dressing

#### Scenario: Block without any costuming
- **WHEN** a scene block names a location and a day marker but no clothing
- **THEN** the draft scene SHALL carry an empty costume list
- **AND** the import SHALL NOT be treated as a failure for that block

### Requirement: The model must not invent costuming
The prompt SHALL forbid inventing a costume, character, location or prop that
the text does not state, and SHALL require every extracted costume to be
traceable to a quoted fragment of the supplied text. A draft costume whose
source text is not present in the input block SHALL be rejected rather than
stored. The bound on the LLM call (retry budget, truncation growth) SHALL remain
as specified for the script import; costume extraction SHALL NOT add a second
paid pass.

#### Scenario: Model returns a costume that the text does not support
- **WHEN** a returned costume carries a `source_quote` that does not occur in the
  supplied scene block
- **THEN** the costume SHALL be dropped from the draft and recorded as an
  uncertainty instead of being presented to the reviewer as extracted data

### Requirement: A draft costume names its character
Each extracted costume SHALL be attributable to exactly one character of the
same draft scene. The system SHALL reject a costume whose character is not in
the scene's own character list and SHALL record it as an uncertainty, because a
costume without its figure has no meaning in the costume-continuity domain
(`costume-character-binding`: a `Costume` binds to a `Character` and nothing else).

#### Scenario: Costume references an unlisted character
- **WHEN** a returned costume names a character that the same draft scene does not list
- **THEN** the costume SHALL NOT become a draft costume row
- **AND** an uncertainty SHALL be recorded naming the unmatched character
