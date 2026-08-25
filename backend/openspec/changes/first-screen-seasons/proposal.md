<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

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
