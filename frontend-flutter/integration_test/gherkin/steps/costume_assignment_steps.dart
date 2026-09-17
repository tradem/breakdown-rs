// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart';

/// Existing dev series for the seeded season (the same fixed dev-series UUID
/// the season-setup-wizard scenarios use; dev-auth mode bootstraps its owner
/// membership on block creation).
const String kSeedSeriesId = '11111111-1111-1111-1111-111111111111';

/// Step definitions for the costume assignment critical scenario
/// (`features-spec/costume_assignment.feature`). Covers the CQRS-on-client
/// contract (AGENTS.md §4): optimistic overlay after a 2xx command
/// acknowledgement, then projection reconciliation; plus the client-side
/// AUTHZ-GATE role denial on the costume stream. All steps drive the on-device
/// UI through widget keys; none assert on a pure function.
Iterable<StepDefinitionGeneric> costumeAssignmentSteps() => [
  given<FlutterWorld>(
    'the backend is seeded with costume "c-7" and character "ch-3" for '
    'season "1"',
    (context) async {
      // Issue #368: the REAL dev backend was seeded over HTTP by
      // `AppHook.onBeforeRun` (host-side, BEFORE the first app launch —
      // seed_http.dart has the flow and the real-backend contract
      // discovery notes). This step copies the resolved REAL ids into the
      // scenario's `AppWorld.seedIds` so downstream steps map the feature's
      // symbolic ids (season "1", "ch-3", "ch-9", "c-7") to backend
      // aggregates. State-establishment step (no assertion) — runs on
      // device with the harness, not a pure-function check.
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
      // The assign button lives on the COSTUME DETAIL screen: open the
      // detail from the costumes list first (the Kleidung-tab move moved the
      // stream entry, not the detail — post-#439 discovery of the #368
      // on-device run), then tap the assign button. Projection-lag guard:
      // the freshly seeded costume reaches the read model a few seconds
      // AFTER its 201 — if the tile is absent, pull-to-refresh the real
      // read-model seam (a real gesture, no sleep) until it projects in.
      final driver = context.world.driver!;
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
      // hold a pre-restart row whose version the server has since advanced
      // (the seed pre-assigns between boots) — the echoed fence then 409s
      // and the overlay never renders. Pull-to-refresh the REAL read-model
      // seam BEFORE opening the detail so the acted-on row echoes the
      // authoritative version (a real gesture, bounded wait, no sleep).
      await driver.scroll(
        find.byValueKey('costumes-list'),
        0,
        200,
        const Duration(milliseconds: 600),
      );
      await FlutterDriverUtils.tap(driver, tile);
      // Reassignment entry (real-backend contract): the costume arrives
      // pre-assigned (seed c-7 → ch-9), so the button key carries the
      // CURRENT character id ('assign-costume-<id>-<ch9>'), not 'none'.
      final currentHolder = world.seedIds['ch-9'];
      final assignButton = find.byValueKey(
        'assign-costume-$realCostume-${currentHolder ?? "none"}',
      );
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
  then<FlutterWorld>('the costume assignment appears optimistically', (
    context,
  ) async {
    // Optimistic overlay: the command is acknowledged immediately and the
    // row carries the assignment with the fence-held key before the
    // projection refreshes.
    final world = context.world as AppWorld;
    final locator = find.byValueKey(
      'overlay-assign-${world.lastCostumeId}-${world.lastCharacterId}',
    );
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
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
    // network call (AGENTS.md §5, D6): the localized 403 narrative renders.
    final locator = find.byValueKey('costume-assign-denied');
    await context.world.driver!.waitFor(
      locator,
      timeout: const Duration(seconds: 10),
    );
  }),
];
