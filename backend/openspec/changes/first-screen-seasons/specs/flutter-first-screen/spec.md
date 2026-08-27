<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## ADDED Requirements

### Requirement: SeasonsScreen as the Reference Screen Pattern

`SeasonsScreen` SHALL be a `ConsumerWidget` (no `StatefulWidget` /
`setState`) backed by a `@riverpod` `SeasonsController` returning
`AsyncValue<List<SeasonDto>>`, with optimistic create and bounded-retry
refetch on `POST /v1/seasons`. It is the reference pattern for all subsequent
screens.

#### Scenario: Creating a season optimistically (after acknowledgement)

- **WHEN** the user submits the Create Season form.
- **THEN** the controller dispatches `POST /v1/seasons`, which returns
  `IdVersionResponse { id, version }`; only after that 2xx does it add an
  optimistic overlay entry keyed by the returned `id` to the controller's
  `overlays` list (part of `SeasonsScreenState`, separate from the
  `AsyncValue<List<SeasonDto>>` `projected` rows) and reconcile via a
  bounded-retry refetch of the seasons projection. The full `SeasonDto` arrives
  with the refetch; the overlay is controller state, not a Drift write; the
  screen's authoritative rows still come from Drift (merged with the overlay by
  `id`).

#### Scenario: A 409 conflict is returned

- **WHEN** `POST /v1/seasons` returns `409` with `code: seasons.conflict`
  **before any 2xx** (the conflict is detected by a command-side check that
  runs ahead of the 201).
- **THEN** the repository returns `Err(ProblemError(code:
  "seasons.conflict"))`, the controller surfaces it as `AsyncError`, and the
  widget shows the error keyed on the stable `code` (never on `detail`).
  Because the optimistic overlay is only added *after* a 2xx, no overlay
  exists to revert — there is nothing to roll back.

### Requirement: Optimistic Row Lives in Controller State, Never in Drift

The optimistic create SHALL add an overlay entry to the controller's
`SeasonsScreenState.overlays` (a `List<OverlayEntry>`), keyed by the server
`id` from `IdVersionResponse`; the projected rows live separately in
`SeasonsScreenState.projected` (`AsyncValue<List<SeasonDto>>`). The overlay
SHALL NOT be written to Drift until the projection refetch confirms it (Drift
must not contain unprojected state). The screen reads `projected` and merges
`overlays` by `id`; reconciliation drops the overlay entry when the refetch
returns the same `id`.

`OverlayEntry { String id; OverlayStatus status; String? warning; }` carries
only the acked `id` + status/warning; the full `SeasonDto` lives in `projected`
after the refetch. `OverlayStatus ∈ { acknowledged, reconciling, stale }`.
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
