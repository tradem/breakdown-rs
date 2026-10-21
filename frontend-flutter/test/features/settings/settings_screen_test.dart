// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

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
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/settings/api_base_override_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_controller.dart';
import 'package:frontend_flutter/features/easter_eggs/easter_eggs_screen.dart';
import 'package:frontend_flutter/features/settings/settings_screen.dart';
import 'package:frontend_flutter/src/network/api_client.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` against
/// open-ended timers).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A season membership DTO with an explicit backend-computed costume-role
/// flag (issue #643: the AI-config entry gate input).
SeasonMembershipDto _membership({required bool hasRole}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = hasRole
    ..capabilities.replace(const <String>[]),
);

/// Immediate reconciliation scheduler (issue #643 push test): ticks are
/// no-ops — no wall-clock gating (AGENTS.md §6).
class _ImmediateReconciliationScheduler extends ReconciliationScheduler {
  const _ImmediateReconciliationScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
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
  defaultProjectId: '',
);

void main() {
  late _OverridePlatform platform;
  late CacheDatabase db;
  late ProviderContainer container;

  /// Screen host with full composition (db, repo, token store, pinned
  /// context). The seasons fetch is holder-driven unless [realFetch] turns
  /// on the genuine transport (unreachable-base test).
  Future<void> pumpScreen(
    WidgetTester tester, {
    AppConfig config = devAuthConfig,
    Brightness brightness = Brightness.light,
    double textScaler = 1.0,
    bool realFetch = false,
    // Simulates post-boot state with a persisted override already applied
    // (bootstrap merges it into the effective base before any client
    // exists — task 6.1).
    String? activeOverride,
    // Extra provider overrides appended after the base set (issue #643:
    // the AI-config entry tests override the season membership fetch).
    // `List<dynamic>` like app_shell_test's harness — Riverpod 3 does
    // not export the `Override` type for user code.
    List<dynamic> extraOverrides = const [],
  }) async {
    platform = _OverridePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    // The pushed Easter-eggs screen hydrates its per-egg notifiers from
    // preferences — the in-memory platform keeps that benign (issue #708).
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final holder = ValueNotifier<Result<List<SeasonView>>>(Right(const []));
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
        ...extraOverrides,
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
    // Push the screen like the profile menu does (no dialog).
    unawaited(
      Navigator.of(
        tester.element(find.byType(Scaffold)),
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    );
    await pumpFrames(tester);
  }

  Future<void> enterUri(WidgetTester tester, String uri) async {
    await tester.enterText(find.byKey(const Key('settings-uri-field')), uri);
    await pumpFrames(tester);
  }

  group('SettingsScreen dev (issue #516)', () {
    testWidgets('pushed as a full screen, not a dialog', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
      expect(find.byKey(const Key('settings-dialog')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // Back navigation affordance present.
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('easter-eggs entry tile present, switches moved (#708)', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Issue #708: the inline per-egg sections are GONE — one entry
      // tile pushes the dedicated [EasterEggsScreen] instead (the
      // counter-model of the AI-config entry, issue #643).
      final tile = find.byKey(const Key('settings-easter-eggs-entry'));
      expect(tile, findsOneWidget);
      expect(
        find.byKey(const Key('settings-egg-karlKleiderbuegel')),
        findsNothing,
      );
      expect(find.byKey(const Key('settings-egg-dejaVuCat')), findsNothing);
      expect(
        find.byKey(const Key('settings-egg-preview-karlKleiderbuegel')),
        findsNothing,
      );
      // Localized general-section copy (l10nOf falls back to the English
      // catalog in bare test trees) + the chevron affordance.
      expect(find.text('Manage Easter eggs'), findsOneWidget);
      expect(
        find.text('Switches and a preview for every egg.'),
        findsOneWidget,
      );
      final size = tester.getSize(tile);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('easter-eggs entry tap pushes the dedicated screen', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('settings-easter-eggs-entry')));
      await pumpFrames(tester, n: 12);

      expect(find.byType(EasterEggsScreen), findsOneWidget);
      expect(find.byKey(const Key('easter-eggs-screen')), findsOneWidget);
      // The settings screen stays below on the same navigator stack
      // (offstage after the push — finder must include offstage trees).
      expect(
        find.byKey(const Key('settings-screen'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('shows base, flavor, and the dev editor', (tester) async {
      await pumpScreen(tester);

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
      await pumpScreen(tester);

      await enterUri(tester, 'not-a-uri');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester);

      expect(find.textContaining('absolute address'), findsOneWidget);
      expect(platform.store.isEmpty, isTrue);
      expect(container.read(runtimeApiBaseProvider), isNull);
      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
    });

    testWidgets('non-loopback http rejected inline (CWE-319)', (tester) async {
      await pumpScreen(tester);

      await enterUri(tester, 'http://192.168.1.10:3000');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester);

      expect(find.textContaining('loopback'), findsOneWidget);
      expect(platform.store.isEmpty, isTrue);
    });

    testWidgets('valid save persists and rebuilds the client', (tester) async {
      await pumpScreen(tester);
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
    });

    testWidgets('reset clears the override and restores the default', (
      tester,
    ) async {
      await pumpScreen(tester, activeOverride: 'https://dev.example:4000');
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
      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
    });

    testWidgets('unreachable base: transport error keyed on code', (
      tester,
    ) async {
      await pumpScreen(tester, realFetch: true);

      await enterUri(tester, 'http://127.0.0.1:9');
      await tester.tap(find.byKey(const Key('settings-save')));
      await pumpFrames(tester, n: 12);

      // Save accepted (loopback http is valid); the screen stays…
      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
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
      await pumpScreen(tester, textScaler: 1.3);

      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen prod (issue #516)', () {
    testWidgets('dev section absent; general section + read-only base remain', (
      tester,
    ) async {
      await pumpScreen(tester, config: _prodConfig);

      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
      expect(find.text('https://api.breakdown.rs'), findsOneWidget);
      expect(find.text('prod'), findsOneWidget);
      // The development section is dev-flavor-only…
      expect(find.byKey(const Key('settings-uri-field')), findsNothing);
      expect(find.byKey(const Key('settings-save')), findsNothing);
      expect(find.byKey(const Key('settings-reset')), findsNothing);
      // …while the Easter-eggs entry stays available (issue #708).
      expect(
        find.byKey(const Key('settings-easter-eggs-entry')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-prod-note')), findsOneWidget);
    });
  });

  group('SettingsScreen AI-config entry (issue #643)', () {
    const seasonId = 'season-1';

    /// Marks the sticky active-block scope — the tile's only ambient
    /// season context. Dev-auth mode short-circuits the membership
    /// fetch to the permissive DTO, so no network runs.
    void setActiveScope() => container
        .read(activeBlockProvider.notifier)
        .set(seasonId: seasonId, blockId: 'block-1');

    testWidgets('hidden without an active-block scope', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsNothing);
    });

    testWidgets('hidden while the membership fetch is pending (D3: hide, '
        'never deny)', (tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          // Never-completing fetch: the gate stays unresolved for the
          // whole test — no wall-clock gating (AGENTS.md §6).
          membershipFetchProvider(seasonId).overrideWith(
            (ref) => Completer<Result<SeasonMembershipDto>>().future,
          ),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsNothing);
    });

    testWidgets('hidden on a resolved denial', (tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          membershipFetchProvider(seasonId)
              .overrideWith((ref) async => Right(_membership(hasRole: false))),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsNothing);
    });

    testWidgets('hidden after a membership fetch failure', (tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          membershipFetchProvider(seasonId).overrideWith(
            (ref) async =>
                const Left(ProblemError(code: 'transport.unreachable')),
          ),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsNothing);
    });

    testWidgets('visible on an active costume-dept membership, ≥ 48×48 dp', (
      tester,
    ) async {
      await pumpScreen(tester);
      setActiveScope();
      await pumpFrames(tester);

      final tile = find.byKey(const Key('settings-ai-config'));
      expect(tile, findsOneWidget);
      // Localized general-section copy (glossary keys settings.aiConfig*);
      // l10nOf falls back to the English catalog in bare test trees.
      expect(find.text('AI configuration'), findsOneWidget);
      // Screen-reader semantics (CodeRabbit review): the tile is one
      // merged, enabled, tappable node whose label carries the visible
      // title — a future change that makes it unusable with a screen
      // reader fails here (anchored to the settings-ai-config key).
      final semanticsHandle = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.byKey(const Key('settings-ai-config')),
      );
      expect(
        node,
        isSemantics(hasEnabledState: true, isEnabled: true, hasTapAction: true),
      );
      expect(node.label, contains('AI configuration'));
      semanticsHandle.dispose();
      final size = tester.getSize(tile);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('tap pushes the existing AiConfigScreen (no new screen)', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          // The pushed screen's discovery seams — immediate, benign
          // first-run values; no network ever runs (same pattern as the
          // ai_config_screen_test harness).
          aiConfigDiscoveryProvider.overrideWith(
            (ref) async => const Right(<AiConfigView>[]),
          ),
          aiProvidersProvider.overrideWith(
            (ref) async => const Right(<AiProviderInfo>[]),
          ),
          aiImportDefaultsProvider.overrideWith(
            (ref) async => Right(
              AiImportDefaults(
                (b) => b
                  ..script = ''
                  ..schedule = '',
              ),
            ),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateReconciliationScheduler(),
          ),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      await tester.tap(find.byKey(const Key('settings-ai-config')));
      await pumpFrames(tester, n: 12);

      expect(find.byKey(const Key('ai-config-screen')), findsOneWidget);
      // The settings screen stays below on the same navigator stack
      // (offstage after the push — finder must include offstage trees).
      expect(
        find.byKey(const Key('settings-screen'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('SettingsScreen AI section (issue #644, #672)', () {
    testWidgets(
      'AI section header renders; the AI-imports JOBS entry is GONE — '
      'it moved to the account drawer (issue #672)',
      (tester) async {
        await pumpScreen(tester, config: devAuthConfig);

        // Issue #672: the jobs list is operational, not a setting — the
        // Settings tile was removed in favor of the drawer entry
        // (`profile-ai-imports`). The AI-configuration entry stays.
        expect(find.byKey(const Key('settings-ai-imports')), findsNothing);
        expect(find.text('AI imports'), findsNothing);
        expect(find.text('AI'), findsOneWidget);
      },
    );
  });

  group('SettingsScreen goldens (issue #516)', () {
    testWidgets('dev light', (tester) async {
      await pumpScreen(tester, brightness: Brightness.light);
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_dev_light.png'),
      );
    });

    testWidgets('dev dark', (tester) async {
      await pumpScreen(tester, brightness: Brightness.dark);
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_dev_dark.png'),
      );
    });

    testWidgets('prod light', (tester) async {
      await pumpScreen(tester, config: _prodConfig);
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_prod_light.png'),
      );
    });

    testWidgets('prod dark', (tester) async {
      await pumpScreen(
        tester,
        config: _prodConfig,
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_prod_dark.png'),
      );
    });

    // Issue #643: the AI-config entry in its VISIBLE state (the four
    // base goldens above never set an active-block scope, so the gated
    // entry is absent there and those goldens stay valid).
    testWidgets('ai-config entry visible, light', (tester) async {
      await pumpScreen(tester, brightness: Brightness.light);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-1');
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_ai_config_light.png'),
      );
    });

    testWidgets('ai-config entry visible, dark', (tester) async {
      await pumpScreen(tester, brightness: Brightness.dark);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-1');
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('settings-screen')),
        matchesGoldenFile('goldens/settings_ai_config_dark.png'),
      );
    });
  });
}
