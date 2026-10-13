<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# flutter-fundus-search — implementation tasks

## 1. Pure model & matcher (Tier-1)

- [x] 1.1 Create `lib/features/fundus/fundus_model.dart`: `FundusInputs`
      (project id, repertoire costumes, project seasons), `FundusViewState`,
      and the pinned field contract (notes + category name only)
- [x] 1.2 Implement the pure fundus matcher (season filter + name
      prefilter reusing `foldForSearch`) with table-driven unit tests:
      whole-fundus default, season narrowing, repertoire-intersection,
      diacritics, empty query

## 2. Cache slice & repository

- [x] 2.1 Add `FundusCostumeCacheRows` to `costume_domains_cache.dart`
      (PK `{id}`, `project_id` fetch scope, mirrors `CostumeView` incl.
      `season_ids_json`)
- [x] 2.2 Register the table in `cache_database.dart`, bump
      `schemaVersion` to 14, add the `from < 14` `createTable` migration
- [x] 2.3 Add `FundusCostumeCacheDao`: `applySnapshotForProject`,
      `readByProjectFresh`, `upsert`, `clearProject`, `isProjectExpired`
- [x] 2.4 Add `lib/data/fundus_repository.dart`: project-scoped fetch via
      `fetchAllPages(listCostumes(projectId:))`, snapshot-replace, cached
      read, TTL staleness, clear; `Result`-typed, no throws
- [x] 2.5 DAO/repository unit tests: cross-project isolation, repertoire
      exclusion, Err-branch assertions, empty/unfetched distinguishability

## 3. Controller & providers

- [x] 3.1 `lib/features/fundus/fundus_controller.dart`: repository
      provider, project-scoped inputs provider (costumes + project
      seasons), query state (text + selected seasons), view controller
      with retained last-good rows and `AsyncError` on storage failure
- [x] 3.2 Bounded prefetch on surface open (repository fetch, fence-guarded)
      so a cold project cache fills without a spinner flash

## 4. UI surface

- [x] 4.1 `lib/features/fundus/fundus_screen.dart`: title, name prefilter
      field, season chip row, repertoire-aware rows, deep link to
      `CostumeDetailScreen` (via `fundus_destinations.dart`)
- [x] 4.2 States: initial empty, zero-match (echoing active season
      filter), not-yet-loaded, error + retry, stale banner; no-season
      empty state
- [x] 4.3 Cast-view entry affordance (`features/shell/cast_tab_screen.dart`)
      with a visible tooltip and key

## 5. Localization & design docs

- [x] 5.1 ARB keys (de/en) in `app_de.arb`/`app_en.arb`; regenerate
      localized classes
- [x] 5.2 `docs/design/screens/fundus.md` (nine template sections, Salt
      wireframe, compiles) + glossary row for the Cast entry action

## 6. Tests & guardrails

- [x] 6.1 Widget tests: season chips narrow results, prefilter matches,
      repertoire season names render, deep-link target, zero-match/error/
      no-season states
- [x] 6.2 Golden test for the fundus surface
      (`goldens/fundus_screen_light.png`)
- [x] 6.3 AI-import exclusion regression test (fundus never reads the
      `ai_import_*` tables)
- [x] 6.4 `dart format`, `flutter analyze`, `flutter test` clean; no
      hand-edited generated files

## 7. Governance

- [x] 7.1 Record the four explicit decisions (separate surface, project
      scope, client cache, exclusions) in this change (design.md)
- [x] 7.2 Confirm no `backend/openapi.yaml` change and no OpenAPI client
      regeneration is required (project-scoped route already generated)
- [x] 7.3 Bump `frontend-flutter/pubspec.yaml`
      (`0.4.0-alpha.13+64 → 0.4.0-alpha.14+65`) and record the
      `[Unreleased]` CHANGELOG entry (Play `versionCode` `+N` monotonic)
