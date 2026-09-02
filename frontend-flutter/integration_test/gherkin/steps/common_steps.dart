// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

/// The runner launches the instrumented app before each scenario. We assert
/// the home screen rendered on device — an on-device assertion, not a
/// pure-function check.
StepDefinitionGeneric givenAppLaunched() => given<FlutterWorld>(
  'the app is launched in dev-auth mode',
  (context) async {
    await context.world.driver!.waitFor(
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

/// Opens the Soll-Ist report for a season (forward-looking — the screen is not
/// yet landed; the key convention follows the seasons reference pattern).
StepDefinitionGeneric whenOpenSollIstReport() => when1<String, FlutterWorld>(
  'I open the Soll-Ist report for season {string}',
  (String seasonId, context) async {
    // TODO(screen): tap the report affordance once the Soll-Ist report
    // screen ships; it should expose `Key('open-soll-ist-report-$seasonId')`.
    final locator = find.byValueKey('open-soll-ist-report-$seasonId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens continuity photo capture for a scene shoot (forward-looking).
StepDefinitionGeneric whenOpenContinuityPhoto() => when1<String, FlutterWorld>(
  'I open the continuity photo capture for scene shoot {string}',
  (String sceneShootId, context) async {
    // TODO(screen): tap the capture affordance once the photo screen ships.
    final locator = find.byValueKey('open-continuity-photo-$sceneShootId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  },
);

/// Opens costume assignment for a season (forward-looking).
StepDefinitionGeneric whenOpenCostumeAssignment() =>
    when1<String, FlutterWorld>(
      'I open the costume assignment for season {string}',
      (String seasonId, context) async {
        // TODO(screen): tap the assignment affordance once the screen ships.
        final locator = find.byValueKey('open-costume-assignment-$seasonId');
        await FlutterDriverUtils.tap(context.world.driver!, locator);
      },
    );
