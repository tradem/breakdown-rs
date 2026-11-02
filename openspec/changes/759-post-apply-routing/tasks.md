<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 759 — Tasks

## 1. Post-apply refresh (the bug component)

- [x] 1.1 `AiApplyController.apply()` success path invalidates
      `scenesListFetchProvider` per episode named by
      `response.applied_episodes` (whole family when it names none) plus their
      `scenesCacheStaleProvider` memos.
- [x] 1.2 The same path invalidates `seasonScriptFetchProvider`, so the Script
      view's composed rows cannot serve a pre-import projection.
- [x] 1.3 Retain the #666 `episodesListFetch` + `blocksListFetch` invalidation.

## 2. Routing into the imported material

- [x] 2.1 `pickAppliedTargetEpisode` — the reviewer's `episode_id` wins, then
      the biggest contribution, ties in server order; empty → `null`.
- [x] 2.2 `resolvePostImportTarget` — job block (cached row) → season id (block
      row) → `SeasonView` from the seasons read cache → episode number (wire,
      else the block's episode list); anything missing → `null`.
- [x] 2.3 `openImportedEpisode` — publish the report, set the episode scope
      (cascades the block scope), set the active season when it differs, select
      the Script destination, pop the import stack.
- [x] 2.4 `ScriptTabScreen` resets its own nested navigator to the root route
      when a report lands.

## 3. Report carried to the destination

- [x] 3.1 `PostImportReport` + `@Riverpod(keepAlive: true)` provider with
      `publish`/`dismiss`.
- [x] 3.2 `AiPostImportReportCard` — outcome line, skipped day groups,
      `unapplied_outfits` with reasons, additional episodes with row counts,
      dismiss action.
- [x] 3.3 Shared outcome/unapplied copy helpers (`aiApplyOutcomeLine`,
      `aiUnappliedOutfitReasonCopy`) so the inline card and the banner cannot
      drift.

## 4. Honest degradation

- [x] 4.1 Unresolved destination → stay on the review screen, keep the outcome
      card, render `ai-apply-navigation-unresolved`; scopes untouched.

## 5. Copy, docs, tests

- [x] 5.1 New ARB keys in `app_de.arb` (template) **and** `app_en.arb`;
      `flutter gen-l10n`.
- [x] 5.2 Glossary: icon row for `playlist_add_check` + the new ARB keys in the
      implemented inventory.
- [x] 5.3 Screen specs: `docs/design/screens/script-view.md` (post-import
      landing + report card) and `ai-import-jobs.md` (routing section).
- [x] 5.4 Tier 1 + Tier 2 tests in
      `test/features/ai_import/post_import_routing_test.dart`.
