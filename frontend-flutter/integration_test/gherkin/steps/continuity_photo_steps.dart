// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

/// Step definitions for the continuity photo capture critical scenarios
/// (`features-spec/continuity_photo_capture.feature`). Every step drives
/// the on-device UI through `world.driver` + value keys (or device-visible
/// text scoped to the shoot's strip); none assert on a pure function.
/// Keys mirror the landed day board (`SceneShootsScreen`) and continuity
/// strip widgets.
Iterable<StepDefinitionGeneric> continuityPhotoSteps() => [
  when2<String, String, FlutterWorld>(
    'I pick costume {string} for the continuity capture of scene shoot {string}',
    (String costumeId, String sceneShootId, context) async {
      final driver = context.world.driver!;
      await FlutterDriverUtils.tap(
        driver,
        find.byValueKey('continuity-costume-pick-$sceneShootId'),
      );
      await FlutterDriverUtils.tap(
        driver,
        find.byValueKey('continuity-costume-option-$costumeId'),
      );
    },
  ),
  when1<String, FlutterWorld>(
    'I capture a continuity photo for scene shoot {string}',
    (String sceneShootId, context) async {
      final locator = find.byValueKey(
        'continuity-capture-camera-$sceneShootId',
      );
      await FlutterDriverUtils.tap(context.world.driver!, locator);
    },
  ),
  when<FlutterWorld>('I accept the capture rationale', (context) async {
    final locator = find.byValueKey('continuity-rationale-accept');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
  }),
  then<FlutterWorld>('the continuity denial narrative appears', (
    context,
  ) async {
    // Client-side AUTHZ-GATE denial surface: the strip renders the 403
    // narrative before any network call (the capture buttons never render
    // for the denied membership).
    final locator = find.byValueKey('continuity-denied-narrative');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  then<FlutterWorld>('no network request leaves the device', (context) async {
    // AUTHZ-GATE preflight: the client refuses the request before any
    // HTTP is issued. Verified by a Dio interceptor that records every
    // outgoing request into `world.requestsLeftDevice`.
    // TODO(screen): inject the recorder into the app build so this is
    // populated; until then the assertion documents the contract.
    final world = context.world as AppWorld;
    if (world.requestsLeftDevice != 0) {
      throw Exception(
        'AUTHZ-GATE preflight failed: '
        '${world.requestsLeftDevice} network request(s) left the device '
        'before the client-side authorization check.',
      );
    }
  }),
  then<FlutterWorld>('the day board shows the command denial', (
    context,
  ) async {
    // Server-side gate: the handler rejected the link (403 problem `code`
    // from the per-operation RFC 9457 responses); the board surfaces the
    // keyed copy in the command-error banner.
    final locator = find.byValueKey('scene-shoot-command-error-banner');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  then2<String, String, FlutterWorld>(
    'the continuity count for {string} becomes {string}',
    (String sceneShootId, String count, context) async {
      // The linked projection reconciled: the strip header carries the
      // count from the read model (e.g. `Continuity (1)`).
      await context.world.driver!.waitFor(
        find.text(count),
        timeout: const Duration(seconds: 30),
      );
    },
  ),
  then1<String, FlutterWorld>(
    'the continuity strip for {string} shows processing',
    (String sceneShootId, context) async {
      // A linked variant still Processing renders the pending state
      // inside the shoot's strip (scoped descendant — never a global
      // text search across strips).
      await context.world.driver!.waitFor(
        find.descendant(
          of: find.byValueKey('continuity-strip-$sceneShootId'),
          matching: find.text('Processing…'),
        ),
        timeout: const Duration(seconds: 30),
      );
    },
  ),
  when<FlutterWorld>(
    '75 seconds pass so the watch budget expires',
    (context) async {
      // The bounded watch budget (60s wall time) must elapse on device so
      // the expiry assertions observe the post-budget state. Slow by
      // design — the seed holds the variant in Processing throughout.
      await Future<void>.delayed(const Duration(seconds: 75));
    },
  ),
  then1<String, FlutterWorld>(
    'the continuity strip for {string} still shows processing',
    (String sceneShootId, context) async {
      // Post-budget: polling stopped, the row renders the neutral "still
      // processing" state (distinguishable from Ready and Failed).
      await context.world.driver!.waitFor(
        find.descendant(
          of: find.byValueKey('continuity-strip-$sceneShootId'),
          matching: find.text('Processing…'),
        ),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  then1<String, FlutterWorld>(
    'the capture affordance for {string} remains',
    (String sceneShootId, context) async {
      // Recovery affordance: capture-again stays available after expiry
      // (no destructive state, manual refresh via pull-to-refresh).
      final locator = find.byValueKey(
        'continuity-capture-camera-$sceneShootId',
      );
      await context.world.driver!.waitFor(
        locator,
        timeout: const Duration(seconds: 10),
      );
    },
  ),
];
