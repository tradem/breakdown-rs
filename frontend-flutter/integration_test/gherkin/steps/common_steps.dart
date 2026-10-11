// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import 'package:frontend_flutter/auth/membership/debug_membership_override.dart'
    show DevAuthRole;

import '../world/app_world.dart';

/// The runner launches the instrumented app before each scenario. Dev-auth
/// boots SIGNED OUT at the auth gate (spec `flutter-auth-shell`) — the
/// gate's visible Continue action (`login-continue-button`, „Continue as
/// dev-e2e") resolves the permissive session explicitly. The step taps it
/// when present (hot-restarted isolate may already be signed in), then
/// asserts the home screen rendered on device — an on-device assertion,
/// not a pure-function check.
StepDefinitionGeneric givenAppLaunched() => given<FlutterWorld>(
  'the app is launched in dev-auth mode',
  (context) async {
    final driver = context.world.driver!;
    try {
      final gate = find.byValueKey('login-continue-button');
      await driver.waitFor(gate, timeout: const Duration(seconds: 5));
      await FlutterDriverUtils.tap(driver, gate);
    } on Object {
      // No auth gate: the isolate is already signed in (hot restart
      // between scenarios) — go straight to the home assertion.
    }
    await driver.waitFor(
      find.byValueKey('seasons-list'),
      timeout: const Duration(seconds: 30),
    );
  },
);

/// Records the asserted caller role for downstream AUTHZ-GATE assertions and
/// — dev-auth mode only — flips the app's membership override to that role
/// via the FlutterDriver data channel (issue #368): the runner builds the
/// app once with fixed dart-defines, so a per-scenario membership shape
/// (permissive costume-dept vs. capability-less viewer) must be switched at
/// runtime. `restartAppBetweenScenarios` starts each scenario's isolate with
/// the override cleared (a fresh `DebugMembershipOverride.role` static), and
/// this step re-asserts it explicitly. Unknown roles deny fail-closed inside
/// the app (`unknown-role` response) so the harness can never hand out
/// capabilities by typo. Never calls a pure function to satisfy an
/// assertion — the channel round-trip IS the device interaction.
StepDefinitionGeneric givenAuthenticatedAs() => given1<String, FlutterWorld>(
  'I am authenticated as a {string} user',
  (String role, context) async {
    final world = context.world as AppWorld;
    world.currentRole = role;
    // Reset first: the static override must never leak between scenarios
    // even if the isolate were hot-restarted instead of fresh.
    await context.world.driver!.requestData('dev-membership:role=');
    if (DevAuthRole.isKnown(role)) {
      // KNOWN role → flip the in-app dev-auth membership override (issue
      // #368): per-scenario membership shape cannot be a compile-time
      // dart-define (the runner builds the app once). `viewer` yields the
      // capability-less denial membership; `costume_dept` resolves the
      // default permissive one (no override needed).
      if (role != DevAuthRole.costumeDept) {
        final applied = await context.world.driver!.requestData(
          'dev-membership:role=$role',
        );
        if (applied != role) {
          throw Exception(
            'dev-membership override rejected role "$role" '
            '(app replied "$applied").',
          );
        }
      }
    } else {
      // UNKNOWN role (e.g. "planner", "viewer"-scoped features in other
      // .feature files): the dev-auth membership has no role plumbing for
      // it — record intent only, exactly as before issue #368. The
      // authoritative membership/capabilities remain server-derived.
    }
  },
);

/// Opens the day-context reports from the day board's "Reports" action
/// (`reports-open` on `SceneShootsScreen`, `flutter-reports` 2.1). Runs on
/// device, does not call a pure function.
///
/// The entry has TWO forms (issue #549): a labelled `TextButton.icon` at
/// realistic widths, and — when the app bar is too narrow to carry the label
/// next to a readable title — a `PopupMenuButton` whose item is itself
/// labelled. `reports-open` is the tap target of BOTH, but only the labelled
/// form navigates on the first tap; the collapsed form opens a menu. So this
/// step taps the entry and then selects the overflow item when it appears.
///
/// The 2s bound is the analytic worst case, not a sleep budget: the menu is a
/// `FadeScaleTransition` over `kThemeChangeDuration` (200ms) plus one frame,
/// so 2s carries a 10x margin. On the common (wide) path the wait simply
/// times out and the step returns — the branch costs one failed wait, never a
/// flaky navigation.
StepDefinitionGeneric whenOpenReports() => when1<String, FlutterWorld>(
  'I open the reports for shooting day {string}',
  (String dayId, context) async {
    final driver = context.world.driver!;
    final entry = find.byValueKey('reports-open');
    await FlutterDriverUtils.tap(driver, entry);

    // Only the collapsed form leaves a menu open; the labelled form already
    // navigated and this item will never exist.
    final overflowItem = find.byValueKey('reports-open-overflow-item');
    try {
      await driver.waitFor(overflowItem, timeout: _reportsMenuTimeout);
    } on DriverError {
      // Labelled action: the reports screen is already pushed.
      return;
    }
    await FlutterDriverUtils.tap(driver, overflowItem);
  },
);

