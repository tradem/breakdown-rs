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
**Format Module 2025.10** (stable): leaf tokens carry `$value`, `$type`, and
optional `$description`; values reference other tokens via `{path.to.token}`
aliases. Values use the 2025.10 structured forms:

- `color`: `{"colorSpace": "srgb", "components": [r, g, b], "hex": "#rrggbb"}`
  — bare hex strings are NOT valid color values in 2025.10; `hex` is only the
  optional fallback inside the object and must agree exactly with
  `components` (the validator enforces this).
- `dimension`: `{"value": <number>, "unit": "px"}` — the unit is mandatory
  even for 0; this pipeline implements only `"px"` (logical px, mapping 1:1
  to Dart doubles; `"rem"` would be valid DTCG but is rejected here).
- `fontWeight`: a number 100–900.

- `color.json` — primitive color tokens (incl. `color.brand.seed`, the
  M3 `ColorScheme.fromSeed` seed) and semantic status colors with explicit
  **light** and **dark** sets.
- `size.json` — dimension tokens: spacing scale (1:1 with the app's
  `AppSpacing`) and corner radii.
- `typography.json` — M3 2021 type scale as scalar dimension tokens
  (composite typography values are not emitted to Dart — Decision D3).
- `elevation.json` — M3 elevation levels.
- `component.json` — **component token** groups (today: `component.appBar.*`,
  the pushed-screen header). See "Component tokens" below for the rules that
  keep this group small.

**Rules:** no Flutter-specific semantics in the JSON (exact
`ColorScheme` composition stays Flutter-side, Decision D4 — the seed IS the
token, scheme roles derive from it); every change must run through the build
below and commit the regenerated output together with the JSON change; hand
edits to any generated artifact are forbidden.

## Component tokens

The `add-dtcg-design-tokens` foundation listed component tokens as a
**non-goal** ("component tokens follow when the design system grows"). Issue
#838 relaxes that non-goal for the first component that genuinely needs its own
value: the pushed-screen header (issue #824), whose 48 dp height used to be
derived by `max(...)` in `lib/design/header_metrics.dart`.

Adding a group to `component.json` is allowed **only** under these rules:

1. **State only the decision no primitive can state.** `component.appBar.height`
   is 48 dp because that is the Material interactive floor the back button's
   touch target needs — no type or spacing token can express that clamp.
   Where a primitive already owns a value, **alias it** instead of retyping it:
   `component.appBar.titleFontSize` is `{typography.fontSize.titleLarge}`,
   `component.appBar.titleLineHeight` is `{typography.lineHeight.titleLarge}`,
   `component.appBar.verticalPadding` is `{size.space.8}`. A dimension `$value`
   may therefore be a `{alias.reference}` string (the validator checks that the
   reference points at another `dimension` token), exactly as a color already
   could.
2. **One consumer, read from the generated artifact.** The value is consumed by
   hand-written code through `design_tokens.g.dart` (today:
   `HeaderMetrics`), never re-derived at a call site.
3. **A relaxation needs its own change.** Propose it (OpenSpec) and record the
   relaxation there, as this group's change
   (`838-appbar-component-token`) does.

Component tokens stay data: no Flutter semantics, no scheme roles, no widget
structure — those remain hand-authored (Decision D4).

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
