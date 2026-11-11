<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks: 879-evict-dead-episode-anchor

## 1. Store seam

- [x] 1.1 `ActiveEpisodeStore.removeScopeIfMatch({seasonId, episodeId})` — one
      conditional removal inside the store's write mutex, the twin of
      `ActiveBlockStore.removeScopeIfMatch`; `Right` (no write) when the stored
      entry no longer names that episode.

## 2. Proof of absence

- [x] 2.1 `EpisodesView.isLoaded` (additive, default `false`, fail-closed): the
      controller marks a successful snapshot `true`; the retained-row branches
      (`AsyncError`, `AsyncLoading`) state `false` explicitly.
- [x] 2.2 `flutter-offline-scope` delta spec records why the episode row list
      alone cannot authorize a deletion.

## 3. Repair

- [x] 3.1 `activeEpisodeScopeRepairProvider`
      (`lib/features/shell/active_episode_scope_repair.dart`): sync,
      keep-alive, side effect on watch. Evicts (a) every episode scope whose
      season the loaded seasons view no longer serves and (b) the active
      season's scope when its loaded episode projection does not contain the
      episode.
- [x] 3.2 Invalidate the persisted provider only after a settled successful
      write; no write when converged (no rebuild loop on a failing store).
- [x] 3.3 Drop the in-memory sticky scope when it still names the evicted
      `(seasonId, episodeId)` pair (compare-and-remove on the live value), so
      the chip and the quick-create entries stop pointing at a deleted episode.
- [x] 3.4 `AppShell` watches `activeEpisodeScopeRepairProvider` next to the
      `#817` season repair (the shell is what runs both).
- [x] 3.5 `activeSeasonResolutionProvider` stays a pure resolver (no eviction
      side effect, no additional async watch).

## 4. Tests

- [x] 4.1 `test/unit/shell/active_episode_scope_repair_test.dart` — 11 cases
      driving the real providers with both fetch seams and the store overridden:
      season-gone eviction, episode-gone eviction, live episode kept, no
      eviction while the episode fetch loads, no eviction on a failed episode
      fetch, no eviction while the seasons fetch loads, compare-and-remove on
      the document, no in-memory discard of a fresh pick, a failing write (one
      attempt, no loop), idempotence, season scoping.
- [x] 4.2 `test/features/shell/active_episode_scope_repair_test.dart` — 4 widget
      cases through a probe that watches exactly what `AppShell` watches.
- [x] 4.3 `test/auth/active_episode_store_test.dart` — `removeScopeIfMatch`
      match / no-op / unknown-season / storage-failure branches.
- [x] 4.4 Mutation-checked: removing the `isLoaded` gate fails exactly the two
      negative cases; removing the compare-and-remove fails the race case.

## 4b. Review round (CodeRabbit on PR #886)

- [x] 4b.1 Projector-lag grace: `episodePickTimesProvider` records real picks
      (in memory, per season) through the `ActiveEpisode.set` seam;
      `isRestore: true` marks the cold-start replay so it never renews the
      window; the repair skips picks younger than
      `kEpisodeScopeSettleWindow` (30 s).
- [x] 4b.2 Repair provider is auto-dispose (shell-lifetime ownership) instead of
      keep-alive, so sign-out ends the repair via the `ref.mounted` fence.
- [x] 4b.3 Per-scope attribution: `Future.wait` results are paired with their
      entry, so only successfully removed scopes reach the in-memory discard.
- [x] 4b.4 Unit test for the settle window (protected inside, evicted past it —
      mutation-checked: removing the guard fails it).
- [x] 4b.5 Store suite splits the read-failure and write-failure branches
      (`failAll` vs `failWrites`; the write branch asserts
      `active_episode.scopes_write_failed`).
- [x] 4b.6 Runbook §13: `pm clear` deletes the remembered AI-config id (secure
      storage, not Drift); the recovery path is documented.

## 5. Verification

- [x] 5.1 `dart format --set-exit-if-changed .` — clean.
- [x] 5.2 `flutter analyze` — no issues.
- [x] 5.3 `flutter test` — full suite green.
- [x] 5.4 `scripts/add-spdx-headers.sh --check` — all headers present.
- [x] 5.5 `build_runner` regenerated
      (`active_episode_scope_repair.g.dart`, `episodes_controller.g.dart`);
      no hand edits to generated files.
- [x] 5.6 Runbook §13 updated: the manual episode-scope clear is no longer part
      of the reset procedure.
