// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

/// Step definitions for the costume assignment critical scenario
/// (`features-spec/costume_assignment.feature`). Covers the CQRS-on-client
/// contract (AGENTS.md §4): optimistic overlay after a 2xx command
/// acknowledgement, then projection reconciliation; plus the client-side
/// AUTHZ-GATE role denial on the costume stream. All steps drive the on-device
/// UI through widget keys; none assert on a pure function.
Iterable<StepDefinitionGeneric> costumeAssignmentSteps() => [
  when2<String, String, FlutterWorld>(
    'I assign costume {string} to character {string}',
    (String costumeId, String characterId, context) async {
      // Opens the assign picker for the costume, then picks the character:
      // the command carries the picked id + the acted-on row's version.
      final world = context.world as AppWorld;
      world.lastCostumeId = costumeId;
      world.lastCharacterId = characterId;
      final assignButton = find.byValueKey('assign-costume-$costumeId-none');
      await FlutterDriverUtils.tap(context.world.driver!, assignButton);
      final option = find.byValueKey('assign-character-$characterId');
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
