<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## MODIFIED Requirements

### Requirement: SeasonsScreen as the Reference Screen Pattern

`SeasonsScreen` SHALL be a `ConsumerWidget` (no `StatefulWidget` /
`setState`) backed by a `@riverpod` `SeasonsController` returning
`SeasonsScreenState` (whose `projected` field is the
`AsyncValue<List<SeasonDto>>`), with optimistic create and
bounded-retry refetch on `POST /v1/seasons`. It is the reference
pattern for all subsequent screens. As the Season tab content, its
presentation SHALL follow the seasons-home capability: rows render
as Material 3 cards with cached metadata and stale indication, the
create action renders as an extended FAB ("Season erstellen"), and
the empty and loading states follow the guided-empty-state and
skeleton requirements.

#### Scenario: Creating a season optimistically (after acknowledgement)

- **WHEN** the user submits the Create Season form.
- **THEN** the controller dispatches `POST /v1/seasons`, which returns
  `IdVersionResponse { id, version }`; only after that 2xx does it add an
  optimistic overlay entry keyed by the returned `id` to
  `SeasonsScreenState.overlays` and reconcile via a bounded-retry refetch of
  the seasons projection. The full `SeasonDto` arrives with the refetch; the overlay
  renders as a card preserving the existing overlay keys.

#### Scenario: Card tap navigates to the season's planning context

- **WHEN** an authenticated user taps a projected season card.
- **THEN** the app opens the season's planning view (Season→Blocks)
  with the `SeasonView` as navigation context (shell/Planen-tab
  contract).

#### Scenario: Command failure surfaces keyed copy

- **WHEN** the create returns conflict/validation or transport
  errors.
- **THEN** the error banner renders localized copy keyed on the
  problem `code` (unchanged behavior), and no overlay exists.
