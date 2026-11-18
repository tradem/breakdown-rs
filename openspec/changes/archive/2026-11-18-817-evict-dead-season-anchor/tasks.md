<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks: 817-evict-dead-season-anchor

## 1. Store seam

- [x] 1.1 `ShellStateDao.deleteIfValue({key, value})` — one conditional SQL
      delete (`WHERE key = ? AND value = ?`), `Left(shell.state_delete_failed)`
      on failure; no read-modify-write window.
- [x] 1.2 `activeSeasonStorageKeyProvider` — the single source for the
      session-scoped key, watched by both the read
      (`activeSeasonPersistedProvider`) and the repair.

## 2. Proof of absence

- [x] 2.1 `SeasonsView.isLoaded` (additive, default `false`, fail-closed): the
      controller marks a successful snapshot `true`; the retained-row branches
      state `false` explicitly.
- [x] 2.2 `flutter-offline-scope` delta spec records why the row list alone
      cannot authorize a deletion.

## 3. Repair

- [x] 3.1 `activeScopeRepairProvider` (`lib/features/shell/active_season_store.dart`):
      sync, keep-alive, side effect on watch — evicts the anchor
      (compare-and-remove) and every block scope of a vanished season
      (`removeScopeIfMatch`) once the view is loaded.
- [x] 3.2 Invalidate the persisted providers only after a settled successful
      write (no rebuild loop on a failing store; no write when converged).
- [x] 3.3 `activeSeasonResolutionProvider` left as a pure resolver (no
      eviction side effect, no additional async watch — its `.future` stays a
      reliable single-build await).
- [x] 3.4 `AppShell` watches `activeScopeRepairProvider` (the shell is what
      runs the repair, as it already restores the active-episode scope).

## 4. Tests

- [x] 4.1 `test/unit/shell/active_season_repair_test.dart` — 10 cases driving
      the real providers with the fetch seam and the two stores overridden:
      eviction, live anchor kept, block-scope pruning, no eviction while
      loading, no eviction on a failed fetch, compare-and-remove race (a
      racing DAO writes a fresh anchor between the read and the delete),
      session scoping, a failing delete (one attempt, no loop), a failing
      block-scope write (one attempt, no loop), idempotence.
- [x] 4.2 `test/features/shell/active_season_repair_test.dart` — 3 widget cases
      through a probe that watches exactly what `AppShell` watches: eviction,
      no drop of a live-but-unloaded season, eviction only after the load.
- [x] 4.3 `test/unit/shell/shell_state_cache_test.dart` — `deleteIfValue`
      positive/absent/`Err` branches.

## 5. Verification

- [x] 5.1 `dart format --set-exit-if-changed .` — clean (0 changed).
- [x] 5.2 `flutter analyze` — no issues.
- [x] 5.3 `flutter test` — 2372 passed.
- [x] 5.4 `tool/breakdown_lints_runner` (`dart run bin/run_lints.dart ../..`)
      — no violations.
- [x] 5.5 `scripts/add-spdx-headers.sh --check` — all headers present.
- [x] 5.6 `build_runner` regenerated (`active_season_store.g.dart`,
      `app_shell` deps); no hand edits to generated files.
