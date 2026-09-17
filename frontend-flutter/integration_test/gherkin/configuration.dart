// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'dart:io';

import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import 'hooks/app_hook.dart';
import 'steps/common_steps.dart';
import 'steps/continuity_photo_steps.dart';
import 'steps/costume_assignment_steps.dart';
import 'steps/season_wizard_steps.dart';
import 'steps/soll_ist_execution_steps.dart';
import 'steps/soll_ist_report_steps.dart';
import 'world/app_world.dart';

/// Builds the on-device `flutter_gherkin` configuration for the critical
/// acceptance scenarios under `features-spec/`.
///
/// The runner launches the instrumented app (`app.dart`) in **dev-auth mode**
/// (`DEV_AUTH_SUB=dev-e2e`, `API_BASE=http://10.0.2.2:3000`) on a connected
/// device/emulator. Critical flows (`@critical`) still tagged `@pending`
/// (Soll-Ist report and execution — own changes) are excluded
/// via `tagExpression: not @pending`; promoted scenarios (costume
/// assignment, shipped with `flutter-costume-domains`; continuity photo
/// capture, shipped with `flutter-shoot-day-execution`) run on device.
/// Removing `@pending` from a scenario promotes it into the on-device pass
/// (the CI gate in `.github/workflows/flutter-ci.yml`).
Future<FlutterTestConfiguration> buildGherkinConfig() async {
  final steps = <StepDefinitionGeneric>[
    givenAppLaunched(),
    givenAuthenticatedAs(),
    whenOpenSeason(),
    whenOpenBlock(),
    whenOpenEpisode(),
    whenOpenScene(),
    whenOpenDayBoard(),
    whenOpenReports(),
    whenOpenSollIstReport(),
    whenOpenCostumeAssignment(),
    ...sollIstReportSteps(),
    ...sollIstExecutionSteps(),
    ...continuityPhotoSteps(),
    ...costumeAssignmentSteps(),
    ...seasonWizardSteps(),
  ];

  return FlutterTestConfiguration.DEFAULT(
      steps,
      // The gherkin core matches this pattern as a REGEX against the FULL
      // relative path (matchAsPrefix + group(0) == path), so it must
      // express a real glob: any file directly/anywhere under features-spec/
      // ending in `.feature`. (A literal `features-spec/*.feature` would
      // never match — the `*` would quantify the `/`, yielding 0 scenarios.)
      featurePath: 'features-spec/.*\\.feature',
      targetAppPath: 'integration_test/gherkin/app.dart',
    )
    ..targetAppWorkingDirectory = '.'
    // Gradle dev/prod product flavors (change add-android-release-workflow):
    // the on-device suite runs the dev variant — the runner must pass
    // `--flavor dev`, because plain `assembleDebug` no longer exists once
    // flavorDimensions are declared.
    ..buildFlavor = 'dev'
    ..hooks = [AppHook()]
    ..tagExpression = 'not @pending'
    ..restartAppBetweenScenarios = true
    // Per-step timeout must exceed the app-launch step's own 30s
    // `seasons-list` wait (cold emulator starts need it); the gherkin
    // core default is 10s, which deterministically times out the first
    // scenario's Given on a cold instrumented start.
    ..defaultTimeout = const Duration(seconds: 45)
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
      // The wizard + quick-create sheet source their `series_id` from the
      // env (`--dart-define=DEFAULT_SERIES_ID`, never hardcoded — AGENTS.md
      // §5). Without it the dispatch POST /v1/seasons fails 422 and the
      // happy-path scenario lands on the partial-failure surface
      // (discovered by the #368 on-device run). Default to the dev series
      // the seeding + wizard scenarios use.
      'DEFAULT_SERIES_ID=${Platform.environment['DEFAULT_SERIES_ID'] ?? '11111111-1111-1111-1111-111111111111'}',
    ]
    // Build the per-scenario world as an AppWorld so step definitions can
    // carry auth-role / network-recorder context without any pure-function
    // logic. The runner still wires the FlutterDriver onto it.
    ..createWorld = (TestConfiguration config) async => AppWorld();
}
