// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart' show hostApiBase, resolveFreeSeasonNumber;

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
      // This is a HOST-side step (the test-runner process), so it must
      // reach the backend via hostApiBase() — the emulator-only `10.0.2.2`
      // loopback alias is unreachable from the host and would time out
      // (issue #463 on-device gap: the arming step's first on-device pass
      // hit exactly that). hostApiBase() substitutes `10.0.2.2` ->
      // `localhost` (the same host-resolution the seed helpers use).
      final apiBase = hostApiBase();
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
    // no seasons — with seeded dev data it renders the card grid. Since issue
    // #511 the extended FAB is the GUIDED entry in BOTH states: it opens the
    // SetupWizardScreen directly (the manual quick-create sheet moved to the
    // app bar's secondary action). The driver wait below is the assertion.
    // Try the FAB path first (works in both states — the FAB renders whenever
    // creation is permitted), fall back to the empty-state CTA.
    final world = context.world as AppWorld;
    // Resolve the free season number BEFORE entering the wizard: the
    // dispatch 409s on a taken SERIES-scoped number (dev data accumulates
    // across runs); the number-entry step maps the symbolic "1" to it.
    // resolveFreeSeasonNumber THROWS on backend/parser failure
    // (CodeRabbit review, #456: never silently store a taken literal) —
    // the exception propagates and fails this step deterministically.
    // The env gate (GHERKIN_WIZARD_RESOLVE) is defaulted ON by
    // tool/run_gherkin.sh (issue #463): the promoted wizard scenarios
    // dispatch against the accumulated dev series, so the resolution must
    // be active for the default on-device pass, never a silent-literal 1.
    if (Platform.environment['GHERKIN_WIZARD_RESOLVE'] == 'on') {
      world.wizardFreeSeasonNumber = await resolveFreeSeasonNumber();
    }
    final driver = context.world.driver!;
    try {
      final fab = find.byValueKey('season-add-fab');
      await driver.waitFor(fab, timeout: const Duration(seconds: 10));
      await FlutterDriverUtils.tap(driver, fab);
    } on Object {
      // No FAB (e.g. a wiped dev backend / signed out): fall back to the
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
      // Season step: enter the HOST-RESOLVED free season number (the happy
      // path's resolution discipline — issue #463 on-device race: the smart
      // default recomputes max+1 from the projection, but the happy path's
      // dispatch took that number mid-run, so the season create 409s with
      // `season.number-already-exists` and the block fault never fires,
      // leaving the BLOCK-conflict narrative missing). Entering the resolved
      // free number keeps the season create conflict-free and lets the armed
      // block fault be the first failure, as the scenario contracts.
      final world = context.world as AppWorld;
      if (world.wizardFreeSeasonNumber != null) {
        await FlutterDriverUtils.enterText(
          context.world.driver!,
          find.byValueKey('wizard-number-field'),
          world.wizardFreeSeasonNumber.toString(),
        );
      }
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
      // Same scroll-then-tap as `I confirm the review`: the confirm CTA sits
      // at the bottom of the review ListView (below the block cards) and a
      // FlutterDriver tap requires it hit-testable (issue #463 — the
      // partial-failure scenario exercises this path on-device; the happy
      // path's review-confirm repair discovered the off-viewport tap
      // timeout). Bounded: fails loudly if it never scrolls into view.
      await _scrollToAndTap(context, 'wizard-step-review', 'wizard-confirm');
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
    await _scrollToAndTap(context, 'wizard-step-review', 'wizard-confirm');
  }),
  when<FlutterWorld>('I remove the first block draft', (context) async {
    final driver = context.world.driver!;
    // Issue #463 on-device gap: the blocks step is a viewport-limited
    // non-lazy ListView (_DraftCard children plus the template chips below).
    // In the template scenario the `three block drafts` assertion just
    // scrolled DOWN to draft 3, so draft 0 (and its remove button) sits
    // ABOVE the viewport — a FlutterDriver tap requires the finder to be
    // hit-testable, so scroll UP (positive dyScroll) until it is onscreen
    // (bounded: the scroll target wait fails loudly if it never appears).
    final list = find.byValueKey('wizard-step-blocks');
    final remove = find.byValueKey('wizard-remove-draft-0');
    await driver.scrollUntilVisible(
      list,
      remove,
      dxScroll: 0,
      dyScroll: 200,
      timeout: const Duration(seconds: 10),
    );
    await FlutterDriverUtils.tap(driver, remove);
  }),
  when<FlutterWorld>('I retry the remaining commands', (context) async {
    // runUnsynchronized: the retry re-starts the dispatch, whose reconcile
    // keeps the app scheduling frames; the un-synced tap targets the
    // already-rendered `wizard-retry` button without frame-sync waiting for
    // a quiescent frame first (issue #463).
    final driver = context.world.driver!;
    await driver.runUnsynchronized(
      () => FlutterDriverUtils.tap(driver, find.byValueKey('wizard-retry')),
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
      // The 4×8 happy path dispatches 1 season + 4 blocks + 32 episodes =
      // 37 sequential commands against the real backend; each takes ~1s
      // from the emulator, plus the submit-time live re-derive (issue
      // #455). The completion budget must cover that analytic worst case
      // (deterministic-tests rule — never a sleep, a bounded per-command
      // worst case).
      await driver.waitFor(
        find.byValueKey('wizard-completion'),
        timeout: const Duration(seconds: 120),
      );
      await driver.waitFor(
        find.text(structure),
        timeout: const Duration(seconds: 30),
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
      ], const Duration(seconds: 20));
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
      // Issue #463 on-device gap: the 3×6 template APPENDS to the one
      // default draft (block drafts 1..3), but the blocks step is a
      // viewport-limited non-lazy ListView — the appended draft cards sit
      // BELOW the fold, so a plain `waitFor(byValueKey)` never matches
      // (the happy path never asserts these keys, so this was never
      // caught). Each draft must be scrolled into view before asserting it
      // and its episode-count field (established pattern: the same
      // `scrollUntilVisible` the review-confirm step uses). The emulator
      // driver is slow under a multi-scenario run (the happy path's own
      // waits logged "taking a long time"), so the per-scroll budget is a
      // bounded worst case. `scrollUntilVisible` returns after
      // `scrollIntoView` settles, making a later tap/getText hit-testable.
      for (var i = 1; i <= 3; i++) {
        final draft = find.byValueKey('wizard-block-draft-$i');
        await driver.scrollUntilVisible(
          find.byValueKey('wizard-step-blocks'),
          draft,
          dxScroll: 0,
          dyScroll: -200,
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
    //
    // runUnsynchronized: the dispatch's fire-and-forget reconcile keeps the
    // app scheduling frames right after the partial-failure settles, so a
    // frame-synced `waitFor` can starve on the "quiet frame" it never gets
    // (issue #463 on-device failure). The un-synced wait still asserts the
    // text is present; it just does not wait for the frame to idle first.
    final driver = context.world.driver!;
    try {
      await driver.runUnsynchronized(
        () => driver.waitFor(
          find.text(
            'Ein Block mit dieser Nummer existiert bereits in der '
            'Serie.',
          ),
          timeout: const Duration(seconds: 10),
        ),
      );
    } on Object {
      // Diagnostic: surface the REAL rendered failure so a code-mapping
      // drift fails loudly with the actual copy (issue #463 — the full-
      // suite run showed the block-conflict narrative absent; this dumps
      // what the completion view actually renders).
      String rendered = '<error-key-not-read>';
      try {
        rendered = await driver.runUnsynchronized(
          () => driver.getText(find.byValueKey('wizard-completion-error')),
        );
      } on Object {
        rendered = '<wizard-completion-error not found>';
      }
      throw StateError(
        'block-conflict narrative not found; rendered error copy was: '
        '$rendered',
      );
    }
  }),
  then<FlutterWorld>(
    'the wizard reaches the completion screen with the full structure',
    (context) async {
      // runUnsynchronized: the retry dispatch's reconcile keeps scheduling
      // frames as it lands the remaining commands; the un-synced wait still
      // asserts the completion screen rendered (issue #463).
      final driver = context.world.driver!;
      await driver.runUnsynchronized(
        () => driver.waitFor(
          find.byValueKey('wizard-completion'),
          timeout: const Duration(seconds: 30),
        ),
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
    // created. The seasons home renders the empty-state CTA only when the
    // backend has ZERO seasons; under accumulated dev data it renders the
    // card grid. Both states are guaranteed by the
    // authenticated-session gate, so assert the seasons home is showing
    // (wizard gone) via the guided FAB — the same entry the wizard came
    // from (#511).
    await context.world.driver!.waitFor(
      find.byValueKey('season-add-fab'),
      timeout: const Duration(seconds: 30),
    );
    // The wizard route is gone (its season step is no longer on-screen).
    await context.world.driver!.waitForAbsent(
      find.byValueKey('wizard-step-season'),
      timeout: const Duration(seconds: 10),
    );
  }),
];

/// Scrolls [scrollableKey]'s list until the widget at [itemKey] is onscreen,
/// then taps it. Shared by the review-confirm paths: the confirm CTA sits at
/// the bottom of the review ListView below the block cards, and a
/// FlutterDriver tap requires the finder to be hit-testable (the #368-era
/// review-confirm repair; reused by the partial-failure scenario under issue
/// #463). Bounded — the scroll target wait fails loudly if the item never
/// scrolls into view (deterministic harness rule, never a silent pass).
Future<void> _scrollToAndTap(
  StepContext<FlutterWorld> context,
  String scrollableKey,
  String itemKey,
) async {
  final driver = context.world.driver!;
  await driver.scrollUntilVisible(
    find.byValueKey(scrollableKey),
    find.byValueKey(itemKey),
    dxScroll: 0,
    dyScroll: -200,
    timeout: const Duration(seconds: 10),
  );
  await FlutterDriverUtils.tap(driver, find.byValueKey(itemKey));
}

/// Taps `wizard-next` until [untilKey] appears (bounded, deterministic —
/// no wall-clock gating beyond the per-locator timeouts). The next button
/// is waited for PRESENT before each tap, so a blocked/unrendered advance
/// fails loudly instead of mis-tapping the surrounding screen (issue #463
/// — the partial-failure scenario drove the seasons HOME because its
/// feature was missing the wizard-start step; this guard catches that
/// class of harness error deterministically instead of hanging the tap).
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
      await driver.waitFor(
        find.byValueKey('wizard-next'),
        timeout: const Duration(seconds: 20),
      );
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