/// Analytic upper bound for the overflow menu to route in and paint its item
/// (Material `kThemeChangeDuration` = 200ms + one frame, 10x margin). Never a
/// sleep used to hope something became true.
const _reportsMenuTimeout = Duration(seconds: 2);

/// Reinstates the step #549 deleted: it tapped
/// `Key('open-soll-ist-report-$seasonId')`, a key that existed nowhere, and
/// was removed rather than smuggled into a discoverability fix. This change
/// (`reports-season-report-index-571`) ships the episode's report index and
/// reinstates the step against the key that NOW exists: the labelled
/// reports entry on the episode's shooting-days screen
/// (`reportsIndexOpen`, label „Berichte"), which pushes the index — the
/// season-level REACHABILITY surface for the day-scoped reports (D8: the
/// report itself stays day-scoped; aggregated season reports remain #571's
/// unmade decision). The season parameter is retained for the original
/// step text; the affordance it resolves is the episode's index entry.
///
/// Same two-form discipline as [whenOpenReports]: the labelled
/// `TextButton.icon` navigates on the first tap; the collapsed (narrow)
/// form opens a menu whose item must be tapped. Runs on device.
StepDefinitionGeneric whenOpenSollIstReport() => when1<String, FlutterWorld>(
  'I open the Soll-Ist report for season {string}',
  (String seasonId, context) async {
    final driver = context.world.driver!;
    final entry = find.byValueKey('reportsIndexOpen');
    await FlutterDriverUtils.tap(driver, entry);

    // Only the collapsed form leaves a menu open; the labelled form
    // already navigated and this item will never exist.
    final overflowItem = find.byValueKey('reportsIndexOpen-overflow-item');
    try {
      await driver.waitFor(overflowItem, timeout: _reportsMenuTimeout);
    } on DriverError {
      return;
    }
    await FlutterDriverUtils.tap(driver, overflowItem);
  },
);

/// Season-level aggregate Soll-Ist entry (issue #571): the labelled action
/// on the blocks screen (`reportsAggregateOpen`, label „Soll-Ist gesamt")
/// pushes the season-scope aggregate screen. Same two-form discipline as
/// [whenOpenReports]: labelled form navigates first tap, collapsed form
/// opens the overflow menu whose item must be tapped.
StepDefinitionGeneric whenOpenAggregateSollIstReportForSeason() =>
    when1<String, FlutterWorld>(
      'I open the aggregate Soll-Ist report for season {string}',
      (String seasonId, context) async {
        final driver = context.world.driver!;
        final entry = find.byValueKey('reportsAggregateOpen');
        await FlutterDriverUtils.tap(driver, entry);
        final overflowItem = find.byValueKey(
          'reportsAggregateOpen-overflow-item',
        );
        try {
          await driver.waitFor(overflowItem, timeout: _reportsMenuTimeout);
        } on DriverError {
          return;
        }
        await FlutterDriverUtils.tap(driver, overflowItem);
      },
    );

/// Episode-level aggregate Soll-Ist entry (issue #571): the labelled
/// action on the report index (`reportsIndexAggregateOpen`) pushes the
/// episode-scope aggregate screen. Same two-form discipline.
// Zero-parameter step: the step text carries NO placeholder, so the
// definition takes no argument (flutter_gherkin matches on the parameter
// count — CodeRabbit review finding for this @pending scenario).
StepDefinitionGeneric whenOpenAggregateSollIstReportOnIndex() =>
    when<FlutterWorld>(
      'I open the aggregate Soll-Ist report on the report index',
      (context) async {
        final driver = context.world.driver!;
        final entry = find.byValueKey('reportsIndexAggregateOpen');
        await FlutterDriverUtils.tap(driver, entry);
        final overflowItem = find.byValueKey(
          'reportsIndexAggregateOpen-overflow-item',
        );
        try {
          await driver.waitFor(overflowItem, timeout: _reportsMenuTimeout);
        } on DriverError {
          return;
        }
        await FlutterDriverUtils.tap(driver, overflowItem);
      },
    );

