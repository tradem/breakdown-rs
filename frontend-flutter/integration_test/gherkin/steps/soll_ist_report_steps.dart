// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

/// Step definitions for the Soll-Ist report critical scenario
/// (`features-spec/soll_ist_report.feature`). Every step drives the on-device
/// UI through `world.driver` — none assert on a pure function.
Iterable<StepDefinitionGeneric> sollIstReportSteps() => [
  then2<int, int, FlutterWorld>(
    'the Soll-Ist report shows planned {int} scenes and actual {int} scenes',
    (int planned, int actual, context) async {
      // Assert the rendered planned/actual counts, not merely that the
      // keyed widgets exist: read the actual text and compare with the
      // scenario's expected values (the screen exposes static keys
      // `soll-ist-planned` / `soll-ist-actual`).
      final plannedText = await context.world.driver!.getText(
        find.byValueKey('soll-ist-planned'),
        timeout: const Duration(seconds: 10),
      );
      final actualText = await context.world.driver!.getText(
        find.byValueKey('soll-ist-actual'),
        timeout: const Duration(seconds: 10),
      );
      final plannedValue = int.tryParse(plannedText.trim());
      final actualValue = int.tryParse(actualText.trim());
      if (plannedValue != planned) {
        throw Exception(
          'Soll-Ist planned count mismatch: expected $planned, '
          'got $plannedValue (rendered: "$plannedText")',
        );
      }
      if (actualValue != actual) {
        throw Exception(
          'Soll-Ist actual count mismatch: expected $actual, '
          'got $actualValue (rendered: "$actualText")',
        );
      }
    },
  ),
  then1<String, FlutterWorld>('the Soll-Ist report lists a {string} scene', (
    String flag,
    context,
  ) async {
    // TODO(screen): assert a row tagged with the moved/missing/skipped/
    // reshot flag is present (key `soll-ist-flag-$flag`).
    final locator = find.byValueKey('soll-ist-flag-$flag');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  then<FlutterWorld>('the Soll-Ist report is marked final', (context) async {
    // TODO(screen): assert the `final` badge derived from `wrapped_at`
    // is present (key `soll-ist-final`).
    final locator = find.byValueKey('soll-ist-final');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
];
