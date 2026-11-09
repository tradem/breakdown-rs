<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# design-tokens Delta — issue #838

## ADDED Requirements

### Requirement: Component token group for a single-consumer decision

The token source SHALL provide a component token group
(`design/tokens/component.json`) for a component whose value no primitive
token can state. The relaxation of the foundation's component-token non-goal
SHALL be recorded in an OpenSpec change, and a component group SHALL satisfy
three rules:

1. It states only the decision the primitives cannot express (a clamp or floor,
   e.g. the header's 48 dp interactive-dimension minimum); every value a
   primitive already owns SHALL be an `{alias.reference}` to that primitive.
2. Exactly one hand-written consumer reads the emitted value from
   `design_tokens.g.dart`; no call site re-derives it.
3. It contains no Flutter semantics (no scheme roles, no widget structure);
   those stay hand-authored.

#### Scenario: A designer retunes the header height
- **WHEN** the value of `component.appBar.height` changes in
  `design/tokens/component.json` and the build script runs.
- **THEN** `HeaderMetrics.toolbarHeight` (and with it every pushed screen's
  `appBarTheme.toolbarHeight`) reports the new value without a Dart change, and
  the regenerated artifact is committed with the JSON edit.

#### Scenario: A type-scale token changes
- **WHEN** `typography.lineHeight.titleLarge` or `size.space.8` changes.
- **THEN** the aliased component tokens change with it (no second edit in
  `component.json`), and a change that would make the header content taller
  than `component.appBar.height` fails
  `test/design/header_metrics_test.dart` instead of being silently absorbed.

#### Scenario: A component token is proposed without a justification
- **WHEN** a component group (or a member of one) is added that only repeats a
  primitive value, or that has no hand-written consumer, or that is not
  recorded in an OpenSpec change.
- **THEN** it is rejected at review; the value belongs in the primitive token
  it duplicates.

### Requirement: Dimension aliases are type-checked by the token validator

A `dimension` token's `$value` SHALL accept either the structured
`{value, unit: "px"}` object or an `{alias.reference}` string, and the
conformance validator SHALL reject a dimension alias whose target resolves to a
non-dimension token. An alias that does not resolve at all SHALL remain a
violation.

#### Scenario: A dimension token aliases a color
- **WHEN** a `dimension` token's `$value` is `{color.brand.seed}`.
- **THEN** `design/validate-tokens.mjs` fails the build with a message naming
  the token, the alias and the mismatched target type.

#### Scenario: A component token aliases a typography primitive
- **WHEN** `component.appBar.titleLineHeight` is
  `{typography.lineHeight.titleLarge}`.
- **THEN** the validator passes and the emitted Dart constant carries the
  resolved 28 dp value.