/// Opens an episode's shooting-days list from the episodes screen's
/// context entry (`episode-shooting-days-<episodeId>`).
StepDefinitionGeneric whenOpenShootingDays() => when1<String, FlutterWorld>(
  'I open the shooting days for episode {string}',
  (String episodeId, context) async {
    final locator = find.byValueKey('episode-shooting-days-$episodeId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens one day's report FROM the report index (the row tap target
/// `report-index-day-<dayId>` — the index's single navigation affordance;
/// distinct from [whenOpenReports], which taps the day board's entry and
/// stays untouched).
StepDefinitionGeneric whenOpenReportIndexEntry() => when1<String, FlutterWorld>(
  'I open the report index entry for shooting day {string}',
  (String dayId, context) async {
    final locator = find.byValueKey('report-index-day-$dayId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens a season and enters the production hierarchy spine (spec
/// `flutter-hierarchy-navigation`; issue #610 re-homed the spine out of the
/// dissolved Planen destination).
///
/// Path: the Cast view's season-selection CTA → the season scope picker →
/// its season-management entry (the seasons overview) → the season card
/// (which sets the shell's active season from the acted-on DTO and opens
/// the production overview) → the block list.
StepDefinitionGeneric whenOpenSeason() => when1<String, FlutterWorld>(
  'I open season {string}',
  (String seasonId, context) async {
    final driver = context.world.driver!;
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('cast-pick-season-cta'),
    );
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('season-scope-manage-seasons'),
    );
    final seasonCard = find.byValueKey('season-$seasonId');
    // Off-viewport guard (same analytic budget as the costume step: the
    // dev series accumulates seasons across on-device runs, so the seeded
    // row can sit far down the list — a real gesture, never a sleep).
    await driver.scrollUntilVisible(
      find.byValueKey('seasons-list'),
      seasonCard,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await FlutterDriverUtils.tap(driver, seasonCard);
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('production-blocks-entry'),
    );
  },
);

/// Opens a block from the blocks list (`block-<id>` tile).
StepDefinitionGeneric whenOpenBlock() => when1<String, FlutterWorld>(
  'I open block {string}',
  (String blockId, context) async {
    final locator = find.byValueKey('block-$blockId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens an episode from the episodes list (`episode-<id>` tile).
StepDefinitionGeneric whenOpenEpisode() => when1<String, FlutterWorld>(
  'I open episode {string}',
  (String episodeId, context) async {
    final locator = find.byValueKey('episode-$episodeId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens a scene from the scenes list (`scene-<id>` tile → detail).
StepDefinitionGeneric whenOpenScene() => when1<String, FlutterWorld>(
  'I open scene {string}',
  (String sceneId, context) async {
    final locator = find.byValueKey('scene-$sceneId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens the shoot-day execution board from the scene detail's
/// shooting-days section (`open-day-board-<day>`).
StepDefinitionGeneric whenOpenDayBoard() => when1<String, FlutterWorld>(
  'I open the day board for shooting day {string}',
  (String dayId, context) async {
    final locator = find.byValueKey('open-day-board-$dayId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens costume assignment for a season via the shell's Cast destination
/// (issue #610: the costume surface moved out of the dissolved Kleidung
/// destination INTO the Cast view; the costume categories vocabulary lives
/// here too, never with the user settings).
///
/// Path: Cast view's season CTA → season scope picker → pick the season
/// (sets the active season, pops) → switch the Cast view to the costume
/// surface. Scenario semantics preserved; only the entry action changed.
StepDefinitionGeneric whenOpenCostumeAssignment() =>
    when1<String, FlutterWorld>(
      'I open the costume assignment for season {string}',
      (String seasonId, context) async {
        // Issue #368: the symbolic feature id maps to the seeded REAL season
        // id (AppWorld.seedIds, filled by the seeding Given step).
        final realSeason =
            (context.world as AppWorld).seedIds[seasonId] ?? seasonId;
        // The Cast view scopes to the shell's ACTIVE season, and the app
        // restarts per scenario with none set: first set the active season
        // from the season scope picker (the surface that SETS it, D5),
        // then switch the Cast view to the costume surface.
        final driver = context.world.driver!;
        await FlutterDriverUtils.tap(
          driver,
          find.byValueKey('cast-pick-season-cta'),
        );
        final scopeList = find.byValueKey('season-scope-list');
        final seasonRow = find.byValueKey('season-scope-season-$realSeason');
        // Off-viewport guard (#368 on-device run): the seeded season sorts
        // at the END of the accumulated dev series (it gets the next free,
        // hence highest, number), beyond the built window of the Planen
        // ListView.builder, so a plain finder never matches. Scroll the list
        // until the row builds into the tree (a real gesture on the real
        // read-model surface, no sleep), then tap it. Bounded worst case:
        // the dev series accumulates seasons across on-device runs (issue
        // #463), so the deepest row can sit ~6400px down; the budget covers
        // that analytic worst case deterministically (per-step -200px
        // gesture, never a sleep).
        await driver.scrollUntilVisible(
          scopeList,
          seasonRow,
          dxScroll: 0,
          dyScroll: -200,
          timeout: const Duration(seconds: 45),
        );
        await FlutterDriverUtils.tap(driver, seasonRow);
        // The Cast view's roster/costume switch — the costume surface is
        // the second segment (label „Kostüme").
        await FlutterDriverUtils.tap(driver, find.text('Kostüme'));
      },
    );
