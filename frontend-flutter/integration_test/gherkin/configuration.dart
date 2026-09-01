// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'dart:io';

import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import 'hooks/app_hook.dart';
import 'steps/common_steps.dart';
import 'steps/continuity_photo_steps.dart';
import 'steps/costume_assignment_steps.dart';
import 'steps/soll_ist_report_steps.dart';
import 'world/app_world.dart';

/// Builds the on-device `flutter_gherkin` configuration for the critical
/// acceptance scenarios under `features-spec/`.
///
/// The runner launches the instrumented app (`app.dart`) in **dev-auth mode**
/// (`DEV_AUTH_SUB=dev-e2e`, `API_BASE=http://10.0.2.2:3000`) on a connected
/// device/emulator. The three critical flows (`@critical`) are tagged
/// `@pending` because their screens are not yet landed; `tagExpression` is
/// `not @pending`, so the default on-device pass runs only `smoke.feature`.
/// Removing `@pending` from a scenario promotes it into the on-device pass
/// (the CI gate in `.github/workflows/flutter-ci.yml`).
Future<FlutterTestConfiguration> buildGherkinConfig() async {
  final steps = <StepDefinitionGeneric>[
    givenAppLaunched(),
    givenAuthenticatedAs(),
    whenOpenSollIstReport(),
    whenOpenContinuityPhoto(),
    whenOpenCostumeAssignment(),
    ...sollIstReportSteps(),
    ...continuityPhotoSteps(),
    ...costumeAssignmentSteps(),
  ];

  return FlutterTestConfiguration.DEFAULT(
      steps,
      featurePath: 'features-spec/*.feature',
      targetAppPath: 'integration_test/gherkin/app.dart',
    )
    ..targetAppWorkingDirectory = '.'
    ..hooks = [AppHook()]
    ..tagExpression = 'not @pending'
    ..restartAppBetweenScenarios = true
    ..logFlutterProcessOutput = true
    ..verboseFlutterProcessLogs = false
    // Both values are configurable from the run environment so the suite is
    // not bound to the Android-emulator host alias. `tool/run_gherkin.sh`
    // exports API_BASE / DEV_AUTH_SUB (defaulting to the emulator URL and the
    // dev dummy principal); a physical device or other target supplies a
    // network-reachable API endpoint via the same variables.
    ..dartDefineArgs = [
      'DEV_AUTH_SUB=${Platform.environment['DEV_AUTH_SUB'] ?? 'dev-e2e'}',
      'API_BASE=${Platform.environment['API_BASE'] ?? 'http://10.0.2.2:3000'}',
    ]
    // Build the per-scenario world as an AppWorld so step definitions can
    // carry auth-role / network-recorder context without any pure-function
    // logic. The runner still wires the FlutterDriver onto it.
    ..createWorld = (TestConfiguration config) async => AppWorld();
}
