// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart' show SeedCache;

/// Reads the costume-command counter from the in-app request recorder
/// (issue #380) over the FlutterDriver data channel. The runner and the app
/// run in separate processes, so the snapshot travels as a `;`-separated
/// key=value string. Returns -1 when the recorder (or the costume counter)
/// is absent, so the denial assertion fails loudly rather than passing on a
/// missing instrumentation.
Future<int> _costumeCommandsLeftDevice(FlutterWorld world) async {
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
  return fields['costume'] ?? -1;
}

/// Step definitions for the costume assignment critical scenario
/// (`features-spec/costume_assignment.feature`). Covers the CQRS-on-client
/// contract (AGENTS.md §4): optimistic overlay after a 2xx command
/// acknowledgement, then projection reconciliation; plus the client-side
/// AUTHZ-GATE role denial on the costume stream. All steps drive the on-device
/// UI through widget keys; none assert on a pure function.
Iterable<StepDefinitionGeneric> costumeAssignmentSteps() => [
  given3<String, String, String, FlutterWorld>(
    'the backend is seeded with costume {string} and character {string} for '
    'season {string}',
    (
      String costumeSymbol,
      String characterSymbol,
      String seasonSymbol,
      context,
    ) async {
      // Issue #368: the REAL dev backend was seeded over HTTP by
      // `AppHook.onBeforeRun` (host-side, BEFORE the first app launch —
      // seed_http.dart has the flow and the real-backend contract
      // discovery notes). This step copies the resolved REAL ids into the
      // scenario's `AppWorld.seedIds` so downstream steps map the feature's
      // symbolic ids (season "1", "ch-3", "ch-9", "c-7", and the
      // reassignment-dedicated "c-r", issue #454) to backend aggregates.
      // State-establishment step (no assertion) — runs on device with the
      // harness, not a pure-function check.
      final world = context.world as AppWorld;
      final ids = SeedCache.costumeAssignmentIds;
      if (ids == null) {
        throw StateError(
          'costume-assignment seed missing — AppHook.onBeforeRun must run '
          'before the scenario Given steps (hook failure or wrong order).',
        );
      }
      world.seedIds.addAll(ids);
    },
  ),
  when1<String, FlutterWorld>(
    'I view the costume {string} in the costume stream',
    (String costumeId, context) async {
      // Opens the costume DETAIL from the stream row (shared with the
      // assign step). Used by the viewer-denial scenario: for a denied
      // membership the assign button never renders (the client-side
      // AUTHZ-GATE replaces it with the `costume-assign-denied` narrative),
      // but the stream row + detail are still reachable read-model
      // surfaces — the denial assertion renders on the detail.
      final world = context.world as AppWorld;
      final realCostume = world.seedIds[costumeId] ?? costumeId;
      await _openCostumeDetail(context.world, realCostume);
    },
  ),
  when2<String, String, FlutterWorld>(
    'I assign costume {string} to character {string}',
    (String costumeId, String characterId, context) async {
      // Opens the assign picker for the costume, then picks the character:
      // the command carries the picked id + the acted-on row's version.
      // Symbolic feature ids ("c-7" / "ch-3") map to the seeded REAL
      // backend ids (issue #368) before any widget key is composed.
      final world = context.world as AppWorld;
      final realCostume = world.seedIds[costumeId] ?? costumeId;
      final realCharacter = world.seedIds[characterId] ?? characterId;
      world.lastCostumeId = realCostume;
      world.lastCharacterId = realCharacter;
      // The assign button lives on the COSTUME DETAIL screen: the detail is
      // opened first (shared with the view step), then the unassigned-seed
      // FIRST-assignment button is tapped. Issue #453: the seed costume is
      // genuinely UNASSIGNED (repertoire-season binding, no pre-assign), so
      // the button key carries 'none' — the exact first-assignment contract
      // that was unreachable under the pre-#453 character-join scoping.
      await _openCostumeDetail(context.world, realCostume);
      final assignButton = find.byValueKey('assign-costume-$realCostume-none');
      await context.world.driver!.waitFor(
        assignButton,
        timeout: const Duration(seconds: 15),
      );
      await FlutterDriverUtils.tap(context.world.driver!, assignButton);
      final option = find.byValueKey('assign-character-$realCharacter');
      await context.world.driver!.waitFor(
        option,
        timeout: const Duration(seconds: 10),
      );
      await FlutterDriverUtils.tap(context.world.driver!, option);
    },
  ),
  when3<String, String, String, FlutterWorld>(
    'I reassign costume {string} from {string} to {string}',
    (
      String costumeId,
      String fromCharacterId,
      String toCharacterId,
      context,
    ) async {
      // Issue #454: the costume is ALREADY assigned to `fromCharacterId`;
      // the Reassign button (`assign-costume-<id>-<currentChar>`) dispatches
      // a client-side unassign→assign sequence (never the plain assign
      // command, which 409s `costume.already-assigned`). The app is already
      // on the costume DETAIL screen (the preceding assign step pushed it),
      // so the Reassign button is tapped in place — no list re-open.
      final world = context.world as AppWorld;
      final realCostume = world.seedIds[costumeId] ?? costumeId;
      final realFrom = world.seedIds[fromCharacterId] ?? fromCharacterId;
      final realTo = world.seedIds[toCharacterId] ?? toCharacterId;
      world.lastCostumeId = realCostume;
      world.lastCharacterId = realTo;
      final reassignButton = find.byValueKey(
        'assign-costume-$realCostume-$realFrom',
      );
      await context.world.driver!.waitFor(
        reassignButton,
        timeout: const Duration(seconds: 15),
      );
      await FlutterDriverUtils.tap(context.world.driver!, reassignButton);
      final option = find.byValueKey('assign-character-$realTo');
      await context.world.driver!.waitFor(
        option,
        timeout: const Duration(seconds: 10),
      );
      await FlutterDriverUtils.tap(context.world.driver!, option);
    },
  ),
  then<FlutterWorld>('the costume assignment appears optimistically', (
    context,
  ) async {
    // Optimistic overlay OR already-reconciled authoritative key.
    //
    // Issue #454 (reassign) exposed a timing race in this step: on a fast
    // localhost backend the projector refresh can clear the optimistic
    // overlay (fence passes) BEFORE the driver polls the tree, so a strict
    // `waitFor(overlay-assign-*)` flakes on runs whose command landed
    // instantly — while the DB proves the assign succeeded (version 2). The
    // strict optimistic-overlay + version-fence contract is pinned by the
    // WIDGET tier; on device the meaningful signal is that the command
    // landed and the projection carries the assignment. Accept EITHER key:
    // the fence-held overlay (CQRS optimistic stage observed) OR the
    // authoritative assigned row (already reconciled). A genuine command
    // failure (409 / error banner) shows NEITHER and still times out.
    final world = context.world as AppWorld;
    final overlayLocator = find.byValueKey(
      'overlay-assign-${world.lastCostumeId}-${world.lastCharacterId}',
    );
    final authoritativeLocator = find.byValueKey(
      'assigned-${world.lastCostumeId}-${world.lastCharacterId}',
    );
    await _waitForEither(
      world,
      [overlayLocator, authoritativeLocator],
      timeout: const Duration(seconds: 10),
      what: 'costume assignment (optimistic overlay or reconciled)',
    );
  }),
  then<FlutterWorld>('the costume assignment projection refreshes', (
    context,
  ) async {
    // The bounded-retry refetch swaps the optimistic entry for the
    // projected one (AGENTS.md §4): the fence passes and the authoritative
    // key replaces the overlay key.
    final world = context.world as AppWorld;
    final locator = find.byValueKey(
      'assigned-${world.lastCostumeId}-${world.lastCharacterId}',
    );
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 30),
    );
  }),
  then<FlutterWorld>('the costume stream denies assignment with a denial', (
    context,
  ) async {
    // Client-side AUTHZ-GATE (membership capability `assign_costumes`)
    // refuses the unprivileged caller on the costume stream before any
    // network call (AGENTS.md §5, D6): the localized 403 narrative renders
    // in place of the assign button on the costume detail.
    final locator = find.byValueKey('costume-assign-denied');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
  then<FlutterWorld>('no costume command leaves the device', (context) async {
    // AUTHZ-GATE preflight (issue #459): the client refused the action
    // before any command HTTP was issued. Verified against the real traffic
    // recorded by the in-app Dio interceptor (issue #380): the
    // costume-command counter (assign + unassign paths) must be zero.
    // Navigation read-model fetches are legitimate traffic and stay out of
    // this counter — the gate prevents command traffic, not page loads.
    final count = await _costumeCommandsLeftDevice(context.world);
    if (count != 0) {
      throw Exception(
        'AUTHZ-GATE preflight failed: '
        '$count costume command request(s) left the device before the '
        'client-side authorization check.',
      );
    }
  }),
];

/// Opens the seeded costume's DETAIL screen from the Kleidung stream row.
///
/// Projection-lag guard (#368 on-device run): the freshly seeded costume
/// reaches the read model a few seconds AFTER its 201 — if the tile is
/// absent, pull-to-refresh the real read-model seam (a real gesture, no
/// sleep) until it projects in. Then a pull-to-refresh before opening the
/// detail guards a stale device-Drift row whose version the server has
/// advanced (the acted-on row must echo the authoritative version).
Future<void> _openCostumeDetail(FlutterWorld world, String realCostume) async {
  final driver = world.driver!;
  final tile = find.byValueKey('costume-$realCostume');
  try {
    await driver.waitFor(tile, timeout: const Duration(seconds: 10));
  } on Object {
    await driver.scroll(
      find.byValueKey('costumes-list'),
      0,
      200,
      const Duration(milliseconds: 600),
    );
    await driver.waitFor(tile, timeout: const Duration(seconds: 20));
  }
  // Stale-version guard (#368 on-device run): the device-Drift cache can
  // hold a pre-restart row whose version the server has since advanced —
  // the echoed fence then 409s and the overlay never renders. Pull-to-refresh
  // the REAL read-model seam BEFORE opening the detail so the acted-on row
  // echoes the authoritative version (a real gesture, bounded wait, no sleep).
  await driver.scroll(
    find.byValueKey('costumes-list'),
    0,
    200,
    const Duration(milliseconds: 600),
  );
  await FlutterDriverUtils.tap(driver, tile);
}

/// Waits for ANY of [locators] to appear (acceptance of an authoritative
/// assertion across a reconcile race — see the optimistic step above).
/// The overhead is bounded and deterministic: each `waitFor` is itself
/// capped, so the worst case is the sum of the per-locator budgets.
Future<void> _waitForEither(
  FlutterWorld world,
  List<SerializableFinder> locators, {
  required Duration timeout,
  required String what,
}) async {
  final driver = world.driver!;
  final deadline = DateTime.now().add(timeout);
  // Poll in short bounded slices so the first of the alternatives that
  // appears wins immediately instead of serializing full budgets.
  final slice = const Duration(milliseconds: 250);
  while (DateTime.now().isBefore(deadline)) {
    for (final locator in locators) {
      try {
        await driver.waitFor(locator, timeout: slice);
        return;
      } on Object {
        // Not (yet) present; try the next alternative.
      }
    }
    await Future<void>.delayed(slice);
  }
  throw TimeoutException('timed out waiting for $what', timeout);
}
