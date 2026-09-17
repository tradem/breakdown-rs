<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

`lib/design/theme.dart` is hand-written (ColorScheme.fromSeed +
a spacing extension) — the styling truth lives in Dart code, is not
diffable as data, and cannot feed the future Svelte/Slint/GPUI
frontends. The UI/UX research report (scorecard winner "Design
Tokens-first", 4.65/5 weighted) recommends the W3C-DTCG JSON format as
the portable token source; team decision 5 explicitly pulled this
pipeline **before** the redesign changes so the app shell, seasons
home, and wizard are token-based from day one with no double work.

## What Changes

- Introduce a DTCG-format token source at `design/tokens/` (monorepo
  level: shared by all frontends): `$value`/`$type`/`$description`
  attributes, alias references, light/dark color token sets,
  dimension tokens for spacing/radius, typography scale, elevation.
- Add a Style Dictionary (or Terrazzo — decided in design.md) build that
  generates `frontend-flutter/lib/design/gen/design_tokens.g.dart` from
  the token source; the generation script is the single entry point
  (`scripts/build-tokens.sh`), regenerate-only like the OpenAPI client.
- Migrate `lib/design/theme.dart` and `lib/design/spacing.dart` to
  consume generated tokens as their values (public API of the design
  package stays stable during this change; widget call sites unchanged).
- CI drift gate: regenerating tokens must produce a byte-identical tree
  to the committed one (mirrors the OpenAPI client drift check).
- Skill `design-tokens-dtcg` for agents (author/modify tokens, run the
  build, detect drift).

## Capabilities

### New Capabilities
- `design-tokens`: the DTCG token source structure, generation pipeline,
  drift gate, and authoring rules shared across frontends.

### Modified Capabilities
- `flutter-design-tokens`: the requirement "Light and Dark M3 Themes
  from Tokens" is modified — themes SHALL be built from the **generated
  DTCG-derived Dart tokens** (still ColorScheme-based; seed color now
  sourced from the token file) instead of hand-written constants;
  spacing tokens SHALL come from the generated dimension tokens.

## Impact

- **New:** `design/tokens/**/*.json`, `scripts/build-tokens.sh`,
  `design/style-dictionary.config.*`, generated
  `frontend-flutter/lib/design/gen/` (rebuild-only), Node tooling pinned
  in the repo (CI-hardening: pinned versions + lockfile).
- **Modified:** `frontend-flutter/lib/design/theme.dart`,
  `lib/design/spacing.dart` (values now read from generated tokens),
  CI workflows (new drift job).
- **No change:** widget call sites (screens keep using
  `Theme.of(context)` and the spacing extension — only the values'
  origin changes), backend, API.
