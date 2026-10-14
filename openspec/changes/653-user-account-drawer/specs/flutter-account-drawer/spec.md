<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# flutter-account-drawer Delta

## ADDED Requirements

### Requirement: User Account Drawer

The shell SHALL offer a user account drawer: a Material 3
`NavigationDrawer` presented as a side overlay (with scrim) when the top
bar's user icon is tapped — Spotify-style, opening from the side, never as
a bottom sheet and never sliding up from the bottom. The drawer SHALL be
hosted by the shell's `Scaffold` (root navigator), so its scrim covers the
entire shell including the top bar. Tapping the scrim or swiping the
drawer SHALL close it.

The drawer is reachable only in the authenticated state (it lives inside
the shell, below `AuthGate`); the routes it pushes are the existing
authenticated surfaces. // AUTHZ-GATE: the drawer dispatches no command
itself beyond the session reset; the surfaces it opens gate inside their
own controllers.

#### Scenario: Drawer opens from the user icon

- **WHEN** the user taps the profile icon in the shell top bar.
- **THEN** the account drawer slides in as a side overlay with a scrim
  above the current content — not a bottom sheet, and no bottom-sheet
  variant exists in the layout.

#### Scenario: Drawer dismisses

- **WHEN** the user taps the scrim or swipes the drawer toward the edge.
- **THEN** the drawer closes and the shell content beneath is interactive
  again.

### Requirement: Account Drawer Entries

The drawer SHALL offer, in order: the signed-in identity (account
identifier with the localized signed-in state), *Über die App* (→ pushes
the full-screen `AppInfoScreen` onto the active destination's navigator —
never a dialog), *Einstellungen* (→ pushes the full-screen
`SettingsScreen` onto the active destination's navigator), and *Abmelden*
(→ runs the OIDC/session-reset sign-out flow and returns to the
unauthenticated gate). Copy SHALL be the localized ARB catalog (German
template plus English); no hardcoded strings.

#### Scenario: About opens a full-screen route

- **WHEN** the user taps *Über die App* in the drawer.
- **THEN** the drawer closes and the full-screen `AppInfoScreen` pushes
  onto the active destination's navigator — the pushed route is a screen
  route (`MaterialPageRoute`), not a dialog.

#### Scenario: Logout returns to the unauthenticated state

- **WHEN** the user taps *Abmelden* in the drawer.
- **THEN** the session reset runs and the app recomposes at the
  unauthenticated gate (login screen), with the cache cleared exactly
  once; a failed reset surfaces the error copy at the gate (fail-closed).
