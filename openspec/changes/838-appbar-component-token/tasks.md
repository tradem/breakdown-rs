<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #838

## 1. Token source

- [x] 1.1 `design/tokens/component.json` — `component.appBar.{height,
      titleFontSize, titleLineHeight, verticalPadding}`; `height` is the 48 dp
      decision, the other three alias `typography.fontSize.titleLarge`,
      `typography.lineHeight.titleLarge` and `size.space.8`.
- [x] 1.2 `design/validate-tokens.mjs` — accept a `{alias.reference}` as a
      `dimension` `$value` and type-check it (a dimension token must alias
      another dimension token); document the rule in the header comment.
- [x] 1.3 `bash scripts/build-tokens.sh` — regenerated
      `frontend-flutter/lib/design/gen/design_tokens.g.dart` (70 → 74 tokens)
      committed with the JSON change.

## 2. Flutter consumer

- [x] 2.1 `lib/design/header_metrics.dart` — `fontSize`, `lineHeight`,
      `verticalPadding` and `toolbarHeight` read the generated component
      tokens; `contentHeight` (the arithmetic) removed; the derivation lives in
      the token `$description` and in the test, not in code.
- [x] 2.2 `lib/design/components/breakdown_app_bar.dart` — doc comment names
      the token (no behavior change).

## 3. Tests

- [x] 3.1 `test/design/header_metrics_test.dart` — alias round-trip (component
      tokens equal the type/spacing primitives), the token reads, and the
      invariant `height ≥ max(lineHeight + 2 × verticalPadding, 48 dp)`.
- [x] 3.2 `flutter test test/design/` green — the app-bar role tests from #824
      still pass unchanged, which is the no-visual-change proof.

## 4. Docs

- [x] 4.1 `design/tokens/README.md` — "Component tokens" section: the relaxed
      non-goal and the three rules a future group must satisfy; dimension
      aliases named in the format rules.
- [x] 4.2 `.pi/skills/design-tokens-dtcg/SKILL.md` — rule 6 rewritten from
      "non-goal" to the relaxation contract; `component.json` in the
      read-first list; dimension aliases in the format rules.
- [x] 4.3 `docs/design/screens/README.md` — the header rule names
      `component.appBar.height`.
- [x] 4.4 This change records the relaxation (proposal + delta spec).

## 5. Verification

- [x] 5.1 `dart format --set-exit-if-changed .` clean.
- [x] 5.2 `flutter analyze` clean.
- [x] 5.3 `flutter test` — full suite green, no golden re-baseline (the
      rendered values are unchanged).
- [x] 5.4 Drift gate: `DESIGN_TOKENS_OUT_DIR=/tmp/... bash
      scripts/build-tokens.sh` + `diff -r` → no difference.
- [x] 5.5 `openspec validate 838-appbar-component-token --strict` passes.

## Follow-ups (not this change)

- [ ] Archive `824-pushed-header-height-and-inset` — this change fulfils its
      `component.appBar.*` follow-up.
