<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: DTCG token source structure
The repository SHALL hold its design token source in
W3C-DTCG-conformant JSON files under `design/tokens/` (monorepo root),
using `$value`, `$type`, and optional `$description` attributes with
`{path.to.token}` alias references. The source SHALL define:
primitive color tokens, semantic color tokens (light and dark sets),
dimension tokens (spacing scale, corner radii), typography scale
tokens, and elevation tokens. Flutter-specific values (e.g. exact
`ColorScheme` composition) SHALL NOT leak into the token source.

#### Scenario: Token file conforms to DTCG
- **WHEN** a token file under `design/tokens/` is validated against the
  DTCG format rules ($-prefixed properties, resolvable alias
  references)
- **THEN** the validation passes as part of the token build script

#### Scenario: New frontend consumes the source
- **WHEN** a future frontend (Svelte, Slint, GPUI) adds a token
  generation target
- **THEN** it consumes the same `design/tokens/` JSON source without
  modifying it

### Requirement: Token generation pipeline
`scripts/build-tokens.sh` at the monorepo root SHALL be the single
entry point that transforms `design/tokens/**/*.json` into
platform artifacts; for this change the only target is Flutter
(`frontend-flutter/lib/design/gen/design_tokens.g.dart`). The script
SHALL pin generator versions via a checked-in lockfile, produce
byte-stable output (no timestamps, deterministic ordering), and print
an explicit regenerate instruction on usage.

#### Scenario: Developer changes a token
- **WHEN** a developer edits a token JSON and runs
  `bash scripts/build-tokens.sh`
- **THEN** the generated Dart file updates deterministically and the
  Flutter build picks up the new values

#### Scenario: Generated tree is hand-edited
- **WHEN** a hand edit to `lib/design/gen/` is detected (CI drift diff)
- **THEN** the pipeline fails and instructs regeneration

### Requirement: Token build runs in CI with drift detection
CI SHALL (a) execute the token build on every change touching
`design/tokens/**` or the generator config, and (b) run a drift check
that regenerates into a throwaway directory and diffs against the
committed tree, failing on any difference.

#### Scenario: Pull request changes tokens
- **WHEN** a PR modifies `design/tokens/` but does not commit the
  regenerated output
- **THEN** CI fails the drift check with the files that differ

### Requirement: Agent skill for token authoring
A `design-tokens-dtcg` skill (pi SKILL.md) SHALL document how agents
author/modify tokens (DTCG format rules, alias/reference usage,
light/dark set conventions), run the build script, and verify drift
locally before committing.

#### Scenario: Agent modifies a semantic color
- **WHEN** the skill is used to change a semantic color token
- **THEN** the skill workflow requires running `scripts/build-tokens.sh`
  and committing the regenerated output together with the JSON change
