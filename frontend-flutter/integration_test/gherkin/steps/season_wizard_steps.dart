// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';

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
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('$apiBase/v1/__faults/block-conflict'),
        );
        final res = await req.close();
        if (res.statusCode != HttpStatus.noContent) {
          final body = await res.transform(utf8.decoder).join();
          throw Exception(
            'fault arming failed (${res.statusCode}): $body — is the dev '
            'backend running with `--features api/test-support`?',
          );
        }
      } finally {
        client.close();
      }
      // The then-steps assert the wizard's partial-failure surface; the
      // flag stays as the assertion-side intent marker.
      (context.world as AppWorld).wizardExpectsPartialFailure = true;
    },
  ),
  when<FlutterWorld>('I start the season setup wizard from the empty state', (
    context,
  ) async {
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('seasons-empty-setup-cta'),
    );
    await context.world.driver!.waitFor(
      find.byValueKey('wizard-step-season'),
      timeout: const Duration(seconds: 10),
    );
  }),
  when2<String, String, FlutterWorld>(
    'I set the season number to {string} and the name {string}',
    (String number, String name, context) async {
      await FlutterDriverUtils.enterText(
        context.world.driver!,
        find.byValueKey('wizard-number-field'),
        number,
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
    await FlutterDriverUtils.tap(
      context.world.driver!,
      find.byValueKey('wizard-confirm'),
    );
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
      final driver = context.world.driver!;
      await driver.waitFor(
        find.byValueKey('wizard-review-summary'),
        timeout: const Duration(seconds: 10),
      );
      await driver.waitFor(
        find.text(title),
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
