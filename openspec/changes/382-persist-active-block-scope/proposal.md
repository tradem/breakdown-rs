<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Proposal: 382-persist-active-block-scope — persist `ActiveBlock` per season

## Summary

Follow-up to #378 (PR #381): the `ActiveBlock` sticky scope is in-memory
only and resets to unset on every cold start, so season-direct entries
(`CostumesScreen`, `CharactersScreen`) on multi-block seasons re-show the
remembered picker after every restart.

Fix strategy (user-confirmed): persist the scope **per season**
(`Map<seasonId, blockId>` as JSON in `flutter_secure_storage`) and consult
it in `blockScopeResolution` before falling back to the existing
re-resolution path. No backend change.

## Context and constraints

- Drift check: `ActiveBlock` (`lib/auth/active_block.dart`) is a sync
  `@Riverpod(keepAlive: true)` notifier with `set`/`clear`; sign-out resets
  via `ref.invalidate(activeBlockProvider)` in `SessionReset`
  (`lib/features/auth/sign_out.dart`). `blockScopeResolution`
  (`lib/features/blocks/active_block_gate.dart`) is sync and returns
  `AsyncValue` — it cannot `await` secure storage inline.
- `flutter_secure_storage` is already a direct dependency and the
  established persistence seam (`SecureTokenStore`,
  `ApiBaseOverrideStore`); block ids are not secrets, but secure storage
  keeps the scope identity-scoped and cleared with the session (no
  cross-identity leak, no plaintext-preference spread). No new dependency.
- CQRS boundary holds: the persisted value is only ever written from the
  DTO the user acted on (via the existing `set` call sites) and only
  *validated* against the `blocksListFetchProvider` projection — never a
  second lookup to fill a command.

## Design

1. **`ActiveBlockStore`** (`lib/auth/active_block_store.dart`, new):
   `Result`-typed, never throws — `readScopes()` (`Map<seasonId, blockId>`,
   corrupt/empty → `{}` with best-effort self-heal), `saveScope()`,
   `removeScope(seasonId)` (stale eviction), `clear()` (sign-out/switch).
   Key `breakdown.active_block_scopes`. Injectable `FlutterSecureStorage`
   for the fake-platform tests. Manual (non-codegen) providers in the same
   file: `activeBlockStoreProvider` + keepAlive
   `activeBlockPersistedProvider` (`Future<Map>` — the single async seam
   the gate watches).
2. **Write-through** (`ActiveBlock.set`/`clear`): in-memory state updates
   synchronously (call sites unchanged); persistence follows fire-and-forget
   (`unawaited` + explicit `Result` fold, no `discard_result` trip) and
   invalidates the persisted provider once the write settles (avoids the
   invalidate-before-write race; the sticky hit short-circuits the gate
   meanwhile, so the race is unobservable).
3. **Lazy restore in `blockScopeResolution`**: sticky hit → ready (unchanged).
   Otherwise, when the blocks fetch yields rows, consult the persisted map:
   - persisted `loading` → `loading` (withhold content — no picker flash);
   - persisted entry for the season **and** still in `rows` → deferred
     `set` (same microtask pattern as the single-block path) + `loading`
     (next frame ready — zero taps for returning users);
   - stale entry (block gone) → schedule `removeScope` eviction and fall
     through to the existing single-auto-pick / picker / empty path;
   - persisted `Err` / no entry → existing path unchanged (never a hard
     failure — persistence problems never break resolution).
4. **Sign-out / backend switch** (`SessionReset`): `await` the store `clear`
   (sign-out: after the Drift clear; switch: before `set(base)` so no
   request ever pairs the new base with the old backend's block id), then
   invalidate `activeBlockProvider` + persisted provider. A clear failure on
   sign-out fails the session closed (same posture as the cache-clear
   failure — stale identity state must never survive); on switch it returns
   `Err` like the cache failure.

## Non-goals

- No backend change; no `openapi.yaml` change (header stays
  middleware-attached via the interceptor).
- No eager boot restore and no session-gated preload: the lazy gate lookup
  only runs inside authenticated screens, and sign-out wipes the map, so
  restoration is inherently session-scoped without extra wiring.
- No new dependency (`shared_preferences` deliberately not introduced).

## Acceptance criteria

- [ ] Scope persisted per season and restored at boot when the session is
      still valid (returning user on a multi-block season: zero taps).
- [ ] Stale scope (block deleted on the backend) degrades to the existing
      re-resolution path, never a hard failure (stale entry evicted).
- [ ] Sign-out clears the persisted scope (no cross-identity leak).
- [ ] `dart format`, `flutter analyze`, `flutter test` clean; no hand-edits
      to `vendor/breakdown_api/` or `*.g.dart`.
