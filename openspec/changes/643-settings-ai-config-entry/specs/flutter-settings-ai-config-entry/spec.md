<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# flutter-settings-ai-config-entry

## ADDED Requirements

### Requirement: Central AI-Configuration Entry in Settings
The Settings screen SHALL offer an AI-configuration entry in the
**general** section (every flavor) that pushes the existing
`AiConfigScreen`. The entry SHALL be visible only while the client-side
membership gate resolves to an active costume-dept role via the sticky
active-block scope (`currentMembershipProvider(scope.seasonId)` →
`hasActiveCostumeRoleInSeason`); an unresolved scope, a pending fetch,
or a membership error SHALL render no entry (a pending fetch hides,
never denies — D3). The server stays authoritative: denial on the
AI-config handlers renders the existing localized 403 narrative
(documented D4 exception on `AiConfigScreen`), never a silent failure.

#### Scenario: Entry visible for an active costume-dept member
- **WHEN** the sticky active-block scope is set and the season-scoped
  membership resolves with `hasActiveCostumeRoleInSeason == true`
- **THEN** the Settings screen renders the AI-configuration tile in the
  general section

#### Scenario: Entry hidden without an active-block scope
- **WHEN** no active-block scope is set (fresh session, seasons-level
  browsing only)
- **THEN** the Settings screen renders no AI-configuration tile

#### Scenario: Entry hidden while the membership is pending or erroring
- **WHEN** the season-scoped membership fetch is in flight or has failed
- **THEN** the Settings screen renders no AI-configuration tile (never a
  denial narrative, D3)

#### Scenario: Entry hidden on a resolved denial
- **WHEN** the season-scoped membership resolves with
  `hasActiveCostumeRoleInSeason == false`
- **THEN** the Settings screen renders no AI-configuration tile

#### Scenario: Entry pushes the existing AI-configuration screen
- **WHEN** the user taps the visible AI-configuration tile
- **THEN** `AiConfigScreen` is pushed (the existing screen and its
  controller are reused — no new screen, no new API surface)

#### Scenario: Denial degrades to the localized 403 narrative
- **WHEN** a member the tile admitted (e.g. a `wardrobe_supervisor`,
  covered by the wider season predicate but not by the backend's
  `has_active_credential_role`) opens `AiConfigScreen` and the server
  denies with 403
- **THEN** the existing localized 403 narrative renders and no request
  is retried client-side (server authoritative, D4 exception)
