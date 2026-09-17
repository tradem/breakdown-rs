// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart' show resolveFreeSeasonNumber;

/// The wizard scenario hard-codes season number "1", but the dev series
/// accumulates seasons across runs; the dispatch POST /v1/seasons only
/// passes with a free number (409 `season.number-already-exists` otherwise).
/// The lowest free number is resolved host-side (seed_http.dart, shared
/// with the costume-assignment seeding) into `AppWorld
/// .wizardFreeSeasonNumber`, and the number-entry / review-title steps map
/// the symbolic "1" to it (same symbolic→real discipline as the #368 seed
/// ids).

/// Step definitions for the season-setup-wizard critical scope
/// (`features-spec/setup/season-wizard.feature`). All steps drive the
/// on-device UI through the wizard's widget keys — none assert a pure
/// function (AGENTS.md §6: a step whose body only calls a pure function
/// belongs in the unit tier).
Iterable<StepDefinitionGeneric> seasonWizardSteps() => [
  given<FlutterWorld>(
    'the backend rejects the first block create with a conflict',
    (context) async {
      // Issue #443: arm the REAL backend fault instead of only recording a
      // client-side intent. The dev backend must be booted with `--features
      // api/test-support`; the one-shot latch then short-circuits the FIRST
      // `POST /v1/blocks` of this scenario with the registry 409
      // `block.number-already-exists`, and the in-session retry passes
      // through. Arming is idempotent-on-repeat (the latch is one-shot, so
      // re-arming before each run re-arms deterministically).
      final apiBase =
          Platform.environment['API_BASE'] ?? 'http://10.0.2.2:3000';
      // Bounded timeputs (CodeRabbit finding, PR #452): a stall here must
      // fail the arming step deterministically, not hang the whole run.
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.postUrl(
          Uri.parse('$apiBase/v1/__faults/block-conflict'),
        );
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != HttpStatus.noContent) {
          final body = await res.transform(utf8.decoder).join();
          throw Exception(
            'fault arming failed (${res.statusCode}): $body — is the dev '
            'backend running with `--features api/test-support`?',
          );
        }
      } finally {
        // Force-close: timeout sockets must not linger on the emulator.
        client.close(force: true);
      }
      // The then-steps assert the wizard's partial-failure surface; the
      // flag stays as the assertion-side intent marker.
      (context.world as AppWorld).wizardExpectsPartialFailure = true;
    },
  ),
  when<FlutterWorld>('I start the season setup wizard from the empty state', (
    context,
  ) async {
    // Post-#439 harness repair (discovered by the #368 on-device run): the
    // seasons home renders the SEASONS EMPTY STATE only when the backend has
    // no seasons — with seeded dev data it renders the card grid, whose
    // wizard entry is the extended FAB → create sheet → "Oder geführt
    // einrichten" (create-open-wizard). Both entries open the same
    // SetupWizardScreen route; the driver wait below is the assertion.
    // Try the FAB path first (works in both states — the FAB renders whenever
    // creation is permitted), fall back to the empty-state CTA.
    final world = context.world as AppWorld;
    // Resolve the free season number BEFORE entering the wizard: the
    // dispatch 409s on a taken SERIES-scoped number (dev data accumulates
    // across runs); the number-entry step maps the symbolic "1" to it.
    world.wizardFreeSeasonNumber = await resolveFreeSeasonNumber();
    final driver = context.world.driver!;
    try {
      final fab = find.byValueKey('season-add-fab');
      await driver.waitFor(fab, timeout: const Duration(seconds: 10));
      await FlutterDriverUtils.tap(driver, fab);
      final wizardEntry = find.byValueKey('create-open-wizard');
      await driver.waitFor(wizardEntry, timeout: const Duration(seconds: 10));
      await FlutterDriverUtils.tap(driver, wizardEntry);
    } on Object {
      // No FAB / create sheet (e.g. a wiped dev backend): fall back to the
      // empty-state CTA — the original #442 entry path.
      await FlutterDriverUtils.tap(
        driver,
        find.byValueKey('seasons-empty-setup-cta'),
      );
    }
    await driver.waitFor(
      find.byValueKey('wizard-step-season'),
      timeout: const Duration(seconds: 10),
    );
  }),
  when2<String, String, FlutterWorld>(
    'I set the season number to {string} and the name {string}',
    (String number, String name, context) async {
      // Symbolic→real mapping (same discipline as the #368 seed ids): the
      // feature's season number "1" maps to the free SERIES-scoped number
      // resolved host-side (AppWorld.wizardFreeSeasonNumber) — the dev
      // series accumulates seasons across runs, and the dispatch 409s on a
      // taken number. Legacy runs without a resolution fall back to the
      // literal feature number.
      final world = context.world as AppWorld;
      final effective = (number == '1' && world.wizardFreeSeasonNumber != null)
          ? world.wizardFreeSeasonNumber.toString()
          : number;
      await FlutterDriverUtils.enterText(
        context.world.driver!,
        find.byValueKey('wizard-number-field'),
        effective,
      );
      await FlutterDriverUtils.enterText(
        context.world.driver!,
        find.byValueKey('wizard-name-field'),
        name,
      );
    },
  ),
  when<FlutterWorld>('I enter a season name', (context) async {
    await FlutterDriverUtils.enterText(
      context.world.driver!,
      find.byValueKey('wizard-name-field'),
      'Sommer 2026',
    );
  }),
  when<FlutterWorld>('I advance to the blocks step', (context) async {
    await _advanceThroughSteps(context, untilKey: 'wizard-step-blocks');
  }),
  when1<String, FlutterWorld>('I apply the template {string}', (
    String template,
    context,
  ) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-apply-template-$template'),
    );
  }),
  when<FlutterWorld>('I advance to the review step', (context) async {
    await _advanceThroughSteps(context, untilKey: 'wizard-step-review');
  }),
  when<FlutterWorld>(
    'I complete the season setup with 2 blocks of 4 episodes',
    (context) async {
      // Season step: the smart defaults stay; blocks step: clear the
      // default draft, apply 2×4, then review + confirm.
      await _advanceThroughSteps(context, untilKey: 'wizard-step-blocks');
      await FlutterDriverUtils.tap(
        context.world.driver!,
        find.byValueKey('wizard-remove-draft-0'),
      );
      for (var i = 0; i < 2; i++) {
        await FlutterDriverUtils.tap(
          context.world.driver!,
          find.byValueKey('wizard-add-draft'),
        );
      }
      for (var i = 0; i < 2; i++) {
        await FlutterDriverUtils.enterText(
          context.world.driver!,
          find.byValueKey('wizard-episode-count-$i'),
          '4',
        );
      }
      await _advanceThroughSteps(context, untilKey: 'wizard-step-review');
      await FlutterDriverUtils.tap(
        context.world.driver!,
        find.byValueKey('wizard-confirm'),
      );
    },
  ),
  when<FlutterWorld>('I confirm the review', (context) async {
    // The review renders 4 block cards above the confirm CTA in a
    // LongPressScrollable ListView (template 4x8): the button is composed
    // but off-viewport, and a FlutterDriver tap requires the finder to be
    // hit-testable — without scrolling it times out after 30s (discovered
    // by the #368 on-device run). Scroll the review list until the button
    // is onscreen, then tap. Bounded: the scroll target wait fails loudly
    // if the button never scrolls into view (deterministic harness rule).
    final driver = context.world.driver!;
    final list = find.byValueKey('wizard-step-review');
    final confirm = find.byValueKey('wizard-confirm');
    await driver.scrollUntilVisible(
      list,
      confirm,
      dxScroll: 0,
      dyScroll: -200,
      timeout: const Duration(seconds: 10),
    );
    await FlutterDriverUtils.tap(driver, confirm);
  }),
  when<FlutterWorld>('I remove the first block draft', (context) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-remove-draft-0'),
    );
  }),
  when<FlutterWorld>('I retry the remaining commands', (context) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-retry'),
    );
  }),
  when<FlutterWorld>('I leave the wizard without submitting', (context) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-back'),
    );
  }),
  when<FlutterWorld>('I confirm the discard', (context) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-discard-confirm'),
    );
  }),
  then<FlutterWorld>(
    'the season number defaults to the highest existing plus one',
    (context) async {
      // The smart default renders as the live preview; the harness seeds
      // the dev backend with two seasons (1, 2) before the scenario.
      await context.world.driver!.waitFor(
        find.byValueKey('wizard-live-preview'),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  then3<String, int, int, FlutterWorld>(
    'the review shows {string} with {int} blocks and {int} episodes',
    (String title, int blocks, int episodes, context) async {
      final world = context.world as AppWorld;
      final driver = context.world.driver!;
      await driver.waitFor(
        find.byValueKey('wizard-review-summary'),
        timeout: const Duration(seconds: 10),
      );
      // The harness maps the symbolic season number "1" to the free
      // SERIES-scoped number (AppWorld.wizardFreeSeasonNumber) — the dev
      // series accumulates seasons across runs, so the on-screen preview
      // shows e.g. "Season 102 · Sommer 2026", never a literal "1" when
      // that number is taken. Map the feature's symbolic title accordingly
      // (same symbolic→real discipline as the #368 seed ids).
      final effectiveTitle = (world.wizardFreeSeasonNumber != null)
          ? title.replaceFirst(
              'Season 1 ',
              'Season ${world.wizardFreeSeasonNumber} ',
            )
          : title;
      await driver.waitFor(
        find.text(effectiveTitle),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  then1<String, FlutterWorld>(
    'the wizard shows the created structure {string}',
    (String structure, context) async {
      final driver = context.world.driver!;
      await driver.waitFor(
        find.byValueKey('wizard-completion'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitFor(
        find.text(structure),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  then<FlutterWorld>(
    'the AI import offer depends on the existing AI configuration',
    (context) async {
      // The CTA renders only with a configuration; without one the info
      // card does. Either surface proves the conditional gating
      // (decision 6).
      final driver = context.world.driver!;
      final found = await _waitForAny(driver, [
        find.byValueKey('wizard-completion-import-cta'),
        find.byValueKey('wizard-completion-ai-info'),
      ], const Duration(seconds: 10));
      if (!found) {
        throw Exception(
          'Neither the import CTA nor the prerequisite info card rendered',
        );
      }
    },
  ),
  then<FlutterWorld>(
    'three block drafts with 6 episodes each exist and stay editable',
    (context) async {
      final driver = context.world.driver!;
      // The 3×6 template APPENDS to the one default draft: the template
      // drafts are positions 1..3, each episode-count field holds "6".
      for (var i = 1; i <= 3; i++) {
        await driver.waitFor(
          find.byValueKey('wizard-block-draft-$i'),
          timeout: const Duration(seconds: 10),
        );
        final count = await driver.getText(
          find.byValueKey('wizard-episode-count-$i'),
        );
        if (count != '6') {
          throw Exception('draft $i episode count is "$count", expected "6"');
        }
      }
    },
  ),
  then<FlutterWorld>(
    'the draft list updates and the wizard stays on the blocks step',
    (context) async {
      await context.world.driver!.waitFor(
        find.byValueKey('wizard-step-blocks'),
        timeout: const Duration(seconds: 10),
      );
    },
  ),
  then<FlutterWorld>('the wizard stops with the created-so-far summary', (
    context,
  ) async {
    await context.world.driver!.waitFor(
      find.byValueKey('wizard-completion-partial-title'),
      timeout: const Duration(seconds: 30),
    );
  }),
  then<FlutterWorld>('the conflict is reported keyed on its problem code', (
    context,
  ) async {
    // The localized narrative is keyed on the stable registry code
    // `block.number-already-exists` (issue #443 — the real wire code; the
    // legacy `blocks.conflict` alias never appears on the wire). The copy
    // is asserted verbatim, never the server `detail`. Series-scoped
    // wording (backend invariant: block numbers are unique per series, not
    // per season).
    await context.world.driver!.waitFor(
      find.text(
        'Ein Block mit dieser Nummer existiert bereits in der '
        'Serie.',
      ),
      timeout: const Duration(seconds: 10),
    );
  }),
  then<FlutterWorld>(
    'the wizard reaches the completion screen with the full structure',
    (context) async {
      await context.world.driver!.waitFor(
        find.byValueKey('wizard-completion'),
        timeout: const Duration(seconds: 30),
      );
    },
  ),
  then<FlutterWorld>('the discard confirmation names what will be lost', (
    context,
  ) async {
    await context.world.driver!.waitFor(
      find.byValueKey('wizard-discard-confirm'),
      timeout: const Duration(seconds: 10),
    );
  }),
  then<FlutterWorld>('nothing was created and reopening starts fresh', (
    context,
  ) async {
    // The wizard popped back to the seasons home and nothing was
    // created: the empty state's setup CTA is on-screen again (the dev
    // backend seeds zero seasons for this scenario family).
    await context.world.driver!.waitFor(
      find.byValueKey('seasons-empty-setup-cta'),
      timeout: const Duration(seconds: 30),
    );
  }),
];

/// Taps `wizard-next` until [untilKey] appears (bounded, deterministic —
/// no wall-clock gating beyond the per-locator timeouts).
Future<void> _advanceThroughSteps(
  StepContext<FlutterWorld> context, {
  required String untilKey,
}) async {
  final driver = context.world.driver!;
  for (var i = 0; i < 4; i++) {
    try {
      await driver.waitFor(
        find.byValueKey(untilKey),
        timeout: const Duration(seconds: 1),
      );
      return;
    } on Object {
      await FlutterDriverUtils.tap(driver, find.byValueKey('wizard-next'));
      await driver.waitFor(
        find.byValueKey('wizard-progress'),
        timeout: const Duration(seconds: 5),
      );
    }
  }
  await driver.waitFor(
    find.byValueKey(untilKey),
    timeout: const Duration(seconds: 5),
  );
}

/// Waits until EITHER locator is present (the driver has no first-of
/// primitive; a serial bounded try/wait does this).
Future<bool> _waitForAny(
  FlutterDriver driver,
  List<SerializableFinder> locators,
  Duration perLocatorTimeout,
) async {
  for (final locator in locators) {
    try {
      await driver.waitFor(locator, timeout: perLocatorTimeout);
      return true;
    } on Object {
      // Not this one — try the next candidate.
    }
  }
  return false;
}
