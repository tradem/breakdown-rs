// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

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

/// Records the asserted caller role for downstream AUTHZ-GATE assertions. The
/// authoritative membership/capabilities are still derived server-side; this
/// only carries intent. Runs on device, does not call a pure function.
StepDefinitionGeneric givenAuthenticatedAs() => given1<String, FlutterWorld>(
  'I am authenticated as a {string} user',
  (String role, context) async {
    final world = context.world as AppWorld;
    world.currentRole = role;
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
        // Navigate to the Kleidung tab (labeled destination).
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
