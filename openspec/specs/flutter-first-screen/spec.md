# flutter-first-screen Specification

## Purpose
TBD - created by archiving change first-screen-seasons. Update Purpose after archive.
## Requirements
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


### Requirement: Optimistic Row Lives in Controller State, Never in Drift

The optimistic create SHALL add an overlay entry to the controller's
`SeasonsScreenState.overlays` (a `List<OverlayEntry>`), keyed by the server
`id` from `IdVersionResponse`; the projected rows live separately in
`SeasonsScreenState.projected` (`AsyncValue<List<SeasonDto>>`). The overlay
SHALL NOT be written to Drift until the projection refetch confirms it (Drift
must not contain unprojected state). The screen reads `projected` and merges
`overlays` by `id`; reconciliation drops the overlay entry when the refetch
returns the same `id`.

`OverlayEntry { String id; String? name; OverlayStatus status; String?
warning; }` carries the acked `id` plus the submitted display fields
(e.g. `name` from the CreateSeason form) so the row can render immediately;
`status`/`warning` track reconciliation. The full `SeasonDto` arrives via the
refetch and lives in `projected`; on reconciliation the projected row replaces
this overlay entry. `OverlayStatus ∈ { acknowledged, reconciling, stale }`.
- `acknowledged`: POST 2xx returned; overlay shown immediately.
- `reconciling`: bounded-retry refetch in flight; overlay still shown.
- `stale`: refetch exhausted its retries; overlay retained with a non-fatal
  `warning` and pull-to-refresh offered.
Fresh successful reconciliation transitions the entry out (the projected Drift
row now carries the same `id`); it is never marked `stale` on success.

#### Scenario: Drift contains no unprojected row during reconciliation

- **WHEN** the POST has acked and the bounded-retry refetch is still pending.
- **THEN** the optimistic entry exists only in controller overlay state, the
  Drift table holds only previously-projected rows, and a cold Drift read
  would not yet show the new season.

### Requirement: Failure Paths Roll Back or Retain the Optimistic Overlay

A POST network/5xx failure or a `409` conflict SHALL NOT insert any overlay
and SHALL leave Drift untouched, surfacing `AsyncError` keyed on `code`.
Bounded-retry exhaustion SHALL retain the overlay marked `stale` (not in
Drift), emit a non-fatal warning, and offer pull-to-refresh.

#### Scenario: POST fails before acknowledgement

- **WHEN** `POST /v1/seasons` fails with a network/5xx error (no 2xx).
- **THEN** the controller inserts no overlay, Drift is unchanged, and the
  widget shows `AsyncError` keyed on `code` with no phantom row.

#### Scenario: Bounded-retry refetch times out

- **WHEN** the POST acked (overlay shown) but the projection refetch exhausts
  its bounded retries.
- **THEN** the provider retains the overlay with `stale = true`, surfaces a
  non-fatal warning state (not a hard error that discards the row), and the
  widget offers pull-to-refresh; Drift still contains no unprojected row.

