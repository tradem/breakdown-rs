// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/data/settings/easter_eggs_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/easter_eggs/dejavu_cat.dart';
import 'package:frontend_flutter/features/easter_eggs/easter_eggs_screen.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// In-memory `SharedPreferencesAsyncPlatform` double forced to fail every
/// operation (write-failure snackbar test, migrated from the settings
/// screen test with the move to the dedicated screen, issue #708).
final class _FailingWritePrefsPlatform extends InMemorySharedPreferencesAsync {
  _FailingWritePrefsPlatform() : super.empty();

  @override
  Future<bool> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async => throw Exception('storage unavailable');
}

/// Pumps a bounded number of frames (never `pumpAndSettle` against
/// open-ended timers).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  /// Screen host: the dedicated Easter-eggs screen as the app home with
  /// the composition it needs — only the preference platform (the screen
  /// is local-only: no db, no API client, no membership gate).
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool disableAnimations = false,
    // Simulates a bootstrap preference-read failure (HydratedEasterEggs
    // carries the visible-error flag; issue #516 spec scenario).
    bool easterEggsReadFailed = false,
    // Simulates a failing on-device preference write (snackbar test).
    bool failPrefsWrite = false,
    // Null = bare test tree (l10nOf falls back to the English catalog —
    // English-copy assertions). Goldens pass `Locale('de')`: AGENTS.md
    // §9 — goldens use the German template locale.
    Locale? locale,
  }) async {
    if (failPrefsWrite) {
      SharedPreferencesAsyncPlatform.instance = _FailingWritePrefsPlatform();
    } else {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    }
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        if (easterEggsReadFailed)
          for (final id in EasterEggId.values)
            easterEggProvider(id).overrideWith(
              () => HydratedEasterEggs(id, initial: true, failed: true),
            ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            platformBrightness: brightness,
            disableAnimations: disableAnimations,
          ),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    // Push the screen like the settings entry tile does — the AppBar
    // back affordance only renders on a pushed route.
    unawaited(
      Navigator.of(
        tester.element(find.byType(Scaffold)),
      ).push(MaterialPageRoute<void>(builder: (_) => const EasterEggsScreen())),
    );
    await pumpFrames(tester);
    return container;
  }

  group('EasterEggsScreen (issue #708)', () {
    testWidgets('dedicated screen renders root, app bar, one switch per egg', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('easter-eggs-screen')), findsOneWidget);
      expect(find.byKey(const Key('easter-eggs-appbar')), findsOneWidget);
      // Screen-reader-visible title (l10nOf falls back to the English
      // catalog in bare test trees).
      expect(find.text('Easter eggs'), findsOneWidget);
      // Back navigation affordance present (like SettingsScreen).
      expect(find.byType(BackButton), findsOneWidget);
      // One switch per registered egg (issue #615), default ON — the
      // complete per-egg functionality moved here unchanged.
      for (final id in EasterEggId.values) {
        final key = Key('settings-egg-${id.name}');
        expect(find.byKey(key), findsOneWidget);
        expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
      }
      // The gallery section moved along (issue #640).
      expect(
        find.byKey(const Key('settings-egg-preview-karlKleiderbuegel')),
        findsOneWidget,
      );
    });
  });

  group('EasterEggsScreen per-egg switches (issue #615, moved #708)', () {
    testWidgets('toggling one egg flips only its notifier immediately', (
      tester,
    ) async {
      final container = await pumpScreen(tester);

      final karlFlips = <bool>[];
      container.listen(
        easterEggProvider(EasterEggId.karlKleiderbuegel),
        (_, v) => karlFlips.add(v),
      );

      await tester.tap(find.byKey(const Key('settings-egg-karlKleiderbuegel')));
      await pumpFrames(tester);

      expect(
        container.read(easterEggProvider(EasterEggId.karlKleiderbuegel)),
        isFalse,
      );
      // The other egg is untouched (per-egg independence).
      expect(container.read(easterEggProvider(EasterEggId.dejaVuCat)), isTrue);
      expect(karlFlips, [false]);
      // Persisted on-device under the flat per-egg key.
      expect(
        await SharedPreferencesAsync().getBool(
          EasterEggId.karlKleiderbuegel.prefsKey,
        ),
        isFalse,
      );
    });

    testWidgets('read-failure fallback: visible error subtitle, default ON', (
      tester,
    ) async {
      await pumpScreen(tester, easterEggsReadFailed: true);

      for (final id in EasterEggId.values) {
        final key = Key('settings-egg-${id.name}');
        expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
        expect(
          find.byKey(Key('settings-egg-${id.name}-error')),
          findsOneWidget,
        );
      }
    });

    testWidgets('write failure: localized snackbar, no silent discard', (
      tester,
    ) async {
      await pumpScreen(tester, failPrefsWrite: true);

      await tester.tap(find.byKey(const Key('settings-egg-dejaVuCat')));
      await pumpFrames(tester);

      // The in-memory flip still applied...
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EasterEggsScreen)),
      );
      expect(container.read(easterEggProvider(EasterEggId.dejaVuCat)), isFalse);
      // ...and the persistence failure surfaces as a localized snackbar.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('could not be saved'), findsOneWidget);
    });
  });

  group('EasterEggsScreen gallery (issue #640, moved #708)', () {
    testWidgets('preview per egg renders month-independently when ON', (
      tester,
    ) async {
      // The gallery bypasses ONLY the October month gate — no clock
      // setup here, and still both previews render.
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('settings-egg-preview-karlKleiderbuegel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-egg-preview-dejaVuCat')),
        findsOneWidget,
      );
      // The cat preview is the walker (same figure the splash uses).
      expect(find.byType(DejaVuCatWalker), findsOneWidget);
    });

    testWidgets('flipping an egg off removes only its preview', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('settings-egg-dejaVuCat')));
      await pumpFrames(tester);

      expect(
        find.byKey(const Key('settings-egg-preview-dejaVuCat')),
        findsNothing,
      );
      // The other egg's preview is untouched (per-egg independence).
      expect(
        find.byKey(const Key('settings-egg-preview-karlKleiderbuegel')),
        findsOneWidget,
      );
    });

    testWidgets('remove-animations: the cat preview renders statically', (
      tester,
    ) async {
      await pumpScreen(tester, disableAnimations: true);

      expect(
        find.byKey(const Key('settings-egg-preview-dejavu-cat')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('EasterEggsScreen goldens (issue #708)', () {
    testWidgets('light', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.light,
        // AGENTS.md §9: goldens use the German template locale.
        locale: const Locale('de'),
      );
      await expectLater(
        find.byKey(const Key('easter-eggs-screen')),
        matchesGoldenFile('goldens/easter_eggs_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpScreen(
        tester,
        brightness: Brightness.dark,
        locale: const Locale('de'),
      );
      await expectLater(
        find.byKey(const Key('easter-eggs-screen')),
        matchesGoldenFile('goldens/easter_eggs_dark.png'),
      );
    });
  });
}
