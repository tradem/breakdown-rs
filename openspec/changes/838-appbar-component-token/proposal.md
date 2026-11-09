<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 838 — The header height is a design token, not an arithmetic derivation

## Why

Issue #824 fixed the pushed-screen header honestly but second-best: its height
is a `max(...)` expression in `lib/design/header_metrics.dart`

```dart
toolbarHeight = contentHeight < kMinInteractiveDimension
    ? kMinInteractiveDimension
    : contentHeight;   // contentHeight = lineHeight (28) + 2 × padding (8) = 44
```

because `component.*` tokens were an explicit non-goal of the design-token
foundation (`add-dtcg-design-tokens`, Non-Goals; `design/tokens/README.md`).
Three consequences, all real:

- A designer cannot retune the header without a code change and a rebuild.
- The 48 dp value is a *clamp*, not a decision: raising
  `typography.lineHeight.titleLarge` silently does nothing until the sum
  exceeds the floor — there is nothing to review.
- `HeaderMetrics` duplicates a `max(...)` rule the token source could state
  once.

The header is the first component that genuinely needs its own value. This
change is the small OpenSpec change that already pins the **relaxation of the
component-token non-goal** to evidence (one real consumer, one decision no
primitive can state), instead of relaxing the rule in prose.

## What changes

- **New token group** `component.appBar.{height, titleFontSize,
  titleLineHeight, verticalPadding}` in `design/tokens/component.json`.
  `height` is the decision (48 dp = the Material interactive floor the leading
  back button's touch target needs); the other three are **aliases** of the
  primitives they are built from (`{typography.fontSize.titleLarge}`,
  `{typography.lineHeight.titleLarge}`, `{size.space.8}`), so retuning the type
  or spacing scale flows into the header token without a second edit.
- **Dimension validator:** a `dimension` `$value` may now be a
  `{alias.reference}` string (it could not be, although a `color` already
  could), and the reference is type-checked — a dimension token must alias
  another `dimension` token.
- **`HeaderMetrics` reads the tokens:** `toolbarHeight`,
  `fontSize`, `lineHeight` and `verticalPadding` are direct reads of the
  generated constants; `contentHeight` (the arithmetic) is **gone**. The
  derivation survives as the token's `$description` and as a test invariant.
- **Docs:** `design/tokens/README.md` gains a "Component tokens" section with
  the three rules a future group must satisfy; the `design-tokens-dtcg` skill's
  former "component tokens are a non-goal" rule is rewritten to the same
  contract; the screen-spec header rule names the token.

Values are unchanged: the app still renders a 48 dp header around a 22 sp
title. **No golden is re-baselined** — this change moves the value, it does not
change it.

## Decisions

### D1 — The token states the clamp, the aliases keep the scale authoritative

`component.appBar.height` is a literal 48 dp, not another derivation: DTCG has
no arithmetic, and the clamp *is* the design decision. The title size, line
height and padding alias the primitives so there is exactly one place to retune
them. The invariant "the content sum must not outgrow the height" is pinned by
`test/design/header_metrics_test.dart` — a future type-scale change that would
clip the header fails a test instead of silently relying on a `max(...)`.

### D2 — Relax the non-goal with rules, not with an exception

A component token is allowed when (a) it states a decision no primitive can
state, (b) everything else in the group aliases the primitives, (c) exactly one
hand-written consumer reads the generated value, and (d) an OpenSpec change
records the relaxation. Stated in `design/tokens/README.md` (the token source's
own contract) and mirrored in the agent skill, so an agent authoring the next
group reads the rules where it reads the format.

### D3 — Dimension aliases are validated by type, not just by existence

The validator already required every `{alias}` to resolve. Loosening the
`dimension` shape without a type check would allow a dimension token to alias a
color and fail later inside Style Dictionary with a much worse message. The
validator therefore records every token's `$type` and rejects a dimension alias
that points at a non-dimension token (`design/validate-tokens.mjs`).

## Alternatives rejected

- **Keep the derivation in `HeaderMetrics`.** The status quo of #824; rejected
  because it is exactly the complaint in the issue (no designer surface, the
  clamp hides type-scale changes).
- **Put all four values as literals in the token group.** Duplicates the type
  and spacing scale; a typography change would then need two edits, and the
  copies would drift silently. Aliases are the reason to have a component group
  at all.
- **Add arithmetic to the token pipeline** (a `$extensions` formula or a
  computed `height: max(...)`). No DTCG-conformant way to express it, and a
  formula engine in the build is far more machinery than one 48 dp constant
  justifies.
- **A `ThemeExtension` for the header metrics instead of a token.** Moves Dart
  constants around without giving a designer a surface — the issue asks for the
  value in the *token source*.

## Impact

- `design/tokens/component.json` (new), `design/validate-tokens.mjs`
  (dimension aliases + type check),
  `frontend-flutter/lib/design/gen/design_tokens.g.dart` (regenerated, 70 → 74
  tokens).
- `frontend-flutter/lib/design/header_metrics.dart` (reads the tokens;
  `contentHeight` removed), `lib/design/components/breakdown_app_bar.dart`
  (doc comment only), `theme.dart` unchanged (`appBarTheme.toolbarHeight` still
  reads `HeaderMetrics.toolbarHeight`).
- `test/design/header_metrics_test.dart` — the alias round-trip, the token
  reads and the floor invariant replace the derivation assertions.
- Docs: `design/tokens/README.md`, `.pi/skills/design-tokens-dtcg/SKILL.md`,
  `docs/design/screens/README.md` (header rule).
- No golden re-baseline: the rendered values are identical.

## Follow-ups (not this change)

- Archive `824-pushed-header-height-and-inset`: its "a `component.appBar.*`
  token group is a follow-up" note is satisfied here, so the pending change can
  be archived once this one lands.
