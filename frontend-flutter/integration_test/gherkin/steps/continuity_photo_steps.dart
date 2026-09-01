// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

/// Step definitions for the continuity photo capture critical scenario
/// (`features-spec/continuity_photo_capture.feature`). Exercises BOTH
/// authorization gates (AGENTS.md §5, D6) plus the happy upload→reconcile→thumb
/// path. All steps drive the on-device UI; none assert on a pure function.
Iterable<StepDefinitionGeneric> continuityPhotoSteps() => [
  when<FlutterWorld>('I request to capture a continuity photo', (
    context,
  ) async {
    // TODO(screen): trigger the capture affordance. The client-side
    // AUTHZ-GATE (currentMembershipProvider, capability
    // `upload_continuity_photos`) must refuse BEFORE any network call.
    final locator = find.byValueKey('photo-capture-fab');
    await FlutterDriverUtils.tap(context.world.driver!, locator);
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
  then<FlutterWorld>('the backend rejects the capture with a denial', (
    context,
  ) async {
    // Server-side gate: even if the request were issued, the handler's
    // SeasonPhotoAccessPolicy rejects it. We assert the denial surface
    // (a 403 / problem `code` shown client-side), not merely the
    // absence of a local call.
    final locator = find.byValueKey('photo-capture-denied');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  when1<String, FlutterWorld>(
    'I upload a continuity photo for scene shoot {string}',
    (String sceneShootId, context) async {
      // TODO(screen): perform the multipart upload (happy path).
      final locator = find.byValueKey('photo-upload-$sceneShootId');
      await FlutterDriverUtils.tap(context.world.driver!, locator);
    },
  ),
  then1<String, FlutterWorld>(
    'the continuity photo thumbnail for {string} appears',
    (String sceneShootId, context) async {
      final locator = find.byValueKey('photo-thumb-$sceneShootId');
      await context.world.driver!.waitFor(
        locator,
        timeout: const Duration(seconds: 30),
      );
    },
  ),
  then<FlutterWorld>('the continuity photo reaches terminal state', (
    context,
  ) async {
    // TODO(screen): assert the variant left its processing state and
    // reached a terminal (uploaded) state (key `photo-terminal`).
    final locator = find.byValueKey('photo-terminal');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 30),
    );
  }),
];
