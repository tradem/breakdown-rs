---
name: design-tokens-dtcg
description: Author or modify breakdown-rs design tokens (W3C-DTCG JSON under design/tokens/), run the token build, and verify byte-stability/drift locally before committing. Use when a task changes theme colors, spacing, radii, type-scale, or elevation values that should flow from the shared token source into the Flutter app.
allowed-tools: Bash(bash scripts/build-tokens.sh:*), Bash(node design/validate-tokens.mjs:*), Bash(npm --prefix design ci:*), Bash(git diff:*), Bash(git status:*)
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Design Tokens (W3C-DTCG)

Author, modify, and review the design-token source at `design/tokens/`
(monorepo root — shared across frontends) and propagate changes into the
Flutter app through the pinned build pipeline.

## Read first

- `design/tokens/README.md` — format rules, DTCG types in use, non-goals.
- `openspec/changes/add-dtcg-design-tokens/design.md` — Decisions D1–D6
  (source location, Style Dictionary, data-only Dart output, seed strategy,
  determinism/drift, pinned toolchain).
- Existing token files (`color.json`, `size.json`, `typography.json`,
  `elevation.json`) — match their structure; never fork the format.

## Format rules

1. **DTCG attributes only:** leaf tokens carry `$value`, `$type`
   (`color` | `dimension` | `fontWeight`), optional `$description`. No other
   `$`-prefixed keys — the validator rejects them.
2. **DTCG 2025.10 structured `$value` shapes** (validator enforces):
   - `color` → `{colorSpace: "srgb", components: [r,g,b], hex: "#rrggbb"}` —
     bare hex strings are NOT valid; `hex` is only the optional fallback and
     must agree exactly with `components`.
   - `dimension` → `{value: <number>, unit: "px"}` — unit mandatory even for
     0; this pipeline implements only `"px"` (logical px → Dart double 1:1).
   - `fontWeight` → number 100–900.
3. **Aliases** reference other tokens as `{path.to.token}` (e.g.
   `{color.brand.seed}`); every alias must resolve (validator enforces).
4. **Light/dark sets:** semantic colors use explicit `light` and `dark`
   sub-groups per token (see `color.semantic.*`).
5. **No Flutter semantics in the JSON** (Decision D4): the M3 scheme roles
   (`primary`, `surface`, …) are NOT tokens — `ColorScheme.fromSeed`
   derives them from `color.brand.seed`. Do not add scheme-role tokens
   until a real brand palette exists (then via a scheme snapshot change).
6. **Component tokens** (per-widget colors/spacing) are a non-goal in the
   foundation; propose an OpenSpec change before adding them.

## Workflow (never commit a JSON change without the generated diff)

```bash
bash scripts/build-tokens.sh           # single entry point (from anywhere)
node design/validate-tokens.mjs        # (already part of the build) quick local check
```

1. Edit the token JSON under `design/tokens/`.
2. Run `bash scripts/build-tokens.sh` — it validates DTCG conformance,
   rebuilds via Style Dictionary (pinned by `design/package-lock.json`,
   restore with `npm --prefix design ci`), and rewrites
   `frontend-flutter/lib/design/gen/design_tokens.g.dart`.
3. Never hand-edit `lib/design/gen/design_tokens.g.dart` (rebuild-only,
   like `vendor/breakdown_api`).
4. Verify locally before committing:
   `git diff --stat` must show the JSON **and** the regenerated
   `design_tokens.g.dart` together; a second script run with no further
   changes must produce no diff (byte-stability).
5. Run the Flutter tests when values change (`flutter test` in
   `frontend-flutter/`); goldens prove pixel stability for refactors.
6. Commit JSON + generated Dart in one change — the CI drift gate
   regenerates into a throwaway directory and fails on any difference.

## Local drift check (before pushing)

```bash
mkdir -p /tmp/tokens-drift && rm -rf /tmp/tokens-drift/* \
  && DESIGN_TOKENS_OUT_DIR=/tmp/tokens-drift bash scripts/build-tokens.sh \
  && diff -r /tmp/tokens-drift frontend-flutter/lib/design/gen
```

`diff` empty = no drift. On drift: run the build script and commit its
output.

## Sample change

See `templates/sample-token-change.md` in this skill directory for a
complete worked example (JSON edit → generated Dart diff → what to verify).
