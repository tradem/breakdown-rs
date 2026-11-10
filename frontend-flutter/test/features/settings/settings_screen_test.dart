// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
import 'package:frontend_flutter/auth/capabilities.dart';
import 'package:frontend_flutter/auth/active_block_store.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_config_repository.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/settings/api_base_override_store.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_controller.dart';
import 'package:frontend_flutter/features/easter_eggs/easter_eggs_screen.dart';
import 'package:frontend_flutter/features/settings/settings_screen.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/src/health/backend_health_providers.dart';
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

/// The GRANTED global capability answer (issue #816): the credential gate is
/// open, ops is not — the ordinary Settings entry state.
const _grantedCapabilities = MyCapabilities(
  canManageAiConfig: true,
  canReadOps: false,
);

/// The RESOLVED DENIAL of the global credential predicate (issue #816): the
/// caller may not manage the AI configuration — an answer, not an absence.
const _deniedCapabilities = MyCapabilities(
  canManageAiConfig: false,
  canReadOps: false,
);

/// Counts AI-config discovery dispatches (issue #816): the pre-tap denial must
/// suppress the read entirely, so a request that never happens is the
/// assertion — not a rendered state that a 403 could have produced anyway.
class _CountingAiConfigRepository extends AiConfigRepository {
  _CountingAiConfigRepository(super.api, this.onDiscovery);

  final void Function() onDiscovery;

  @override
  Future<Result<List<AiConfigView>>> listConfigs() async {
    onDiscovery();
    return const Right(<AiConfigView>[]);
  }

