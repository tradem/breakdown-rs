<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# 549-reports-discoverability-loaded-goldens

## Why

The reporting surface is **implemented and fully test-covered** — the problem
is that it is *invisible* to the user, its strongest state is not asserted,
and its design documentation is inconsistent. This is a
discoverability + assertion-coverage + docs-consistency change on a shipped
feature, not a missing-feature change.

Five gaps, all verified against the tree:

1. **The entry point is tooltip-only, and it is the only one.** The reports
   screen is reachable from exactly one place: an `IconButton`
   (`Icons.summarize_outlined`, key `reports-open`, tooltip `Berichte`) in the
   day board's app bar (`lib/features/scene_shoots/scene_shoots_screen.dart`).
   Design D8 (reports are strictly day-scoped, anchored in the day board)
   **stands** — but the single entry is an icon with a tooltip and no visible
   label, which is the one form the glossary's visible-label norm
   (`docs/design/screens/README.md`: *"Every navigation destination and
   primary action shows a visible label (glossary rule); icons reinforce
   only."*) does not sanction. The day board is the on-set surface, so the
   affordance must be findable **without hover**.
2. **A planned season-level entry was never built; the Gherkin step is dead
   code.** `integration_test/gherkin/steps/common_steps.dart` defines
   `whenOpenSollIstReport()` — tapping `Key('open-soll-ist-report-$seasonId')`,
   a key that exists **nowhere** in `lib/` — and registers it in
   `configuration.dart`, while no scenario in `features-spec/` uses it. It can
   never fail, and its `TODO(screen)` comment reads to every future
   maintainer as a pending requirement.
3. **The goldens assert only the pre-data state.** All four committed goldens
   are `reports_idle_{light,dark}_{android,macos}.png` — the state *before*
   any report is loaded. The spec's *"{light,dark} × {android,macos} goldens"*
   requirement is satisfied **in form** while the coverage sits where it
   matters least: there is no golden for the **loaded** report (Soll/Ist rows,
   the four flag chips, the counts row, the `final` banner from `wrapped_at`,
   the PDF cards) nor for the 403 denial narrative. The 12 non-golden widget
   tests cover the *state machine* well; the *rendered report* is unasserted.
4. **The glossary carries a duplicate row and two non-existent copy keys.**
   Two rows for the same icon+label, citing `reports.open` and
   `sceneShoots.reports` — **neither exists in any ARB file**. The real key is
   `sceneShootsReportsTooltip` (present in both catalogs).
5. **A scene with no shooting day gives no hint that a report exists.** The
   chain is: no day → no day board (its entry is disabled when
   `byId[id] == null`) → no `reports-open` → and **no text anywhere** on the
   scene saying a Soll/Ist report will exist once days are planned. A user who
   has just created a scene sees no reports affordance and no reason to expect
   one later.

## What Changes

- **Adaptive labelled reports entry (Gap 1).** The `IconButton` becomes a
  `_ReportsAppBarAction` that renders a `TextButton.icon`
  (`Icons.summarize_outlined` + visible label `Berichte`) — one tap, visible
  without hover — and collapses into a **labelled** overflow-menu item
  (`ListTile`, leading icon + label) only when the app bar is too narrow to
  carry both the label and a readable title. It never reverts to icon-only.
  The decision is a width breakpoint on the scaffold's `LayoutBuilder`
  (`_reportsLabelMinBarWidth`), not a platform check, so it is deterministic
  and directly testable at both widths. The Gherkin contract key
  **`reports-open` is unchanged** in both branches (it sits on whichever
  widget is the tap target), so `whenOpenReports()` keeps passing.
- **Dead step removal (Gap 2 — Option A).** Delete `whenOpenSollIstReport()`
  and its registration in `configuration.dart`. The day-scoped entry is the
  shipped contract and the `.feature` file already uses it. **Option B is
  explicitly rejected here**: a season-level report is a *new screen with new
  backend scope*, not a fix — `openapi.yaml` carries only
  `/v1/shooting-days/{id}/report/{dispo,shoot-day,soll-ist}` (+ `.pdf` twins)
  and `/v1/shooting-days/{id}/report/archive`, with **no** scene- or
  season-scoped report route. It needs its own change proposal (tracked as a
  follow-up issue), its own `// AUTHZ-GATE:` decision, and its own spec delta.
- **Loaded-state goldens (Gap 3).** Twelve new goldens in the existing
  `{light,dark} × {android,macos}` matrix: `loaded_*` (rows + all four flag
  chips + counts row), `loaded_final_*` (adds the `wrapped_at` finality
  banner — a distinct, easy-to-regress state), `loaded_denied_*` (the 403
  AUTHZ-GATE narrative with zero report requests). The four `reports_idle_*`
  goldens stay byte-valid. Platform variants are kept for all three states
  because the platform already changes the surface (scrollbar/overscroll) in
  the idle set — dropping them for the new states would weaken the matrix.
- **Report-provenance empty state (Gap 5, client half).** On a scene with
  **0** shooting days, the existing empty `ListTile`
  (`scene-shooting-days-empty`) gains a subtitle naming the Soll/Ist report as
  what becomes available once the scene is scheduled. It **invents no report**
  and adds no season-level entry — the hint is text, not an affordance that
  leads nowhere. Same rule as the report's own `reportsNoScenes` empty state.
- **Glossary correction (Gap 4).** The two `summarize_outlined` rows collapse
  into **one**, citing the ARB identifiers that actually exist
  (`sceneShootsReportsTooltip` for the tooltip, new
  `sceneShootsReportsLabel` for the visible label) — which is exactly what the
  row format is for once an entry has two keys. New keys also added to the
  implemented-inventory table so
  `frontend-flutter/tool/check_glossary_catalog.py` guards them.
- **Spec deltas (the silent-gap fix).** `flutter-reports-screen` gains the
  report-provenance empty-state requirement; `flutter-scene-shoots-screen`
  gains the labelled-entry requirement. The issue text planned only the
  former; the second is added deliberately, because the *same* silence — a spec
  that says nothing about the entry — is precisely what let an icon-only
  entry survive four tiers of testing with no failing assertion.
- **Deliberately out of scope:** the `ShootingDaysScreen` navigation dead end
  (a day row has no `onTap`, so the day board is unreachable from the
  episode-level schedule view). Same class of problem as Gap 1 but a
  *navigation-graph* change on the hierarchy spine — deferred to **#548**, as
  the issue records. The backend half of Gap 5 is likewise a separate change.

## Impact

- **Affected specs:** deltas under
  `openspec/changes/549-reports-discoverability-loaded-goldens/specs/`
  (`flutter-reports-screen` — report-provenance empty state;
  `flutter-scene-shoots-screen` — labelled entry). Main specs untouched
  until archive.
- **Affected code:**
  - `frontend-flutter/lib/features/scene_shoots/scene_shoots_screen.dart`
    (reports entry becomes a labelled/adaptive action),
  - `frontend-flutter/lib/features/scenes/scene_detail_screen.dart`
    (report-provenance empty-state subtitle),
  - `frontend-flutter/integration_test/gherkin/steps/common_steps.dart` +
    `configuration.dart` (dead step removed).
  - No wire-contract change: `backend/openapi.yaml` is not touched, no client
    regeneration is needed (Gap 5's client half invents no route).
- **New ARB keys** (de/en): `sceneShootsReportsLabel` (the visible entry
  label), `sceneDetailNoShootingDaysReportHint` (the report-provenance
  subtitle). Existing `sceneShootsReportsTooltip` (now also the overflow
  fallback's label), `sceneDetailNoShootingDays`, `reportsNoScenes` reused.
- **Tests:** widget tier for the labelled entry (semantic finder on the label
  text — fails if the label regresses to icon-only — plus the narrow-width
  overflow arm and a `reports-open` key-stability assertion in both branches);
  widget tier for the 0-day empty state **and its absence** on a scene that
  has days; 12 new reports goldens; the four `scene_shoots_board_*` goldens
  regenerate (the app-bar action is wider by the label); the Gherkin
  `soll_ist_report.feature` is unchanged and stays green. **No new unit
  tests** — every gap is presentation, coverage, or docs.
