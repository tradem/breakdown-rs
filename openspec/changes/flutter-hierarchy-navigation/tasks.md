<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Hierarchy Navigation

## 1. Shared reconciliation extraction
- [ ] 1.1 `lib/domain/reconciliation/` — move
       `ReconciliationScheduler` / `ExponentialBackoffScheduler`, extract
       overlay bookkeeping (add / markReconciling / dropProjected /
       markAllStale) and the single-flight + ack-generation runner,
       parameterized per aggregate
- [ ] 1.2 Migrate `features/seasons/seasons_controller.dart` onto the
       shared module; seasons golden tests must remain byte-stable
       (parity proof)
- [ ] 1.3 Unit tests: runner with fake scheduler — attempt budget,
       exhaustion, late-ack follow-up, success-drop; parity cases ported
       from the seasons reconciliation tests

## 2. Data layer (repositories + Drift)
- [ ] 2.1 Drift migration adding `blocks`, `episodes`, `scenes`,
       `costume_categories` tables (mirror read DTOs; `costume_categories`
       carries `order_key` + `archived`; bump schema version + migration
       test)
- [ ] 2.2 `data/block_repository.dart` — `listBySeason(seasonId)`
       (GET `?season_id=`; snapshot-replace), `create(request)`
       (`Result<IdVersionResponse, ProblemError>`)
- [ ] 2.3 `data/episode_repository.dart` — `listBySeason(seasonId)`
       + `groupByBlock(rows)` pure mapper (D3: no block_id filter exists);
       `create(request)`
- [ ] 2.4 `data/scene_repository.dart` — `listByEpisode(episodeId)`,
       `create(request)`
- [ ] 2.5 `data/costume_category_repository.dart` — `list(seasonId)`,
       `create`, `rename(id, version, name)`, `archive(id)`
- [ ] 2.6 Unit tests for every repository method: Ok AND Err branches;
       cache untouched on fetch failure; snapshot-replace removes deleted
       rows

## 3. Membership read
- [ ] 3.1 `lib/auth/season_membership_provider.dart` — family provider,
       strict `SeasonMembershipDto` capability parsing (unknown string →
       `Err`), TTL-scoped caching
- [ ] 3.2 Unit tests: strict parser (known set / unknown entry),
       provider refetch-vs-TTL behavior with fake clock

## 4. Controllers
- [ ] 4.1 `features/blocks/` — family `BlocksController(seasonId)` on
       the shared reconciliation; state = projected/cachedRows/isStale/
       overlays/commandError; `create()` gated by the session
       AUTHZ-GATE (`// AUTHZ-GATE:` annotated, ids from the season DTO)
- [ ] 4.2 `features/episodes/` — `EpisodesController(blockId, seasonId)`
       (repository-side group-by), create gated likewise
- [ ] 4.3 `features/scenes/` — `ScenesController(episodeId)`, create
       gated likewise
- [ ] 4.4 `features/costume_categories/` — controller + next-order-key
       pure function (append rule `!`..`~`, overflow grows length)
- [ ] 4.5 Unit tests per controller: create happy path (overlay only
       after 2xx), conflict/validation (no overlay, keyed-on-`code`
       copy), exhaustion (stale overlay), 404 narrative branch

## 5. Screens & widgets
- [ ] 5.1 Seasons screen: tappable rows → push `BlocksScreen`; toolbar
       entry to the categories screen of the selected season
- [ ] 5.2 `BlocksScreen` — list + empty state + pull-to-refresh + FAB
       (create block; fields number/start/end, ids pre-filled from the
       season DTO), membership/capabilities chip on the AppBar
- [ ] 5.3 `EpisodesScreen` — grouped episodes of the tapped block +
       create (number + optional name)
- [ ] 5.4 `ScenesScreen` — episodes' scenes with read-only detail data
       (mood, location, summary, script day, schedule flag,
       `assigned_characters.length`, `shooting_day_ids.length`) + create
- [ ] 5.5 `CostumeCategoriesScreen` — `order_key`-ascending list,
       archived toggle, rename dialog (version echo), archive action,
       create dialog with derived order key
- [ ] 5.6 Pure `widgets/` trees per screen (no Riverpod imports), theme
       tokens only; macOS variants: focus traversal, hover, Escape-close
       dialogs, width-gutter behavior; Android: 48 dp targets

## 6. Widget + golden tests (Tier 2)
- [ ] 6.1 Per screen: data / empty / error / stale / overlay-state
       widget tests (semantic finders, paired with goldens)
- [ ] 6.2 Goldens {light, dark} × {android, macos} for every non-trivial
       surface (4 variants each)
- [ ] 6.3 404-narrative + pop-back tests; membership chip states; strict-
       parse error state
- [ ] 6.4 Categories: toggle, rename-409 copy, archive flow, order-key
       edge derivation surfaced in list order

## 7. Integration tests (Tier 4)
- [ ] 7.1 On-emulator smoke (dev-auth backend): create season → block →
       episode → scene → category; each appears after projector lag
       within the reconciliation budget; back navigation preserves state
- [ ] 7.2 Sign-out mid-navigation returns to the login gate (depends on
       `flutter-login-and-app-shell`)

## 8. Housekeeping
- [ ] 8.1 SPDX headers; `dart format` / `flutter analyze` /
       `breakdown_lints_runner` clean; `flutter test --coverage` +
       `coverde` changed-code gate; no new packages (pure Flutter usage)
- [ ] 8.2 `openspec` coverage audit: every scenario in
       `flutter-hierarchy-navigation` and
       `flutter-costume-categories-screen` has a passing test
- [ ] 8.3 Backend issue #335 tracks the episodes `block_id` filter
       gap (design.md D3 — client-side grouping in the meantime); a
       follow-up swaps the repository to the server filter once the
       contract lands — no `backend/openapi.yaml` edit in this change