  @override
  Future<Result<List<AiProviderInfo>>> listProviders() async =>
      const Right(<AiProviderInfo>[]);
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
    // Reachability probe seam (issue #809): injected so no real health IO
    // ever runs — a never-completing future pins the "unknown" state and a
    // throwing/`BackendHealthUnreachable` one the unreachable state, with no
    // wall-clock gating (AGENTS.md §6).
    BackendHealthProbe? healthProbe,
    // Exact pre-tap capability seam (issue #816): same discipline as the
    // health probe. The default reports the GRANTED capability so every
    // pre-#816 test keeps its ordinary subtitle; the four entry states are
    // injected explicitly by the tests below.
    MyCapabilitiesFetch? capabilitiesFetch,
    // Pre-seeded secure-storage documents (issue #809: the stale persisted
    // block scope a dev data reset leaves behind).
    Map<String, String> secureSeed = const {},
    // Golden locale (AGENTS.md §9: goldens use the German template). Null
    // keeps the historical English fallback of `l10nOf`, so the four base
    // Settings goldens keep their current output (CodeRabbit review).
    Locale? locale,
  }) async {
    platform = _OverridePlatform();
    platform.store.addAll(secureSeed);
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
        // The AI-config entry's one-shot reachability probe (issue #809):
        // the default reports a reachable backend so the entry renders its
        // ordinary subtitle; tests inject the other states.
        backendHealthProbeProvider.overrideWithValue(
          healthProbe ??
              () async => const BackendHealthReported(HealthStatus.healthy),
        ),
        // The exact pre-tap credential predicate (issue #816): granted by
        // default, injected per state by the tests.
        myCapabilitiesFetchProvider.overrideWithValue(
          capabilitiesFetch ?? () async => const Right(_grantedCapabilities),
        ),
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
            locale: locale,
            localizationsDelegates: locale == null
                ? null
                : AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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

  group('SettingsScreen AI-config entry (issues #643 / #809)', () {
    const seasonId = 'season-1';

    /// Marks the sticky active-block scope. Kept in the tests that used to
    /// depend on it: the point of issue #809 is that the entry's PRESENCE
    /// no longer changes with the scope at all — only its subtitle changes
    /// with the reachability probe.
    void setActiveScope() => container
        .read(activeBlockProvider.notifier)
        .set(seasonId: seasonId, blockId: 'block-1');

    /// The pushed screen's discovery seams — immediate, benign first-run
    /// values; no network ever runs (same pattern as the
    /// ai_config_screen_test harness).
    List<dynamic> screenSeams({ProblemError? discoveryError}) => [
      aiConfigDiscoveryProvider.overrideWith(
        (ref) async => discoveryError == null
            ? const Right(<AiConfigView>[])
            : Left<ProblemError, List<AiConfigView>>(discoveryError),
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
    ];

    testWidgets('cold start without any scope: the entry is rendered, '
        'tappable, and its subtitle says the state is being resolved', (
      tester,
    ) async {
      // Never-completing probe: the "unknown" state is pinned for the whole
      // test — no wall-clock gating (AGENTS.md §6).
      final never = Completer<BackendHealthOutcome>();
      await pumpScreen(tester, healthProbe: () => never.future);

      // Issue #809 C1: the entry is NEVER hidden by an unresolved scope
      // (this replaces the former 'hidden without an active-block scope'
      // test, which locked the defect in).
      final tile = find.byKey(const Key('settings-ai-config'));
      expect(tile, findsOneWidget);
      expect(
        find.text('Checking backend…'),
        findsOneWidget,
        reason: 'the state is rendered, not omitted',
      );
      expect(
        find.byKey(const Key('settings-ai-config-checking')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);
    });

    testWidgets('entry stays rendered while the season membership is pending '
        '(a pending fetch no longer hides a configuration entry)', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          // Never-completing fetch: the membership stays unresolved for the
          // whole test.
          membershipFetchProvider(seasonId).overrideWith(
            (ref) => Completer<Result<SeasonMembershipDto>>().future,
          ),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      // The gate input really is unresolved here (the provider is
      // autoDispose, so a bare `read` would start-and-drop it): subscribe,
      // then assert.
      final subscription = container.listen(
        currentMembershipProvider(seasonId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await pumpFrames(tester);
      expect(
        container.read(currentMembershipProvider(seasonId)).hasValue,
        isFalse,
        reason: 'the membership gate really is unresolved here',
      );
      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsOneWidget,
      );
    });

    testWidgets('entry stays rendered on a resolved denial', (tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          membershipFetchProvider(seasonId)
              .overrideWith((ref) async => Right(_membership(hasRole: false))),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      // The gate input really is a resolved denial (autoDispose provider:
      // subscribe so it survives the resolution).
      final subscription = container.listen(
        currentMembershipProvider(seasonId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await pumpFrames(tester);
      expect(
        container
            .read(currentMembershipProvider(seasonId))
            .value
            ?.hasActiveCostumeRoleInSeason,
        isFalse,
      );
      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
    });

    testWidgets('entry stays rendered after a failed membership fetch (a '
        'failed read is not a denial)', (tester) async {
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

      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
    });

    testWidgets('reachable backend: the ordinary subtitle, ≥ 48×48 dp, one '
        'merged tappable semantics node', (tester) async {
      await pumpScreen(tester);
      setActiveScope();
      await pumpFrames(tester);

      final tile = find.byKey(const Key('settings-ai-config'));
      expect(tile, findsOneWidget);
      // Localized copy (glossary keys settings.aiConfig*); l10nOf falls back
      // to the English catalog in bare test trees.
      expect(find.text('AI configuration'), findsOneWidget);
      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsOneWidget,
      );
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

    testWidgets('unreachable backend: localized unreachable subtitle + a '
        'working Retry, and no "no configuration" claim (issue #809 C2)', (
      tester,
    ) async {
      var calls = 0;
      Future<BackendHealthOutcome> probe() async {
        calls++;
        // First probe: no answer at all. Every later probe: the backend
        // answers (the retry path).
        return calls == 1
            ? const BackendHealthUnreachable()
            : const BackendHealthReported(HealthStatus.healthy);
      }

      await pumpScreen(tester, healthProbe: probe);

      const unreachableCopy = 'Backend not reachable yet';
      expect(find.text(unreachableCopy), findsOneWidget);
      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsNothing,
        reason: 'a failed read is not a configuration claim',
      );
      expect(find.byKey(const Key('settings-ai-config-retry')), findsOneWidget);
      // …and the entry still opens the screen (never blocked by "unknown").
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('settings-ai-config')))
            .onTap,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('settings-ai-config-retry')));
      await pumpFrames(tester);

      expect(calls, 2, reason: 'the Retry re-runs exactly one probe');
      expect(find.text(unreachableCopy), findsNothing);
      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsOneWidget,
      );
    });

    testWidgets('granted capability: the ordinary subtitle, no denial state '
        'and no Retry (issue #816)', (tester) async {
      await pumpScreen(
        tester,
        capabilitiesFetch: () async => const Right(_grantedCapabilities),
      );

      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsOneWidget,
      );
      expect(find.text('No permission'), findsNothing);
      expect(find.byKey(const Key('settings-ai-config-denied')), findsNothing);
      expect(find.byKey(const Key('settings-ai-config-retry')), findsNothing);
    });

    testWidgets('resolved denial: "No permission" BEFORE the tap — a state, '
        'never a hidden entry, never a Retry (issue #816)', (tester) async {
      await pumpScreen(
        tester,
        capabilitiesFetch: () async => const Right(_deniedCapabilities),
      );

      expect(find.text('No permission'), findsOneWidget);
      expect(
        find.byKey(const Key('settings-ai-config-denied')),
        findsOneWidget,
        reason: 'the state is visible, not just textual',
      );
      expect(
        find.byKey(const Key('settings-ai-config-retry')),
        findsNothing,
        reason: 'retrying cannot flip a role',
      );
      expect(
        find.text('Manage the AI provider and models for AI import.'),
        findsNothing,
        reason: 'a denial must not read as if the permission existed',
      );
      // #809 rule: the entry is a state, never an absence.
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('settings-ai-config')))
            .onTap,
        isNotNull,
      );
    });

    testWidgets('pending capability: "Checking backend…" — unknown is not a '
        'denial (issue #816)', (tester) async {
      final never = Completer<Result<MyCapabilities>>();
      await pumpScreen(tester, capabilitiesFetch: () => never.future);

      expect(find.text('Checking backend…'), findsOneWidget);
      expect(find.text('No permission'), findsNothing);
      expect(
        find.byKey(const Key('settings-ai-config-checking')),
        findsOneWidget,
      );
    });

    testWidgets(
      'failed capability read: UNKNOWN, never a denial — the ordinary '
      'subtitle and no lock icon (issue #816)',
      (tester) async {
        await pumpScreen(
          tester,
          capabilitiesFetch: () async => Left<ProblemError, MyCapabilities>(
            const ProblemError(code: 'transport.connectionError'),
          ),
        );

        expect(find.text('No permission'), findsNothing);
        expect(
          find.byKey(const Key('settings-ai-config-denied')),
          findsNothing,
        );
        expect(
          find.text('Manage the AI provider and models for AI import.'),
          findsOneWidget,
          reason: 'an unknown capability keeps the server authoritative',
        );
      },
    );

    testWidgets('a resolved denial dispatches ZERO config reads: the screen '
        'renders the administrator narrative without a request (issue #816)', (
      tester,
    ) async {
      var discoveryCalls = 0;
      await pumpScreen(
        tester,
        capabilitiesFetch: () async => const Right(_deniedCapabilities),
        extraOverrides: [
          aiConfigRepositoryProvider.overrideWith(
            (ref) => _CountingAiConfigRepository(
              ref.watch(apiClientProvider),
              () => discoveryCalls++,
            ),
          ),
          aiProvidersProvider.overrideWith(
            (ref) async => const Right(<AiProviderInfo>[]),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateReconciliationScheduler(),
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('settings-ai-config')));
      await pumpFrames(tester, n: 12);

      expect(
        find.byKey(const Key('ai-config-discovery-forbidden')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-config-discovery-retry')),
        findsNothing,
        reason: 'a denial is not a retryable load error',
      );
      expect(
        discoveryCalls,
        0,
        reason: 'a resolved denial must never provoke the read it pre-empts',
      );
    });

    testWidgets('tap pushes the existing AiConfigScreen (no new screen)', (
      tester,
    ) async {
      await pumpScreen(tester, extraOverrides: screenSeams());
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

    testWidgets('resolved denial: the entry is present and the screen renders '
        'the server\'s administrator narrative WITHOUT a retry (D4)', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          membershipFetchProvider(seasonId)
              .overrideWith((ref) async => Right(_membership(hasRole: false))),
          ...screenSeams(
            discoveryError: const ProblemError(
              code: 'ai-config.forbidden',
              status: 403,
            ),
          ),
        ],
      );
      setActiveScope();
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-ai-config')));
      await pumpFrames(tester, n: 12);

      expect(
        find.byKey(const Key('ai-config-discovery-forbidden')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-config-discovery-retry')),
        findsNothing,
        reason: 'a 403 is a denial, not a retryable load error',
      );
      expect(
        find.byKey(const Key('ai-config-backend-unreachable')),
        findsNothing,
        reason: 'a denial is not an unreachable backend',
      );
    });

    testWidgets('post-reset stale state: a persisted season anchor that '
        'resolves to no row and a deleted block scope leave the entry '
        'rendered and reachable (issue #809)', (tester) async {
      await pumpScreen(
        tester,
        extraOverrides: screenSeams(),
        // The `business` dev reset leaves the per-season block scope behind
        // (a deleted block) — issued #809's second defect input.
        secureSeed: {
          ActiveBlockStore.key:
              '{"season-deleted": {"blockId": "block-deleted", '
              '"number": 1}}',
        },
      );

      // …and the persisted season anchor names a season the projection no
      // longer serves (driven through the REAL resolution providers, not by
      // poking activeBlockProvider).
      final session = await container.read(
        authSessionControllerProvider.future,
      );
      final write = await container
          .read(shellStateDaoProvider)
          .upsert(
            key: activeSeasonKeyFor(session?.sub),
            value: 'season-deleted',
            cachedAt: DateTime.utc(2026, 11, 3),
          );
      expect(write.isRight(), isTrue);
      container.invalidate(activeSeasonPersistedProvider);
      await pumpFrames(tester);

      // The dead state is real (both documents name data that is gone)…
      expect(
        await container.read(activeSeasonResolutionProvider.future),
        isNull,
        reason: 'a persisted id that matches no season row resolves to null',
      );
      expect(
        (await container.read(activeBlockPersistedProvider.future)).keys,
        contains('season-deleted'),
      );
      // …and it no longer disables the entry.
      final tile = find.byKey(const Key('settings-ai-config'));
      expect(tile, findsOneWidget);
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);

      await tester.tap(tile);
      await pumpFrames(tester, n: 12);
      expect(find.byKey(const Key('ai-config-screen')), findsOneWidget);
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

    // Issue #643 / #809: the AI-config entry in its states. Issue #809
    // replaced the "visible vs hidden" pair (the entry is always rendered
    // now) with one golden per REACHABILITY state, {light,dark} × android —
    // so a change that lets the entry disappear (or drops a state's copy)
    // cannot pass silently. The entry is captured alone: the state is the
    // subject, and a tile-scoped capture keeps the diff readable.
    Future<void> pumpEntryGolden(
      WidgetTester tester, {
      required String golden,
      required Brightness brightness,
      BackendHealthProbe? healthProbe,
      MyCapabilitiesFetch? capabilitiesFetch,
    }) async {
      await pumpScreen(
        tester,
        brightness: brightness,
        healthProbe: healthProbe,
        capabilitiesFetch: capabilitiesFetch,
        locale: const Locale('de'),
      );
      expect(find.byKey(const Key('settings-ai-config')), findsOneWidget);
      await expectLater(
        find.byKey(const Key('settings-ai-config')),
        matchesGoldenFile('goldens/$golden'),
      );
    }

    testWidgets('ai-config entry reachable, light', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_reachable_light.png',
        brightness: Brightness.light,
      );
    });

    testWidgets('ai-config entry reachable, dark', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_reachable_dark.png',
        brightness: Brightness.dark,
      );
    });

    testWidgets('ai-config entry checking, light', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_checking_light.png',
        brightness: Brightness.light,
        // Never-completing probe: pins the "unknown" state (no wall clock).
        healthProbe: () => Completer<BackendHealthOutcome>().future,
      );
    });

    testWidgets('ai-config entry checking, dark', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_checking_dark.png',
        brightness: Brightness.dark,
        healthProbe: () => Completer<BackendHealthOutcome>().future,
      );
    });

    // Issue #816: the resolved-denial state is golden-covered as well, so a
    // later "hide the entry when denied" regression (the #809 defect, one
    // permission narrower) cannot pass review.
    testWidgets('ai-config entry denied, light', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_denied_light.png',
        brightness: Brightness.light,
        capabilitiesFetch: () async => const Right(_deniedCapabilities),
      );
    });

    testWidgets('ai-config entry denied, dark', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_denied_dark.png',
        brightness: Brightness.dark,
        capabilitiesFetch: () async => const Right(_deniedCapabilities),
      );
    });

    testWidgets('ai-config entry unreachable, light', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_unreachable_light.png',
        brightness: Brightness.light,
        healthProbe: () async => const BackendHealthUnreachable(),
      );
    });

    testWidgets('ai-config entry unreachable, dark', (tester) async {
      await pumpEntryGolden(
        tester,
        golden: 'settings_ai_config_unreachable_dark.png',
        brightness: Brightness.dark,
        healthProbe: () async => const BackendHealthUnreachable(),
      );
    });
  });
}
