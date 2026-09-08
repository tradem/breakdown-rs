<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Proposal: 378-active-block-header — client sends `X-Active-Block`

## Summary

Close the client/backend contract gap from issue #378: the backend
`authorize_middleware` (`requirement_for`) classifies episodes, scenes,
shooting days, scene shoots, costumes and characters as `BlockMember` and
rejects a missing `X-Active-Block` header with 400 — but the Flutter client
never sends that header, so every screen below blocks 400s (verified:
day-board fetch 400s on the 4.1 emulator smoke).

Fix strategy **A** (user-confirmed): a client-side active-block concept —
sticky scope tracking + a Dio interceptor that attaches the header to every
API request. No backend change; fully compliant with the action-scoped
authz design (Decision D2: client presents the scope, server enforces
membership and stays authoritative).

## Context and constraints

- Drift check: no active-block state and no header wiring exist anywhere in
  `frontend-flutter/` (`grep -ri active-block` empty outside this change).
- The generated `breakdown_api` client exposes **no** header parameter for
  block-scoped routes (`X-Active-Block` is middleware-enforced and absent
  from `backend/openapi.yaml`), so the header can only be attached via a
  Dio interceptor — per-repository/per-call header passing is impossible
  without hand-editing generated code (forbidden: rebuild-only rule).
- Sending the header on `Authenticated`-only routes (seasons, `/blocks`,
  photos, reports) is harmless: the middleware returns before parsing it.
  No per-route branching is needed.
- Navigation gap: `CostumesScreen`/`CharactersScreen` are entered from
  season level with only a `SeasonView` (no block in context), so deriving
  the scope "from the DTO at hand" does not cover all screens — sticky
  tracking with resolution is required.
- Transparency requirement (user-confirmed): zero extra taps in
  hierarchical flows; at most one remembered tap when entering
  season-direct screens with an ambiguous (multi-block, no sticky) scope.

## Design

1. **`ActiveBlock` scope state** (`lib/auth/active_block.dart`,
   `@Riverpod(keepAlive: true)`): state is `ActiveScope?`
   (`{seasonId, blockId}`) with `set({seasonId, blockId})` and `clear()`.
   Keep-alive so the scope survives screen pops; cleared on sign-out.
2. **`ActiveBlockInterceptor`** (`lib/src/network/active_block_interceptor.dart`):
   Dio interceptor taking the current `String? activeBlockId`; sets
   `X-Active-Block` when non-null, sends nothing when null (seasons/blocks/
   auth flows keep working headerless). Never throws. Same test harness
   shape as `AuthTokenInterceptor`.
3. **Wiring**: `buildPinnedDio(..., {String? activeBlockId})` gains the
   interceptor; `apiDioProvider` watches `activeBlockProvider` and passes
   `state?.blockId` (Dio rebuilds on scope change — same pattern as the
   runtime base-URL rebuild). Bootstrap `buildApiClient` passes null.
4. **Set point (implicit, zero taps)**: the `BlocksScreen` block tap sets
   the scope from the `BlockView` (`seasonId` + `id`) synchronously before
   pushing `EpisodesScreen` — CQRS-boundary compliant (from the DTO acted
   on, never a second projection lookup). Deliberately the *only*
   production set point: a user gesture runs outside any build (provider
   writes during builds throw), and the tap is the single funnel into
   block context. Deeper screens inherit the sticky scope; they never
   touch it. Test harnesses pumping block-child screens directly set the
   scope explicitly.
5. **`ActiveBlockGate` resolution (season-direct screens)**: shared helper
   used by `CostumesScreen`/`CharactersScreen`. If the sticky scope's
   `seasonId` matches → reuse silently. Else resolve via the existing
   `blocksListFetchProvider(seasonId)` seam: exactly one block → auto-set
   silently; multiple → one-tap remembered picker dialog; zero → inline
   hint (no block exists yet — headerless requests would 400). Loading and
   error states reuse the screens' existing fetch-error/retry surfaces.
6. **Sign-out**: scope cleared alongside session teardown so a new session
   never inherits the previous user's block scope.

## Non-goals

- No backend change (`authorization.rs`, `openapi.yaml` untouched).
- No per-request block override API on repositories; no `Options(headers:)`
  at call sites — the interceptor is the single attachment point.
- No offline queueing of the scope; in-memory only (no persistence).
- No client-side membership denial on scope grounds — the server 403
  surfaces through the existing keyed-on-`code` error path.

## Acceptance criteria

- [ ] Every Dio API request carries `X-Active-Block` whenever a scope is
      set, and omits it when unset (unit-tested at the interceptor level).
- [ ] Navigating Seasons → Blocks → Episodes sets the scope implicitly;
      popping back above blocks does not clear it (sticky); sign-out clears.
- [ ] Costumes/Characters entered directly: single-block season works with
      zero taps; multi-block season shows the remembered picker once.
- [ ] `dart format`, `flutter analyze`, `flutter test` clean; no
      hand-edits to `vendor/breakdown_api/` or `*.g.dart` (regenerated).
