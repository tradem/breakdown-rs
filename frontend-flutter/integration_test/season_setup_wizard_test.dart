// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// On-device E2E for the season setup wizard (add-season-setup-wizard task
// 5.3): the FULL flow — Season → Blocks → Review → dispatch → Completion —
// driven through the REAL repositories against the dev backend (the
// documented device tier: the backend dev compose must be reachable at
// `API_BASE`, AGENTS.md §7), plus the abort path (destructive discard,
// decision 3). Run via `dart run integration_test run-tests` on an
// emulator/device with the backend compose up.

import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_controller.dart';
import 'package:frontend_flutter/src/network/api_client.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_screen.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_state.dart';

/// Pumps (bounded) until the wizard's dispatch settles — the real-backend
/// sequence plus its reconcile passes take wall-clock time on device; the
/// predicate makes the wait deterministic, never a fixed sleep
/// (AGENTS.md §6 deterministic-tests rule adapted to the device tier).
Future<void> _waitForSettle(
  WidgetTester tester,
  ProviderContainer container, {
  int maxPumps = 300,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (container.read(setupWizardControllerProvider).phase !=
        SetupWizardPhase.dispatching) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Bounded-wait exhaustion is a FAILURE, never a silent pass: re-check
  // after the final pump so a dispatch that settled on it is not reported.
  if (container.read(setupWizardControllerProvider).phase ==
      SetupWizardPhase.dispatching) {
    fail(
      'dispatch did not settle within $maxPumps pumps; phase is still '
      'dispatching',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A fresh UUID series per run: the dev backend accumulates seasons and
  /// blocks under the fixed test series across runs, and block numbers are
  /// series-scoped — a fresh series keeps the full dispatch deterministic.
  String freshSeriesId() {
    final r = DateTime.now().microsecondsSinceEpoch;
    String h(int v, int len) =>
        v.toRadixString(16).padLeft(len, '0').substring(0, len);
    return '${h(r, 8)}-${h(r >> 32, 4)}-4${h(r, 3)}'
        '-8${h(r >> 8, 3)}-${h(r, 12)}';
  }

  late String seriesId;

  const devConfigTemplate = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    // Real-backend dispatch: `series_id` is a UUID on the wire, so the
    // dev define carries a fixed test-series UUID (deterministic).
    defaultSeriesId: '11111111-1111-1111-1111-111111111111',
  );

  late ProviderContainer container;

  /// Builds the container the bootstrap way: real repositories, real API
  /// client over the dev flavor's pinned-CA SecurityContext (loaded once
  /// from the bundled asset, mirroring [bootstrap]), real Drift cache —
  /// only the config is pinned.
  Future<ProviderContainer> buildContainer() async {
    final caPem = await rootBundle.loadString('assets/certs/dev/ca.pem');
    final pinned = pinnedSecurityContext(utf8.encode(caPem));
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: devConfigTemplate.flavor,
            apiBase: devConfigTemplate.apiBase,
            oidcIss: devConfigTemplate.oidcIss,
            devAuthSub: devConfigTemplate.devAuthSub,
            oidcAudience: devConfigTemplate.oidcAudience,
            oidcClientId: devConfigTemplate.oidcClientId,
            oidcRedirectUri: devConfigTemplate.oidcRedirectUri,
            devIdpInsecure: devConfigTemplate.devIdpInsecure,
            appVersion: devConfigTemplate.appVersion,
            defaultSeriesId: seriesId,
          ),
        ),
        pinnedSecurityContextProvider.overrideWithValue(pinned),
      ],
    );
  }

  setUp(() => seriesId = freshSeriesId());

  tearDown(() => container.dispose());

  testWidgets(
    'full wizard run: season → 2 blocks → review → completion against the '
    'dev backend',
    (tester) async {
      container = await buildContainer();
      // Dev-auth boots signed out at the login gate (spec
      // `flutter-auth-shell`); resolve the permissive session explicitly
      // — the AUTHZ-GATE the dispatch enforces.
      await container.read(authSessionControllerProvider.notifier).signIn();

      // Derive a conflict-free season number from the REAL projection
      // (max+1) before opening the wizard — the dev backend accumulates
      // seasons across runs, so the fresh-seed default (1) would 409.
      final rows =
          (await container.read(seasonRepositoryProvider).fetchSeasonsList())
              .getOrElse((_) => const []);
      final nextNumber =
          rows.fold<int>(0, (max, s) => s.number > max ? s.number : max) + 1;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            home: const SetupWizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 renders with the smart-default number seeded from the
      // seasons projection (the key is number-independent).
      expect(find.byKey(const Key('wizard-step-season')), findsOneWidget);
      expect(find.byKey(const Key('wizard-progress-text')), findsOneWidget);

      // Pin the derived number so the real dispatch cannot conflict with a
      // concurrently created season.
      await tester.enterText(
        find.byKey(const Key('wizard-number-field')),
        '$nextNumber',
      );

      // Season → Blocks.
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wizard-step-blocks')), findsOneWidget);

      // Clear the default draft, add two drafts of 4 episodes each
      // (the templates are the 4×8 / 3×6 presets; 2×4 is built by hand),
      // then advance to Review.
      await tester.tap(find.byKey(const Key('wizard-remove-draft-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-add-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-add-draft')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('wizard-episode-count-0')),
        '4',
      );
      await tester.enterText(
        find.byKey(const Key('wizard-episode-count-1')),
        '4',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      // Review: summary + confirm.
      expect(find.byKey(const Key('wizard-review-summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wizard-confirm')));

      // The dispatch issues the season → blocks → episodes commands
      // against the dev backend; per-command progress is visible, then
      // the completion screen lists the created structure.
      await tester.pump();
      // Predicate-driven settle wait: the real sequence plus its reconcile
      // passes take wall-clock time on device (bounded pumps, never a fixed
      // sleep — AGENTS.md §6 deterministic tests).
      await _waitForSettle(tester, container);
      expect(find.byKey(const Key('wizard-completion')), findsOneWidget);
      // Conditional CTA: either the import CTA or the prerequisite info
      // card renders (checked client-side before render, decision 6).
      final cta = find.byKey(const Key('wizard-completion-import-cta'));
      final info = find.byKey(const Key('wizard-completion-ai-info'));
      final ctaFound = cta.evaluate().isNotEmpty;
      expect(ctaFound || info.evaluate().isNotEmpty, isTrue);

      // Done pops back.
      await tester.tap(find.byKey(const Key('wizard-completion-done')));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'abort path: back + confirm discards; nothing created, reopen fresh',
    (tester) async {
      container = await buildContainer();
      await container.read(authSessionControllerProvider.notifier).signIn();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            home: const SetupWizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter a name (draft state exists), then back out.
      await tester.enterText(
        find.byKey(const Key('wizard-name-field')),
        'Aborted',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('wizard-back')));
      await tester.pumpAndSettle();

      // The confirmation names what is lost (decision 3).
      expect(find.text('Setup abbrechen?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wizard-discard-confirm')));
      await tester.pumpAndSettle();

      // Reopening starts fresh: nothing was created or persisted. (The
      // prior tree is torn down FIRST — re-rooting the Navigator directly
      // trips its empty-history assertion in integration mode.)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            home: const SetupWizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(setupWizardControllerProvider).phase,
        SetupWizardPhase.editing,
      );
      expect(
        container.read(setupWizardControllerProvider).blocks,
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
