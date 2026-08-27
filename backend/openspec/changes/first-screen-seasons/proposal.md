<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Proposal: First Screen — SeasonsScreen (Reference Pattern)

## Why
The foundation specs (`flutter-state-management`, `flutter-openapi-client`,
`flutter-offline-scope`) describe the conventions abstractly. This change
lands the first real screen — `SeasonsScreen` — as the concrete reference
pattern every subsequent screen-by-screen implementation follows.

## What changes
- `features/seasons/seasons_controller.dart` — `@riverpod`
  `SeasonsController` returning `AsyncValue<List<SeasonDto>>`.
- `SeasonsRepository` wrapping the generated client + Drift cache.
- `SeasonsScreen` `ConsumerWidget` (no `StatefulWidget` / `setState`).
- Optimistic create + bounded-retry refetch on `POST /v1/seasons`.
- Tests: unit (mapper, repository Ok/Err branches), widget + golden,
  integration_test smoke.
- Documented as the reference pattern in `AGENTS.md` §9 (already in
  `design.md`).

## Dependencies
- **Depends on:** `scaffold-flutter-project`, `wire-openapi-dart-client`,
  `wire-flutter-oidc-auth`, and `add-drift-read-cache` — required, not
  optional: `flutter-offline-scope` mandates Drift as the read-projection
  cache and the single source for screen state, so a cache-less
  implementation of this screen would violate that requirement.

## Non-goals
- No other screens (this is the reference; subsequent screens open their
  own changes following this pattern).
- No design-system exhaustiveness (only the components this screen needs).

## Design Decisions (resolved during spec-hardening, issue #272)
The PR #269 review asked where the optimistic row lives and for the
failure-path tests. Resolved here; encoded as requirements in
`specs/flutter-first-screen/spec.md`.

### D1. Optimistic insert timing (after command acknowledgement)

- The optimistic insert is performed **only after `POST /v1/seasons` returns
  2xx** with the server `IdVersionResponse` (carrying the server-assigned
  `id` and `version`). The full `SeasonDto` arrives later via the projection
  refetch; the overlay is keyed by the `IdVersionResponse.id`. We do NOT insert
  a locally-fabricated row before the command acks. The endpoint returns the
  created `id`, so the overlay has a real key to reconcile on.
- "Optimistic" here means: the UI reflects the server-acknowledged entity
  immediately, in parallel with — and ahead of — the slower projection
  refetch, so the user sees their new season without waiting for projector
  lag.

### D2. Where the optimistic row lives — controller-state overlay (NOT Drift)

- Decision: the optimistic row lives in **controller state** as an
  in-memory overlay, **not** in Drift. Rationale: the cache invariant
  (foundation `flutter-offline-scope`) states Drift must not contain
  unprojected state; a pre-projection row in Drift would be exactly that.
  Drift holds only projected rows; the optimistic entity (server-acknowledged
  but not yet projection-confirmed) lives in the controller's `AsyncValue`
  overlay.
- How the screen still "reads Drift only" for authoritative data: the
  screen's effective list = `Drift-projected rows (read source)` ∪
  `controller optimistic overlay`. The provider composes both — it reads the
  projected list from Drift (via the repository `readCached`) and merges the
  optimistic overlay entries keyed by `id` (the real `id` from the POST
  response). Because the overlay entry already has the real `id`, refetch
  reconciliation is a clean replace-by-id: when the bounded-retry refetch
  returns the projected row with the same `id`, the overlay entry is dropped
  (the projected row now carries the same data, authoritatively). The
  invariant "screen reads Drift only" holds for *authoritative/projection*
  data; the optimistic overlay is explicitly ephemeral controller state
  layered on top, never persisted to Drift.
- This also resolves the `add-drift-read-cache` D4 interaction: the overlay
  is separate from the stale-cache path; an error during refetch keeps both
  the projected Drift rows and the optimistic overlay (with a reconciling
  spinner), and bounded-retry exhaustion marks the overlay `stale` but keeps
  it so the user still sees "your season was created; projection is catching
  up."
- **Controller state shape**: the controller exposes `SeasonsScreenState {
  AsyncValue<List<SeasonDto>> projected; List<OverlayEntry> overlays; }`. The
  optimistic overlay is a separate `overlays` list — `AsyncValue` holds only
  the projected rows, never `OverlayEntry` metadata. `OverlayEntry { String id;
  String? name; OverlayStatus status; String? warning; }` carries the
  server-assigned `id` (from `IdVersionResponse`) plus the submitted display
  fields (e.g. `name` from the CreateSeason form) so the row renders immediately;
  status/warning track reconciliation. The full `SeasonDto` lives in `projected`
  once the refetch returns and replaces this overlay on reconciliation.
  `OverlayStatus ∈ { acknowledged, reconciling, stale }`: `acknowledged` shows
  immediately after the 2xx;
  `reconciling` while the bounded-retry refetch is in flight; `stale` when the
  refetch exhausts its retries (overlay retained with a non-fatal `warning` +
  pull-to-refresh). A successful reconciliation drops the entry as the projected
  Drift row takes over — it is never marked `stale` on success.

### D3. Failure-path tests (added to Tasks 5.x and encoded as scenarios)
- **POST network failure / 5xx** → repository returns
  `Err(ProblemError)`; controller does NOT insert any overlay; Drift is
  untouched; widget surfaces `AsyncError` keyed on `code`; no phantom row.
- **409 conflict** (command-side, returned before any 2xx) →
  `Err(ProblemError(code: "seasons.conflict"))`; because the overlay is only
  added *after* a 2xx, no overlay was ever created, so there is nothing to
  revert; error keyed on `code`.
- **Bounded-retry exhaustion** → POST succeeded (entity acked, overlay
  shown), but the projection refetch retries N times and times out; provider
  retains the overlay with `reconciling = false, stale = true`, emits a
  non-fatal warning state so the user can pull-to-refresh; Drift still does
  not contain the unprojected row.
