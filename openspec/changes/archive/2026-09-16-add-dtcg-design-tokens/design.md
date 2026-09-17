<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

Today `lib/design/theme.dart` builds both M3 themes from
`ColorScheme.fromSeed` with a hand-picked seed, and
`lib/design/spacing.dart` is a hand-written `ThemeExtension` with
double values. Styling truth lives in Dart constants — not diffable as
data, unable to feed sibling frontends (Svelte/Slint/GPUI planned).
The research report's scorecard ranked Design-Tokens-first highest
(4.65/5) precisely because the W3C-DTCG JSON format is
platform-neutral and git-native. Team decision 5 ordered this work
**before** the redesign changes (P0) so shell/home/wizard consume
tokens from day one. DTCG spec status: stable (2025-10); Style
Dictionary and Terrazzo both consume it and have Flutter targets.

## Goals / Non-Goals

**Goals:**
- DTCG token source at `design/tokens/` (monorepo level).
- Deterministic generation into
  `frontend-flutter/lib/design/gen/design_tokens.g.dart`.
- `theme.dart`/`spacing.dart` read generated values; public API
  stable (no widget call-site changes).
- CI drift gate (regenerate-and-diff) mirroring the OpenAPI client
  discipline.
- Agent skill `design-tokens-dtcg`.

**Non-Goals:**
- No new visual design (values are carried over 1:1 from today's
  seed/scheme/spacing — a visual redesign is later work).
- No Svelte/Slint/GPUI build targets (only the JSON source is shared;
  each target is its own future change).
- No dynamic color / Material You (dynamic scheme) — static seed from
  the token source.
- No component-level tokens yet (only color/typography/spacing/radius/
  elevation); component tokens follow when the design system grows.

## Decisions

### D1 — Token source location: monorepo root `design/tokens/`
Not inside `frontend-flutter/` — the whole point is cross-frontend
reuse (mirroring how shared assets live in this repo).

*Alternative:* `frontend-flutter/design/tokens/` rejected: Svelte and
Rust frontends would then need cross-package references into the
Flutter tree.

### D2 — Generator: Style Dictionary
Style Dictionary (v4) is the mature, widely-documented choice with
built-in DTCG-format support and a Flutter transformGroup.

*Alternative:* Terrazzo is newer and DTCG-native but has a smaller
ecosystem and less predictable plugin stability; can be revisited if
Style Dictionary's Flutter output proves limiting. The decision point
is isolated in the config + script — switching later means rewriting
the generator config, not the token source.

### D3 — Generated output shape: single Dart class + ThemeExtension
`design_tokens.g.dart` exposes const `Color`/`double` values (generated
class, e.g. `DesignTokens.colorPrimary`); `theme.dart` composes
`ColorScheme` from them; `spacing.dart` delegates to generated
dimension tokens. No ThemeExtension in the generated file — the
existing handwritten extension stays the public API.

*Why:* keeps generation dumb (data only) and Flutter semantics
(schemes, extensions) hand-authored where they can be reviewed; the
generated file stays replaceable byte-for-byte by a re-run.

### D4 — Seed strategy: seed-color token drives ColorScheme.fromSeed
The token source defines `color.brand.seed` (primitive); Flutter
builds `ColorScheme.fromSeed(seedColor: DesignTokens.colorBrandSeed,
brightness: ...)` exactly as today. All other scheme roles remain
derived by M3 (not duplicated as tokens) in this change.

*Why:* duplicating every M3 scheme role into tokens now would freeze
an M3-internal mapping and double maintenance;
`fromSeed` remains the compatibility anchor; role-level overrides go
into the token source later when a real brand palette exists
(then generated via a scheme snapshot).

### D5 — Determinism & drift gate
Script runs Style Dictionary with sorted/filtered output, no
timestamps; CI job regenerates and `diff -r` against the committed
tree; byte-identical required (same pattern as regen-client for the
OpenAPI Dart client, which enabled us to trust regeneration).

### D6 — Node toolchain pinned
`scripts/build-tokens.sh` uses a pinned Node/npm-ci setup with the
lockfile committed (CI-hardening: no `latest`, no unpinned network
fetch at build time beyond npm registry resume of pinned versions).

## Risks / Trade-offs

- [Style Dictionary JSON→Dart output naming churn] → we own a tiny
  format filter in the config; lockfile keeps generator version
  pinned; output is data-only (D3) so churn risk is contained.
- [Two sources of truth concern: `fromSeed`-derived roles not in
  tokens] → documented explicitly (D4): the seed IS the token; roles
  derive; until role-level tokens exist, scheme role changes are
  Flutter-side decisions.
- [CI cost: Node toolchain in a job] → job only triggers on
  `design/tokens/**` + config paths; npm cache; job remains < 1 min.
- [Monorepo-level `design/` dir is new conventions] → README inside
  the folder; root AGENTS.md cross-reference is part of the design-doc
  workflow change (establish-design-doc-workflow) — here only the
  build script documents itself.

## Migration Plan

1. Add token source with 1:1 values from current theme/spacing.
2. Add script + config; generate; verify byte-stable on re-run.
3. Rewire `theme.dart`/`spacing.dart` to generated values (pure
   refactor — goldens must stay identical).
4. Add CI drift job; wire into existing frontend workflows.
5. Rollback: revert the change; regenerate path simply disappears,
   `fromSeed` constants return via revert.

## Open Questions

- None blocking. (Light/dark set topology in JSON — one file with
  two mode sets vs. two files — is decided during implementation per
  Style Dictionary conventions; spec only requires both modes exist.)
