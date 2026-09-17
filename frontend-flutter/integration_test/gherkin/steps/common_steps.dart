// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

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
StepDefinitionGeneric whenOpenReports() => when1<String, FlutterWorld>(
  'I open the reports for shooting day {string}',
  (String dayId, context) async {
    final locator = find.byValueKey('reports-open');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Legacy season-level entry (kept for step-registry completeness; the
/// `soll_ist_report.feature` scenarios use the day-context entry above
/// since `flutter-reports` 2.1).
StepDefinitionGeneric whenOpenSollIstReport() => when1<String, FlutterWorld>(
  'I open the Soll-Ist report for season {string}',
  (String seasonId, context) async {
    // TODO(screen): tap the report affordance once the Soll-Ist report
    // screen ships; it should expose `Key('open-soll-ist-report-$seasonId')`.
    final locator = find.byValueKey('open-soll-ist-report-$seasonId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens a season from the seasons list (`season-<id>` tile).
StepDefinitionGeneric whenOpenSeason() => when1<String, FlutterWorld>(
  'I open season {string}',
  (String seasonId, context) async {
    // Hierarchy spine via the shell's Planen tab (spec
    // `flutter-hierarchy-navigation`: hierarchy pushes operate on the
    // Planen tab's nested navigator): tap the Planen destination, then the
    // season row (which also sets the shell's active season).
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('shell-destination-1'),
    );
    final locator = find.byValueKey('planen-season-$seasonId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
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

/// Opens costume assignment for a season via the shell's Kleidung tab
/// (`redesign-app-shell-navigation` task 5.5 — the season-row icon buttons
/// are gone; the costume stream is a first-class tab destination now):
/// tap the Kleidung destination, then the season-scoped "Kostüme" entry.
/// Scenario semantics preserved; only the entry action changed.
StepDefinitionGeneric whenOpenCostumeAssignment() =>
    when1<String, FlutterWorld>(
      'I open the costume assignment for season {string}',
      (String seasonId, context) async {
        // Issue #368: the symbolic feature id maps to the seeded REAL season
        // id (AppWorld.seedIds, filled by the seeding Given step).
        final realSeason =
            (context.world as AppWorld).seedIds[seasonId] ?? seasonId;
        // The Kleidung tab scopes to the shell's ACTIVE season, and the app
        // restarts per scenario with none set: first set the active season
        // from the Planen tab's season row (the surface that SETS it, D5),
        // then switch to the Kleidung tab and open the costumes entry.
        await FlutterDriverUtils.tap(
          context.world.driver!,
          find.byValueKey('shell-destination-1'),
        );
        final planenList = find.byValueKey('planen-list');
        final seasonRow = find.byValueKey('planen-season-$realSeason');
        // Off-viewport guard (#368 on-device run): the seeded season sorts
        // mid-list of the accumulated dev series — beyond the built window
        // of the Planen ListView.builder, so a plain finder never matches.
        // Scroll the list until the row builds into the tree (a real
        // gesture on the real read-model surface, no sleep), then tap it.
        await context.world.driver!.scrollUntilVisible(
          planenList,
          seasonRow,
          dxScroll: 0,
          dyScroll: -200,
          timeout: const Duration(seconds: 15),
        );
        await FlutterDriverUtils.tap(context.world.driver!, seasonRow);
        await FlutterDriverUtils.tap(
          context.world.driver!,
          find.byValueKey('shell-destination-2'),
        );
        // The season-scoped costumes entry (Kleidung tab root).
        await FlutterDriverUtils.tap(
          context.world.driver!,
          find.byValueKey('kleidung-costumes-entry'),
        );
      },
    );
