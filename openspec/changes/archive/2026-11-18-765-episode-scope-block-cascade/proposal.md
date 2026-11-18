<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 765 — Selecting or restoring an episode cascades the block scope

## Why

Issue #765 reports a user-visible scope inconsistency in the shell: from the
Script view with **only a season selected**, picking an episode through the
episode scope pill set the episode scope but left the **block scope unset**.
The block pill kept showing "Kein Block", and the block-scoped request scope
(`X-Active-Block`, attached by `ActiveBlockInterceptor`) did not follow the
episode the user had just chosen.

An episode belongs to exactly one block, so "episode scope set, block scope
unset" is never a meaningful client state:

- `ActiveBlockInterceptor` attaches `X-Active-Block` to every request, and the
  backend authorization middleware **rejects a missing header with 400** on the
  block-scoped routes (episodes, scenes, shooting days, scene shoots, pieces,
  characters). A silently unset block scope means those calls go out
  headerless.
- The user has no visible indication which block the app is acting in — the
  block pill stays neutral while the episode pill is highlighted.
- The two scopes could also disagree in the other direction: switching the
  block scope left an episode scope from the *old* block active, so the shell
  could display "Block B · Episode of block A".

Root cause (verified in the tree): `ActiveEpisode.set(...)` stored only the
episode scope, and every call site — the scope-pill episode picker, the Script
tab's scene row, the schedule tab, the episodes screen rows and the cold-start
restore — wrote it directly, so the block scope was nobody's responsibility.
The cold-start restore was the reported entry point: it restores an episode
scope from the persisted document without a block scope, which makes the
episode pill visible (its prerequisite is "block scope OR episode scope") while
the block pill is empty.

## What Changes

- **One cascade seam — `ActiveEpisode.set`.** The episode notifier now also
  establishes the block scope from the same acted-on DTO
  (`activeBlockProvider.set(seasonId, episode.blockId)`) whenever the block
  scope does not already name that season/block pair. Because the cascade lives
  inside `set`, every existing and future
  `activeEpisodeProvider.notifier.set(...)` call site gets it structurally —
  the invariant cannot be forgotten by a new picker or screen.
  An optional `blockNumber` lets call sites that hold the `BlockView` (Script
  tab, schedule tab, episodes screen) carry the number, so the block pill needs
  no backfill; the restore and picker paths pass none and rely on the existing
  **cache-only** number backfill (never a fabricated number, never a network
  fetch).
  A matching block scope is left untouched, so a resolved number is never
  downgraded back to the "unknown" narrative.
- **Reverse direction — `ActiveBlock.set`.** A block scope that moves to a
  different block drops an episode scope belonging to another block
  (`ActiveEpisode.clearForForeignBlock`): in-memory always, plus the persisted
  per-season document when it belongs to that season, so a cold start cannot
  resurrect the stale pair. A scope from another season keeps its own document
  (per-season memory remains the season-switch path's `discard()` concern).
  The two cascades are ordered by construction (the episode is written before
  the cascade; the reverse guard is a no-op when the block matches), so the
  forward cascade is never undone by its own reverse.
- **Restore path.** The cold-start restore goes through the same `set` seam, so
  a restored episode scope cascades its block scope for the **active** season
  only — the persisted document is looked up by that season id, so a foreign
  season's remembered episode can never seed a block scope.
- **Call sites** (`script_tab_screen.dart`, `schedule_tab_screen.dart`,
  `episodes_screen.dart` ×2) pass the acted-on block number through the seam;
  the picker and the restore pass none.

## Impact

- **Specs:** `flutter-navigation-shell` (ADDED requirement "Episode Scope
  Implies Its Block Scope" — the canonical `openspec/specs/flutter-navigation-shell/
  spec.md` does not exist yet; #638's scope-pill requirement and #707's
  tab-root-reset requirement are still open deltas, so a `MODIFIED` heading
  would target a nonexistent canonical requirement).
- **Code:** `lib/auth/active_episode.dart` (`set` cascade + `blockNumber` +
  `clearForForeignBlock`), `lib/auth/active_block.dart` (`set` reverse guard),
  `lib/features/shell/script_tab_screen.dart`,
  `lib/features/shell/schedule_tab_screen.dart`,
  `lib/features/episodes/episodes_screen.dart` (call-site numbers),
  doc notes in `lib/features/shell/active_episode_chip.dart` and
  `lib/features/shell/app_shell.dart`. No l10n, no API/contract change —
  `backend/openapi.yaml` untouched, no client regen, no codegen run.
- **Tests:** `test/auth/active_episode_test.dart` (cascade, number carriage,
  no-downgrade, foreign-scope reconciliation, `clearForForeignBlock` +
  persistence), `test/auth/active_block_test.dart` (block switch drops a
  foreign episode + its document, same block keeps it, foreign season keeps its
  document), `test/features/shell/active_episode_chip_test.dart` (picker
  cascade), `test/features/shell/app_shell_test.dart` (restore cascade, pill
  labels after a Script-row-shaped cascade, block switch ⇒ no mismatched pair,
  cache-only backfill after a numberless cascade). No golden changes — the chip
  labels and layout are untouched.

## Non-goals

- No new network call and no second projection lookup: the episode DTO already
  carries `blockId`, and the block number comes from the acted-on `BlockView`
  or the cache-only backfill (CQRS boundary unchanged).
- No change to the episode/block pill visibility rules (#638), to the
  foreign-season narratives, or to `discard()`/`clear()` semantics.
- No pre-emptive rewrite of the AI-import post-import routing (that follow-up
  change must call the same seam; nothing here changes it).
