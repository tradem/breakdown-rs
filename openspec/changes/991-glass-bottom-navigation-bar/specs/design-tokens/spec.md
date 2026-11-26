<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# design-tokens Delta — issue #991

## ADDED Requirements

### Requirement: A `number` token type expresses ratios and opacities

The token source SHALL support the DTCG `number` type, a leaf token whose
`$value` is a finite JSON number, for design decisions that are ratios rather
than lengths or colors (today: the glass bottom bar's tint opacity and its
plane lift). The conformance validator SHALL reject a non-numeric, non-finite or
alias-shaped `$value` of that type, SHALL resolve the value into the generated
Dart artifact as a `double`, and SHALL leave the value's range to the token's
`$description` (the DTCG `number` type does not constrain it).

#### Scenario: An alpha token reaches the Flutter artifact

- **WHEN** `component.navigationBar.tintAlpha` is a `number` token with the
  value `0.72` and the build script runs.
- **THEN** the regenerated artifact carries
  `static const double componentNavigationBarTintAlpha = 0.72;` and no Dart call
  site re-derives an alpha literal.

#### Scenario: A malformed number token fails the build

- **WHEN** a `number` token's `$value` is a string, a non-finite number, or an
  `{alias.reference}`.
- **THEN** `design/validate-tokens.mjs` fails the build with a message naming
  the token, before Style Dictionary runs.

### Requirement: A component token group for the glass bottom bar

The token source SHALL provide a `component.navigationBar` group for the compact
shell's translucent bottom bar, satisfying the same three component-token rules
as `component.appBar` (state only a decision no primitive can state, alias what
a primitive already owns, one hand-written consumer). The group SHALL carry the
bar's height, the tint's opacity, the plane's lift and the backdrop blur radius;
the tint **color** SHALL NOT be a token, because it is derived per brightness
from the scheme's `surface` and `surfaceTint` roles and a fixed color would read
as a hole in dark mode.

#### Scenario: A designer retunes the glass effect

- **WHEN** `component.navigationBar.tintAlpha` or `blurSigma` changes in
  `design/tokens/component.json` and the build script runs.
- **THEN** the bar's tint opacity or blur radius changes without a Dart edit,
  the regenerated artifact is committed with the JSON change, and the contrast
  test fails if the new opacity breaks the 4.5:1 label budget.

#### Scenario: The bar height and the content inset cannot drift

- **WHEN** `component.navigationBar.height` changes.
- **THEN** the theme writes the new value into `NavigationBarThemeData.height`
  AND `Scaffold(extendBody: true)` derives the body's bottom inset from the
  laid-out bar height, so the last list row keeps ending at the bar's top edge.
