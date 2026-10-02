<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## Why

The Soll/Ist report surface is complete and day-scoped by design (D8), and
#549 made its single entry point findable. But the **per-day hop is not
reachable from the list of days**: `shooting_days_screen.dart` builds
`ShootingDayTile` with only `onRename` / `onReschedule` / `onUnschedule` /
`onArchive` / `onMoveUp` / `onMoveDown` — no `onTap` at all. The only way
into a day board (and therefore into a report) is
`scenes/scene_detail_screen.dart:490`. A user standing in the episode's
Drehtage list has no way to open any report without first navigating
*backwards* to a scene.

The user's real question — "wie lief die Staffel?" — is therefore answered
by walking day boards one at a time, each reached indirectly, with no
overview of which days even have a report.

This change delivers that overview as a **pure navigation index**: a
season/episode entry that lists the shooting days and links to the
**existing, shipped** per-day reports. It deliberately adds **no backend
route** — the expensive half of #571 (aggregation, aggregate finality, a
wider authz surface) stays out and is left as a documented, evidence-backed
follow-up.

## What Changes

- **A report index screen (`ReportsIndexScreen`).** Lists the shooting days
  of one episode, each row showing the day's own label, date and an
  `abschließend` / `offen` state derived from the day's own `wrapped_at`
  field in the existing `ShootingDayView` DTO — never from a client-side
  recomputation. Tapping a row pushes the **existing** `ReportsScreen` with
  that day's `ReportDayScope`. No report content is rendered on the index;
  it is a navigation surface, not a second report.
- **A labelled entry in the hierarchy spine.** `ShootingDaysScreen` gains a
  `_ReportsAppBarAction`-style labelled action (`Berichte`, icon
  reinforcing only, per the glossary's visible-label norm) that pushes the
  index. The day rows themselves stay non-navigating — the index is the one
  new affordance, so the tile's action set does not grow a second tap
  target.
- **`seasonId` threaded to the day surface.** `ShootingDaysScreen` today
  receives only `EpisodeView`, and `EpisodeView` carries `block_id` /
  `series_id` but **no** `season_id`. The index needs the season id for the
  reports membership gate. It is threaded down from `EpisodesScreen`
  (which already holds `block.seasonId`) exactly as `ScenesScreen`
  receives it today — a nav-context field, **not** a second projection
  lookup (the client-side CQRS boundary, D2).
- **Reinstatement of the Gherkin step #549 deleted.** A new tier-3
  scenario covers season → block → episode → reports index → per-day
  report, and the removed `open-soll-ist-report-$seasonId` step is
  reinstated against a key that now actually exists.
- **An honest empty state.** An episode with no shooting days shows plain
  copy naming the report as what becomes available once a day is planned —
  the same provenance-hint pattern #549 shipped for the scene case. The
  index still offers no report for a day-less scope, because the report
  routes are day-scoped in the contract itself.

### Explicitly NOT in this change (the #571 follow-up)

- No season- or scene-scoped **aggregated** report route.
- No aggregate finality rule (any/all unwrapped) — that decision is
  unmade, and the index sidesteps it by showing *per-day* `wrapped_at`
  state only.
- No new authorization capability. The index reuses the existing
  season-scoped `has_active_costume_role_in_season` gate the per-day
  routes already use, because the index exposes **no** report content —
  only day labels, dates and finality, all already visible in the day list.
- No `openapi.yaml` change, no client regeneration, no PDF work. The three
  per-day PDFs stay reachable from the per-day report screen as shipped.

## Capabilities

### New Capabilities

- `flutter-reports-index`: the season/episode-scoped report **index**
  surface — its row contents, its per-day finality derivation, its empty
  state, its navigation into the existing per-day report screen, and its
  client-side membership gate.

### Modified Capabilities

- `flutter-hierarchy-navigation`: the spine gains a labelled reports entry
  on the episode's shooting-days screen, and `season_id` is added to the
  nav context threaded into that screen (the D8 "anchored in the day
  board" decision is widened to "anchored in the day board **and** indexed
  per episode", with the day-scoped report surface itself unchanged).
- `flutter-reports-screen`: the day-scoped report screen gains a second,
  documented inbound path (from the index) and a documented invariant — it
  is still the **only** place report content is rendered, still renders
  exclusively from its read DTOs, and the index is not an alternative
  renderer of the same data.

## Impact

**Client only (`frontend-flutter/`), no backend, no contract change.**

- `lib/features/reports/reports_index_screen.dart` (new) +
  `reports_index_controller.dart` / `_state.dart` — a `ConsumerWidget`
  container rendering `asyncValue.when`, presentation widgets under
  `widgets/` with no Riverpod imports, fed by a family provider that
  **reuses the existing `shootingDaysControllerProvider(episodeId)` state**
  rather than issuing a second fetch. The index therefore adds no network
  traffic and no new Drift table — it reads the rows the day list already
  holds.
- `lib/features/shooting_days/shooting_days_screen.dart` — `seasonId`
  parameter added, labelled reports action added.
- `lib/features/episodes/episodes_screen.dart` — passes
  `block.seasonId` into `ShootingDaysScreen`.
- `lib/l10n/app_de.arb` + `app_en.arb` — new keys for the entry, the
  index title, the per-day `abschließend`/`offen` state, and the empty
  state. German copy quoted verbatim in the specs below.
- `features-spec/soll_ist_report.feature` — one new scenario.
- `integration_test/gherkin/steps/common_steps.dart` +
  `configuration.dart` — the reinstated step + the new index step.
- `docs/design/screens/navigation-shell.md` — the D8 note
  (line 84) is updated to describe the index.
- `docs/design/glossary.md` — a row for the new entry, per #549's
  duplicate-row fix.

**No impact on:** `backend/`, `backend/openapi.yaml`,
`vendor/breakdown_api/`, the `SceneShootReportRepository` port, any
`problem_codes!` entry, or the authz capability set.

**Test impact:** goldens for the index in the established
`{light,dark} × {android,macos}` matrix (idle, loaded, denied) plus widget
tests for the empty state, the per-day finality chip, and the row tap
pushing the per-day report with the right `ReportDayScope`.
