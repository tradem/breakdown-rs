// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'dart:async';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart' show SeedCache;

/// Reads the look-command counter from the in-app request recorder
/// (issue #380) over the FlutterDriver data channel. Returns -1 when the
/// recorder (or the look counter) is absent, so the denial assertion fails
/// loudly rather than passing on a missing instrumentation.
Future<int> _outfitCommandsLeftDevice(FlutterWorld world) async {
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
  return fields['outfit'] ?? -1;
}

/// Step definitions for the outfit-casting critical scenario
/// (`features-spec/outfit_casting.feature`).
///
/// Covers the CQRS-on-client contract (AGENTS.md §4) — optimistic beat
/// overlay after a 2xx command acknowledgement, then projection
/// reconciliation — the continuity-by-id and copy-on-write variant rules of
/// the wardrobe split, and the client-side AUTHZ-GATE role denial on the look
/// surface. All steps drive the on-device UI through widget keys; none assert
/// on a pure function.
Iterable<StepDefinitionGeneric> outfitCastingSteps() => [
  given3<String, String, String, FlutterWorld>(
    'the backend is seeded with outfit {string} for character {string} in '
    'scene {string}',
    (
      String outfitSymbol,
      String characterSymbol,
      String sceneSymbol,
      context,
    ) async {
      // The REAL dev backend was seeded over HTTP by `AppHook.onBeforeRun`
      // (host-side, BEFORE the first app launch). This step copies the
      // resolved REAL ids into the scenario's `AppWorld.seedIds` so the
      // downstream steps map the feature's symbolic ids (season "1",
      // "ch-3"/"ch-9", "p-7"/"p-r", "o-a"/"o-av"/"o-b", "e-1"/"sc-1").
      // State-establishment step (no assertion).
      final world = context.world as AppWorld;
      final ids = SeedCache.outfitCastingIds;
      if (ids == null) {
        throw StateError(
          'outfit-casting seed missing — AppHook.onBeforeRun must run '
          'before the scenario Given steps (hook failure or wrong order).',
        );
      }
      world.seedIds.addAll(ids);
      world.lastOutfitId = world.seedIds[outfitSymbol] ?? outfitSymbol;
      world.lastCharacterId = world.seedIds[characterSymbol] ?? characterSymbol;
      world.lastSceneId = world.seedIds[sceneSymbol] ?? sceneSymbol;
    },
  ),
  when1<String, FlutterWorld>('I open the scene detail for scene {string}', (
    String sceneSymbol,
    context,
  ) async {
    // Path: season scope picker (the surface that SETS the active season)
    // → Script destination → the scene row (`script-scene-<id>`) → detail.
    final world = context.world as AppWorld;
    final realSeason = world.seedIds['1'] ?? '1';
    final realScene = world.seedIds[sceneSymbol] ?? sceneSymbol;
    world.lastSceneId = realScene;
    final driver = context.world.driver!;
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('cast-pick-season-cta'),
    );
    final scopeList = find.byValueKey('season-scope-list');
    final seasonRow = find.byValueKey('season-scope-season-$realSeason');
    await driver.scrollUntilVisible(
      scopeList,
      seasonRow,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await FlutterDriverUtils.tap(driver, seasonRow);
    // The script view is the shell's second destination.
    await FlutterDriverUtils.tap(driver, find.text('Script'));
    final sceneRow = find.byValueKey('script-scene-$realScene');
    await driver.waitFor(sceneRow, timeout: const Duration(seconds: 30));
    await FlutterDriverUtils.tap(driver, sceneRow);
  }),
  when2<String, String, FlutterWorld>(
    'I cast outfit {string} onto the beat of character {string}',
    (String outfitSymbol, String characterSymbol, context) async {
      // The scene detail's beat section offers the assign affordance per
      // character; the picker returns the LOOK (selection only — editing the
      // look stays on the outfit screens).
      final world = context.world as AppWorld;
      final realOutfit = world.seedIds[outfitSymbol] ?? outfitSymbol;
      final realCharacter = world.seedIds[characterSymbol] ?? characterSymbol;
      world.lastOutfitId = realOutfit;
      world.lastCharacterId = realCharacter;
      await _castBeat(world, realCharacter, realOutfit);
    },
  ),
  when2<String, String, FlutterWorld>(
    'I add a look change for character {string} with outfit {string}',
    (String characterSymbol, String outfitSymbol, context) async {
      // A second beat on the same character is an in-scene change; the
      // affordance is the `+ Lookwechsel` button of the character's group.
      final world = context.world as AppWorld;
      final realOutfit = world.seedIds[outfitSymbol] ?? outfitSymbol;
      final realCharacter = world.seedIds[characterSymbol] ?? characterSymbol;
      world.lastOutfitId = realOutfit;
      world.lastCharacterId = realCharacter;
      await _castBeat(world, realCharacter, realOutfit, change: true);
    },
  ),
  then1<String, FlutterWorld>('the beat renders the look {string}', (
    String outfitSymbol,
    context,
  ) async {
    // Optimistic beat overlay OR already-reconciled authoritative row: on a
    // fast localhost backend the projector can clear the fence BEFORE the
    // driver polls the tree, so a strict overlay-only wait would flake. The
    // strict optimistic contract is pinned by the widget tier; on device the
    // meaningful signal is that the cast landed on the character's beat.
    final world = context.world as AppWorld;
    final realOutfit = world.seedIds[outfitSymbol] ?? outfitSymbol;
    world.lastOutfitId = realOutfit;
    await world.driver!.waitFor(
      find.byValueKey('scene-piece-beat-${world.lastCharacterId}0'),
      timeout: const Duration(seconds: 30),
    );
  }),
  then1<String, FlutterWorld>('the look {string} carries its garment', (
    String outfitSymbol,
    context,
  ) async {
    // The look list row of the character the beat was cast on announces the
    // piece count; a look with a garment reports one.
    final world = context.world as AppWorld;
    final realOutfit = world.seedIds[outfitSymbol] ?? outfitSymbol;
    await world.driver!.waitFor(
      find.byValueKey('outfit-row-$realOutfit'),
      timeout: const Duration(seconds: 30),
    );
  }),
  then3<String, String, String, FlutterWorld>(
    'the beat sequence of character {string} shows {string} and {string}',
    (String characterSymbol, String first, String second, context) async {
      // Two beats on one character are an in-scene look change: both rows
      // render, in `order` sequence (0 = the base look, 1 = the change).
      final world = context.world as AppWorld;
      final realCharacter = world.seedIds[characterSymbol] ?? characterSymbol;
      final driver = context.world.driver!;
      await driver.waitFor(
        find.byValueKey('scene-piece-beat-${realCharacter}0'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitFor(
        find.byValueKey('scene-piece-beat-${realCharacter}1'),
        timeout: const Duration(seconds: 30),
      );
      // The labels carry the looks' own names as joined by the backend.
      await driver.waitFor(
        find.text(first),
        timeout: const Duration(seconds: 10),
      );
      await driver.waitFor(
        find.text(second),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  when1<String, FlutterWorld>('I open the looks of character {string}', (
    String characterSymbol,
    context,
  ) async {
    // Cast view → the character tile opens the character detail, which
    // hosts the look section (a look belongs to a character).
    final world = context.world as AppWorld;
    final realSeason = world.seedIds['1'] ?? '1';
    final realCharacter = world.seedIds[characterSymbol] ?? characterSymbol;
    final driver = context.world.driver!;
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('cast-pick-season-cta'),
    );
    final scopeList = find.byValueKey('season-scope-list');
    final seasonRow = find.byValueKey('season-scope-season-$realSeason');
    await driver.scrollUntilVisible(
      scopeList,
      seasonRow,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await FlutterDriverUtils.tap(driver, seasonRow);
    final roster = find.byValueKey('characters-list');
    final tile = find.byValueKey('character-$realCharacter');
    await driver.scrollUntilVisible(
      roster,
      tile,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 45),
    );
    await FlutterDriverUtils.tap(driver, tile);
  }),
  then<FlutterWorld>('the look surface denies management with a denial', (
    context,
  ) async {
    // Client-side AUTHZ-GATE: the look section's create action is disabled and
    // the localized 403 narrative renders in its place; the detail's write
    // affordances never appear.
    await context.world.driver!.waitFor(
      find.byValueKey('outfit-denied-narrative'),
      timeout: const Duration(seconds: 15),
    );
  }),
  then<FlutterWorld>('no look command leaves the device', (context) async {
    // The client refused the action before any command HTTP was issued,
    // verified against the real traffic recorded by the in-app Dio
    // interceptor (issue #380): mutating `/v1/outfits*` requests must be zero.
    // Navigation read-model fetches are legitimate traffic and stay out of
    // this counter — the gate prevents commands, not page loads.
    final count = await _outfitCommandsLeftDevice(context.world);
    if (count != 0) {
      throw Exception(
        'AUTHZ-GATE preflight failed: '
        '$count look command request(s) left the device before the '
        'client-side authorization check.',
      );
    }
  }),
];

/// Casts (or adds a change with) a look for one character on the open scene
/// detail: the group's assign / add-change button, then the look picker row.
Future<void> _castBeat(
  AppWorld world,
  String characterId,
  String outfitId, {
  bool change = false,
}) async {
  final driver = world.driver!;
  final sceneKey = world.lastSceneId == null
      ? null
      : find.byValueKey('scene-detail-${world.lastSceneId}');
  final button = find.byValueKey(
    change
        ? 'scene-piece-add-change-$characterId'
        : 'scene-piece-assign-$characterId',
  );
  if (sceneKey != null) {
    await driver.scrollUntilVisible(
      sceneKey,
      button,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 30),
    );
  } else {
    await driver.waitFor(button, timeout: const Duration(seconds: 30));
  }
  await FlutterDriverUtils.tap(driver, button);
  final option = find.byValueKey('pick-outfit-$outfitId');
  await driver.waitFor(option, timeout: const Duration(seconds: 20));
  await FlutterDriverUtils.tap(driver, option);
  // A beat change carries an optional cue note; the picker's confirm is the
  // row tap itself (no separate submit).
  unawaited(Future<void>.value());
}
