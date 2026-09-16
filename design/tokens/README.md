<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Design Tokens (W3C-DTCG source)

This directory is the **platform-neutral design-token source** for all
breakdown-rs frontends (Flutter today; Svelte/Slint/GPUI later). It is the
shared styling truth, diffable as data — not Dart constants (spec
`design-tokens`, OpenSpec change `add-dtcg-design-tokens`).

## Format

[W3C Design Tokens Community Group (DTCG)](https://www.w3.org/community/design-tokens/)
format, stable 2025-10: leaf tokens carry `$value`, `$type`, and optional
`$description`; values reference other tokens via `{path.to.token}` aliases.
Types used here: `color` (hex strings) and `dimension` (unitless numbers =
logical px).

- `color.json` — primitive color tokens (incl. `color.brand.seed`, the
  M3 `ColorScheme.fromSeed` seed) and semantic status colors with explicit
  **light** and **dark** sets.
- `size.json` — dimension tokens: spacing scale (1:1 with the app's
  `AppSpacing`) and corner radii.
- `typography.json` — M3 2021 type scale as scalar dimension tokens
  (composite typography values are not emitted to Dart — Decision D3).
- `elevation.json` — M3 elevation levels.

**Rules:** no Flutter-specific semantics in the JSON (exact
`ColorScheme` composition stays Flutter-side, Decision D4 — the seed IS the
token, scheme roles derive from it); every change must run through the build
below and commit the regenerated output together with the JSON change; hand
edits to any generated artifact are forbidden.

## Build

`scripts/build-tokens.sh` (monorepo root) is the single entry point:

```bash
bash scripts/build-tokens.sh
```

It validates the DTCG conformance of this directory, runs Style Dictionary
(pinned versions via `design/package-lock.json`, restored with `npm --prefix
design ci`), and writes
`frontend-flutter/lib/design/gen/design_tokens.g.dart` (rebuild-only, like
`vendor/breakdown_api`). A second run without source changes produces a
byte-identical tree — CI enforces this drift gate.

For agents: see the `design-tokens-dtcg` skill
(`frontend-flutter/.pi/skills/design-tokens-dtcg/SKILL.md`).

## Vocabulary

Terminology and UI vocabulary are governed separately by
`docs/design/glossary.md` (workflow: `establish-design-doc-workflow`). The
glossary references this directory for theme-relevant token names; token
*values* live here, token *names/labels used in specs* live there.
