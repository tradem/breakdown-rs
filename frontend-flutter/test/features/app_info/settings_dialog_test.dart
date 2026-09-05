// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';
import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/settings/api_base_override_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/app_info/settings_dialog.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (dialog animations settle within a few
/// frames; never `pumpAndSettle` against open-ended timers).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// In-memory secure-storage double backing [ApiBaseOverrideStore.secure].
class _OverridePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => store.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      store.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}

const _prodConfig = AppConfig(
  flavor: Flavor.prod,
  apiBase: 'https://api.breakdown.rs',
  oidcIss: 'https://idp.example',
  devAuthSub: '',
  oidcAudience: 'breakdown-api',
  oidcClientId: 'client',
  oidcRedirectUri: 'breakdown://redirect',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: '',
);

void main() {
  late _OverridePlatform platform;
  late CacheDatabase db;
  late ProviderContainer container;

  /// Dialog host with full composition (db, repo, token store, pinned
  /// context). The seasons fetch is holder-driven unless [realFetch] turns
  /// on the genuine transport (unreachable-base test).
  Future<void> pumpDialog(
    WidgetTester tester, {
    AppConfig config = devAuthConfig,
    Brightness brightness = Brightness.light,
    double textScaler = 1.0,
    bool realFetch = false,
    List<SeasonView> initialRows = const [],
    // Simulates post-boot state with a persisted override already applied
    // (bootstrap merges it into the effective base before any client
    // exists — task 6.1).
    String? activeOverride,
  }) async {
    platform = _OverridePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final holder = ValueNotifier<Result<List<SeasonView>>>(Right(initialRows));
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        pinnedSecurityContextProvider.overrideWithValue(SecurityContext()),
        cacheDatabaseProvider.overrideWithValue(db),
        // Provider-backed repository (review): the fake wraps the REAL
        // injected client, so the post-switch request below proves the
        // rebuilt `apiDioProvider` base instead of a hand-built client.
        seasonRepositoryProvider.overrideWith(
          (ref) => FakeSeasonRepository(
            ref.watch(apiClientProvider),
            SeasonCacheDao(ref.watch(cacheDatabaseProvider)),
          ),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          if (realFetch) {
            return r.fetchAndCacheList(() async {
              final one = await r.get('x');
              return one.match(
                (e) => Left<ProblemError, List<SeasonView>>(e),
                (_) => const Right<ProblemError, List<SeasonView>>([]),
              );
            });
          }
          return r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);
    if (activeOverride != null) {
      platform.store[ApiBaseOverrideStore.key] = activeOverride;
      container.read(runtimeApiBaseProvider.notifier).set(activeOverride);
    }
    if (config.devAuthMode) {
      await container.read(authSessionControllerProvider.notifier).signIn();
    }
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            platformBrightness: brightness,
            textScaler: TextScaler.linear(textScaler),
          ),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    unawaited(showSettingsDialog(tester.element(find.byType(Scaffold))));
    await pumpFrames(tester);
  }

  Future<void> enterUri(WidgetTester tester, String uri) async {
    await tester.enterText(find.byKey(const Key('settings-uri-field')), uri);
    await pumpFrames(tester);
  }

  group('SettingsDialog dev (task 6.4/6.6)', () {
    testWidgets('shows base, flavor, and the editor', (tester) async {
      await pumpDialog(tester);

      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-base')),
          matching: find.text('http://10.0.2.2:3000'),
        ),
        findsOneWidget,
      );
      expect(find.text('dev'), findsOneWidget);
      expect(find.byKey(const Key('settings-uri-field')), findsOneWidget);
      expect(find.byKey(const Key('settings-prod-note')), findsNothing);
    });

    testWidgets('invalid input rejected inline, no save', (tester) async {
      await pumpDialog(tester);

      await enterUri(tester, 'not-a-uri');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester);

      expect(find.textContaining('absolute address'), findsOneWidget);
      expect(platform.store.isEmpty, isTrue);
      expect(container.read(runtimeApiBaseProvider), isNull);
      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    });

    testWidgets('non-loopback http rejected inline (CWE-319)', (tester) async {
      await pumpDialog(tester);

      await enterUri(tester, 'http://192.168.1.10:3000');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester);

      expect(find.textContaining('loopback'), findsOneWidget);
      expect(platform.store.isEmpty, isTrue);
    });

    testWidgets('valid save persists, rebuilds, closes', (tester) async {
      await pumpDialog(tester);
      final dioBefore = container.read(apiDioProvider);

      await enterUri(tester, 'https://dev.example:4000/');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester, n: 12);

      expect(
        platform.store[ApiBaseOverrideStore.key],
        'https://dev.example:4000',
      );
      expect(
        container.read(runtimeApiBaseProvider),
        'https://dev.example:4000',
      );
      final dioAfter = container.read(apiDioProvider);
      expect(identical(dioAfter, dioBefore), isFalse);
      expect(dioAfter.options.baseUrl, 'https://dev.example:4000');
      expect(find.byKey(const Key('settings-dialog')), findsNothing);
    });

    testWidgets('reset clears the override and restores the default', (
      tester,
    ) async {
      await pumpDialog(tester, activeOverride: 'https://dev.example:4000');
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-base')),
          matching: find.text('https://dev.example:4000'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings-reset')));
      await pumpFrames(tester, n: 12);

      expect(platform.store.isEmpty, isTrue);
      expect(container.read(runtimeApiBaseProvider), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-base')),
          matching: find.text('http://10.0.2.2:3000'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    });

    testWidgets('unreachable base: transport error keyed on code', (
      tester,
    ) async {
      await pumpDialog(tester, realFetch: true);

      await enterUri(tester, 'http://127.0.0.1:9');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester, n: 12);

      // Save accepted (loopback http is valid); dialog closed…
      expect(find.byKey(const Key('settings-dialog')), findsNothing);
      // …against the rebuilt client targeting the switched base…
      expect(
        container.read(apiDioProvider).options.baseUrl,
        'http://127.0.0.1:9',
      );
      // …and the real fetch against the unreachable base fails transport.
      // Real socket IO must run outside the fake-async test zone
      // (same `runAsync` pattern as the seasons offline widget test).
      final fetch = (await tester.runAsync(
        () => container.read(seasonsListFetchProvider.future),
      ))!;
      final code = fetch.getLeft().toNullable()?.code ?? '';
      expect(code.startsWith('transport.'), isTrue);
    });

    testWidgets('holds at textScaler 1.3 without overflow', (tester) async {
      await pumpDialog(tester, textScaler: 1.3);

      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsDialog prod (task 6.4/6.6)', () {
    testWidgets('editor absent, read-only base with explanation', (
      tester,
    ) async {
      await pumpDialog(tester, config: _prodConfig);

      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
      expect(find.text('https://api.breakdown.rs'), findsOneWidget);
      expect(find.text('prod'), findsOneWidget);
      expect(find.byKey(const Key('settings-uri-field')), findsNothing);
      expect(find.byKey(const Key('settings-save')), findsNothing);
      expect(find.byKey(const Key('settings-reset')), findsNothing);
      expect(find.byKey(const Key('settings-prod-note')), findsOneWidget);
      expect(
        find.textContaining('set by your organization for security'),
        findsOneWidget,
      );
    });
  });

  group('SettingsDialog goldens (task 6.6)', () {
    testWidgets('dev light', (tester) async {
      await pumpDialog(tester, brightness: Brightness.light);
      await expectLater(
        find.byType(SettingsDialog),
        matchesGoldenFile('goldens/settings_dev_light.png'),
      );
    });

    testWidgets('dev dark', (tester) async {
      await pumpDialog(tester, brightness: Brightness.dark);
      await expectLater(
        find.byType(SettingsDialog),
        matchesGoldenFile('goldens/settings_dev_dark.png'),
      );
    });

    testWidgets('prod light', (tester) async {
      await pumpDialog(tester, config: _prodConfig);
      await expectLater(
        find.byType(SettingsDialog),
        matchesGoldenFile('goldens/settings_prod_light.png'),
      );
    });

    testWidgets('prod dark', (tester) async {
      await pumpDialog(
        tester,
        config: _prodConfig,
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(SettingsDialog),
        matchesGoldenFile('goldens/settings_prod_dark.png'),
      );
    });
  });
}
