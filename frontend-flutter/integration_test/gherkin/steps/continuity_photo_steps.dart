// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:frontend_flutter/data/photo_repository.dart'
    show kPhotoWatchMaxDelay;
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

/// Reads the in-app request recorder (issue #380) over the FlutterDriver
/// data channel: the runner and the app run in separate processes, so the
/// counts travel as a compact `total=N;photo=M` snapshot string instead of
/// shared memory. The recorder is a `@visibleForTesting` Dio interceptor
/// registered only by the instrumented app target (`gherkin/app.dart`).
Future<({int total, int photo})> _requestRecorderSnapshot(
  FlutterWorld world,
) async {
  final raw = await world.driver!.requestData(
    'request-recorder:snapshot',
    timeout: const Duration(seconds: 10),
  );
  final fields = Map<String, int>.fromEntries(
    raw
        .trim()
        .split(';')
        .map(
          (pair) => MapEntry(
            pair.split('=').first,
            int.tryParse(pair.split('=').last) ?? -1,
          ),
        ),
  );
  return (total: fields['total']!, photo: fields['photo']!);
}

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
    // HTTP is issued. Verified against the real traffic recorded by the
    // in-app Dio interceptor (issue #380): the photo-pipeline count MUST
    // be zero. Navigation read-model fetches are legitimate traffic and
    // are deliberately NOT counted — the gate prevents capture-pipeline
    // requests (upload, bytes, delete, link), not page loads.
    final world = context.world as AppWorld;
    final snapshot = await _requestRecorderSnapshot(context.world);
    world.requestsLeftDevice = snapshot.photo;
    if (world.requestsLeftDevice != 0) {
      throw Exception(
        'AUTHZ-GATE preflight failed: '
        '${world.requestsLeftDevice} photo-pipeline network request(s) left '
        'the device before the client-side authorization check.',
      );
    }
  }),
  then<FlutterWorld>('the day board shows the command denial', (context) async {
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
      // count from the read model (e.g. `Continuity (1)`), scoped to the
      // requested shoot so a sibling strip cannot satisfy the step.
      await context.world.driver!.waitFor(
        find.descendant(
          of: find.byValueKey('continuity-strip-$sceneShootId'),
          matching: find.text(count),
        ),
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
  then<FlutterWorld>('no further network requests leave the device', (
    context,
  ) async {
    // Post-budget quiescence (issue #380): polling actually STOPPED after
    // the watch budget expired — observed against the real traffic recorded
    // by the in-app Dio interceptor, not inferred from the UI.
    //
    // The window is analytic, not a jitter budget: the watch's refetch
    // backoff is capped at kPhotoWatchMaxDelay (10s), so a still-running
    // watch would issue another refetch within that bound. Two snapshots
    // `2 × kPhotoWatchMaxDelay` apart with an unchanged total count prove
    // the poll loop ended (a stopped watch never re-subscribes by itself).
    final before = await _requestRecorderSnapshot(context.world);
    await Future<void>.delayed(kPhotoWatchMaxDelay * 2);
    final after = await _requestRecorderSnapshot(context.world);
    final delta = after.total - before.total;
    if (delta != 0) {
      throw Exception(
        'post-budget quiescence failed: $delta network request(s) left the '
        'device after the watch budget expired (polling did not stop).',
      );
    }
  }),
  when<FlutterWorld>('75 seconds pass so the watch budget expires', (
    context,
  ) async {
    // The bounded watch budget (60s wall time) must elapse on device so
    // the expiry assertions observe the post-budget state. Slow by
    // design — the seed holds the variant in Processing throughout.
    await Future<void>.delayed(const Duration(seconds: 75));
  }),
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
  then1<String, FlutterWorld>('the capture affordance for {string} remains', (
    String sceneShootId,
    context,
  ) async {
    // Recovery affordance: capture-again stays available after expiry
    // (no destructive state, manual refresh via pull-to-refresh).
    final locator = find.byValueKey('continuity-capture-camera-$sceneShootId');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
];
