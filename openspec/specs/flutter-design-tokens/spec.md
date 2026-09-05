# flutter-design-tokens Specification

## Purpose
TBD - created by archiving change flutter-login-and-app-shell. Update Purpose after archive.
## Requirements
### Requirement: Light and Dark M3 Themes from Tokens
`lib/design/theme.dart` SHALL define `AppThemes.light()` and
`AppThemes.dark()` via `ColorScheme.fromSeed` over a single seed-color
token, and `App` SHALL pass both (`theme`, `darkTheme`) with
`themeMode: ThemeMode.system`. Widgets introduced by this change SHALL
use scheme roles and `lib/design` spacing tokens only — no hardcoded
`Color`, style, or spacing literals in widget code.

#### Scenario: System switches to dark mode
- **WHEN** the device brightness setting changes to dark while the app
  is in the foreground.
- **THEN** the active screens and dialogs re-render in the dark scheme
  without an app restart.

#### Scenario: Hardcoded color in a new widget
- **WHEN** a review/CI check finds a `Color(...)` literal in a widget
  introduced by this change.
- **THEN** it is rejected; the color must come from `Theme.of(context)`
  color-scheme roles or `lib/design` tokens.

### Requirement: Contrast and Accessibility Baseline
Both themes SHALL use the default Material 3 system-contrast scheme;
every text-on-surface pair the new surfaces render SHALL meet 4.5:1
contrast. Interactive targets SHALL have a minimum touch size of 48×48
logical px, and dialogs SHALL remain usable (no overflow) at
`textScaler` up to 1.3.

#### Scenario: Dark-theme golden comparison
- **WHEN** golden tests render the login gate and both dialogs in light
  and dark variants.
- **THEN** all four goldens match; failures are treated as rendering
  regressions.

#### Scenario: Dialog at large text scale
- **WHEN** a dialog renders under `textScaler: 1.3`.
- **THEN** no overflow errors are emitted (widget-test assertion).
