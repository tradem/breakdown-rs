<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 765 — Tasks

## 1. Cascade seam (notifiers)

- [x] 1.1 `ActiveEpisode.set` cascades the block scope from the acted-on
      episode's `blockId`; add the optional `blockNumber` (carried from the
      acted-on `BlockView`) and document the "an episode implies its block"
      invariant.
- [x] 1.2 Skip the cascade when the block scope already names the same
      season/block pair (never downgrade a resolved number; no loop with the
      reverse guard).
- [x] 1.3 `ActiveEpisode.clearForForeignBlock` — drops the in-memory scope and,
      for the same season, its persisted document; a foreign season keeps its
      document.
- [x] 1.4 `ActiveBlock.set` calls the reverse guard after writing its own scope;
      document the reverse half of the invariant in both notifiers.

## 2. Call sites

- [x] 2.1 `ScriptTabScreen._open` passes `blockNumber: row.block.number`.
- [x] 2.2 `ScheduleTabScreen` day row passes `blockNumber: row.block.number`.
- [x] 2.3 `EpisodesScreen` scene entry + shooting-days entry pass
      `blockNumber: block.number`.
- [x] 2.4 Doc notes: the episode picker (`active_episode_chip.dart`) states that
      a pick cascades; `AppShell._restoreEpisodeScope` states that the restore
      cascades through the same seam and can only seed the ACTIVE season's
      block.

## 3. Tests

- [x] 3.1 `test/auth/active_episode_test.dart`: cascade sets the block scope;
      `blockNumber` travels; a matching scope keeps its number; a foreign block
      scope is reconciled without eating the episode; `clearForForeignBlock`
      drops memory + same-season document and keeps another season's document.
- [x] 3.2 `test/auth/active_block_test.dart`: a block switch drops the foreign
      episode scope and its persisted document; re-setting the same block keeps
      the episode; a block switch in another season keeps that season's
      document.
- [x] 3.3 `test/features/shell/active_episode_chip_test.dart`: a pick from the
      picker cascades the block scope (no fabricated number).
- [x] 3.4 `test/features/shell/app_shell_test.dart`: cold-start restore cascades
      the block scope (honest unknown label); the Script-row-shaped cascade
      labels both pills and a later block switch drops the foreign episode
      (neutral arm); a numberless cascade keeps "unknown" until the cache-only
      backfill resolves it, without eating the episode.

## 4. Validation

- [x] 4.1 `dart format --set-exit-if-changed .` clean.
- [x] 4.2 `flutter analyze` clean.
- [x] 4.3 `flutter test` green (full suite).
- [x] 4.4 No codegen: `vendor/breakdown_api/` untouched (`backend/openapi.yaml`
      unchanged), no `*.g.dart` / `*.freezed.dart` regeneration needed.
- [x] 4.5 `openspec validate 765-episode-scope-block-cascade` passes.
