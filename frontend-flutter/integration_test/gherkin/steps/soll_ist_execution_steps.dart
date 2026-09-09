// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3 (opencode)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

/// Step definitions for the Soll-Ist execution critical scenarios
/// (`features-spec/soll_ist_execution.feature`). Every step drives the
/// on-device day board through `world.driver` + value keys (or
/// device-visible read-model copy); none assert on a pure function.
/// Keys mirror the landed board (`SceneShootsScreen`).
Iterable<StepDefinitionGeneric> sollIstExecutionSteps() => [
  when<FlutterWorld>('I plan the first shoot', (context) async {
    // Empty-board plan affordance: plans for the entry scene with an
    // appended planned-order key (day/scene travel in the path only).
    final locator = find.byValueKey('scene-shoots-plan-first');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  }),
  then1<String, FlutterWorld>('the board shows a {string} shoot', (
    String status,
    context,
  ) async {
    // The status chip renders the projection's status verbatim.
    await context.world.driver!.waitFor(
      find.text(status),
      timeout: const Duration(seconds: 10),
    );
  }),
  when1<String, FlutterWorld>('I start scene shoot {string}', (
    String sceneShootId,
    context,
  ) async {
    final locator = find.byValueKey('scene-shoot-start-$sceneShootId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  }),
  when2<String, String, FlutterWorld>(
    'I set the actual order of scene shoot {string} to {string}',
    (String sceneShootId, String orderKey, context) async {
      // Explicit key editing (no hidden reorder magic): menu → dialog →
      // typed key → save dispatches the version-echoed command.
      final driver = context.world.driver!;
      await FlutterDriverUtils.tap(
        driver,
        find.byValueKey('scene-shoot-menu-$sceneShootId'),
      );
      await FlutterDriverUtils.tap(
        driver,
        find.byValueKey('scene-shoot-actual-order-$sceneShootId'),
      );
      await driver.tap(find.byValueKey('order-key-field'));
      await driver.enterText(orderKey);
      await FlutterDriverUtils.tap(driver, find.byValueKey('order-key-save'));
    },
  ),
  then1<String, FlutterWorld>('the board settles for scene shoot {string}', (
    String sceneShootId,
    context,
  ) async {
    // Projection boundary: the optimistic overlay (pending spinner)
    // clears only once the read model carries the acknowledged
    // version — later assertions observe the projection, never the
    // overlay. Rejected commands add no overlay, so they cannot
    // satisfy the status assertions that follow.
    await context.world.driver!.waitForAbsent(
      find.byValueKey('scene-shoot-pending-$sceneShootId'),
      timeout: const Duration(seconds: 30),
    );
  }),
  then2<String, String, FlutterWorld>(
    'the order of scene shoot {string} reads {string}',
    (String sceneShootId, String order, context) async {
      // The Ist strip renders actual vs planned from the read model.
      await context.world.driver!.waitFor(
        find.text(order),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  when1<String, FlutterWorld>('I finish scene shoot {string}', (
    String sceneShootId,
    context,
  ) async {
    final locator = find.byValueKey('scene-shoot-finish-$sceneShootId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  }),
  when1<String, FlutterWorld>('I skip scene shoot {string}', (
    String sceneShootId,
    context,
  ) async {
    final locator = find.byValueKey('scene-shoot-skip-$sceneShootId');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  }),
  when<FlutterWorld>('I wrap the shooting day', (context) async {
    // Guarded day-level action: the confirm dialog names the consequence
    // and the absence of an undo before dispatching.
    final driver = context.world.driver!;
    await FlutterDriverUtils.tap(driver, find.byValueKey('scene-shoots-wrap'));
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('wrap-confirm-button'),
    );
  }),
  then<FlutterWorld>('the day board shows finality', (context) async {
    final locator = find.byValueKey('scene-shoots-wrapped-banner');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  then1<String, FlutterWorld>('no actions remain for scene shoot {string}', (
    String sceneShootId,
    context,
  ) async {
    // Wrapped days are immutable for execution: every mutable control
    // is absent (not merely disabled) — start, finish, skip, and the
    // order menu alike.
    final driver = context.world.driver!;
    for (final key in [
      'scene-shoot-start-$sceneShootId',
      'scene-shoot-finish-$sceneShootId',
      'scene-shoot-skip-$sceneShootId',
      'scene-shoot-menu-$sceneShootId',
    ]) {
      await driver.waitForAbsent(
        find.byValueKey(key),
        timeout: const Duration(seconds: 10),
      );
    }
  }),
];
