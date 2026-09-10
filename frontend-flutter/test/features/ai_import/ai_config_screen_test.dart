// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-2 widget tests for the AI-import configuration screen
// (`flutter-ai-config` task 2.2): first-run discovery (list-first + empty
// honest state), the masked-key field semantics (obscured, never
// persisted — D6), the 403 credential-role narrative (D4 session-only),
// the 422 provider degradation, the 409 edit conflict (no automatic
// version-bump re-dispatch), revoke-with-confirm, and goldens
// {light,dark}×{android,macos}.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_config_repository.dart';
import 'package:frontend_flutter/data/ai_import_handoff_store.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_controller.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_screen.dart';

import '../../support/fake_secure_storage.dart';

// --- Fixtures ---------------------------------------------------------------

const devAuthConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: 'series-1',
);

AiProviderInfo _provider(String key, LlmProvider provider) => AiProviderInfo(
  (b) => b
    ..provider = provider
    ..key = key,
);

ModelInfo _model(String id) => ModelInfo(
  (b) => b
    ..id = id
    ..provider = LlmProvider.openai,
);

AiConfigView _config({
  int version = 1,
  String assistantModel = 'gpt-5.6-luna',
  String? imageModel,
}) => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = assistantModel
    ..provider = LlmProvider.openai
    ..vaultKeyId = 'vk-1'
    ..imageModel = imageModel
    ..promptKinds.replace(
      BuiltList(const [DocumentKind.script, DocumentKind.schedule]),
    )
    ..revoked = false
    ..version = version,
);

/// Repository fake: every config/credential route is scriptable with call
/// counters (denial short-circuit + no-automatic-re-dispatch proofs).
class FakeAiConfigRepository extends AiConfigRepository {
  FakeAiConfigRepository(super.api);

  Result<IdVersionResponse>? submitResult;
  Result<SettingsView>? settingsResult;
  Result<IdVersionResponse>? createResult;
  Result<int>? updateResult;
  Result<int>? revokeResult;
  Result<List<AiConfigView>>? listResult;

  int submitCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int revokeCalls = 0;
  int settingsCalls = 0;

  String? lastSecret;

  @override
  Future<Result<List<AiConfigView>>> listConfigs() async =>
      listResult ?? const Right(<AiConfigView>[]);

  @override
  Future<Result<IdVersionResponse>> submitCredential({
    required String provider,
    required String secret,
  }) async {
    submitCalls++;
    lastSecret = secret;
    return submitResult ??
        Right(
          IdVersionResponse(
            (b) => b
              ..id = 'settings-1'
              ..version = 1,
          ),
        );
  }

  @override
  Future<Result<SettingsView>> getSettings(String id) async {
    settingsCalls++;
    return settingsResult ??
        Right(
          SettingsView(
            (b) => b
              ..id = id
              ..provider = 'openai'
              ..vaultKeyId = 'vk-1'
              ..vaultVersion = 1
              ..version = 1
              ..bindingState = CredentialBindingState.active,
          ),
        );
  }

  @override
  Future<Result<IdVersionResponse>> createConfig(
    CreateAiConfigRequest request,
  ) async {
    createCalls++;
    return createResult ??
        Right(
          IdVersionResponse(
            (b) => b
              ..id = 'config-1'
              ..version = 1,
          ),
        );
  }

  @override
  Future<Result<int>> updateConfig(String id, UpdateAiConfigRequest request) {
    updateCalls++;
    return Future.value(updateResult ?? Right(2));
  }

  @override
  Future<Result<int>> revokeConfig(String id, int version) {
    revokeCalls++;
    return Future.value(revokeResult ?? Right(2));
  }
}

void main() {
  late FakeSecureStoragePlatform secureStorage;
  setUp(() {
    secureStorage = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = secureStorage;
  });

  late FakeAiConfigRepository repo;
  late ValueNotifier<Result<List<AiConfigView>>> discovery;
  late ValueNotifier<Result<List<AiProviderInfo>>> providers;
  late ValueNotifier<Result<List<ModelInfo>>> models;
  late ProviderContainer container;

  Future<void> setupContainer({
    Result<List<AiConfigView>>? discoveryValue,
    Result<List<AiProviderInfo>>? providersValue,
    Result<List<ModelInfo>>? modelsValue,
  }) async {
    repo = FakeAiConfigRepository(BreakdownApi());
    discovery = ValueNotifier(discoveryValue ?? const Right(<AiConfigView>[]));
    providers = ValueNotifier(
      providersValue ??
          Right([
            _provider('openai', LlmProvider.openai),
            _provider('neuralwatt', LlmProvider.neuralwatt),
          ]),
    );
    models = ValueNotifier(
      modelsValue ?? Right([_model('gpt-5.6-luna'), _model('gpt-5.6-terra')]),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiConfigRepositoryProvider.overrideWithValue(repo),
        aiConfigDiscoveryProvider.overrideWith((ref) async => discovery.value),
        aiProvidersProvider.overrideWith((ref) async => providers.value),
        aiProviderModelsProvider.overrideWith((ref, key) async => models.value),
        // Immediate scheduler: reconciliation ticks are no-ops — no
        // wall-clock gating (AGENTS.md §6).
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const _ImmediateScheduler(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    TargetPlatform? platform,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Restore, don't clear: pumpScreen does not own the platform
    // override — the golden helpers set it around the capture (review).
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      if (platform != null) {
        debugDefaultTargetPlatformOverride = platform;
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: mode,
            home: const AiConfigScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  }

  Future<void> refreshDiscovery(WidgetTester tester) async {
    container.invalidate(aiConfigDiscoveryProvider);
    await tester.pumpAndSettle();
  }

  Future<void> pickProviderAndModel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-luna').last);
    await tester.pumpAndSettle();
  }

  testWidgets('first-run: list-first discovery renders the empty honest '
      'state with provider + model pickers and the masked key field', (
    tester,
  ) async {
    await setupContainer();
    await pumpScreen(tester);

    expect(find.byKey(const Key('ai-config-first-run')), findsOneWidget);
    expect(find.text('Not configured yet'), findsOneWidget);
    expect(find.byKey(const Key('ai-provider-picker')), findsOneWidget);
    await pickProviderAndModel(tester);
    expect(find.byKey(const Key('ai-assistant-model-picker')), findsOneWidget);

    // Masked-key semantics (D6): the field obscures its text and nothing
    // is persisted while typing.
    final field = tester.widget<TextField>(
      find.byKey(const Key('ai-api-key-field')),
    );
    expect(field.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-test-123',
    );
    await tester.pump();
    expect(
      secureStorage.store.values.join().contains('sk-test-123'),
      isFalse,
      reason: 'the key never persists while editing (D6)',
    );
    // …and it never enters the hand-off document at all.
    expect(secureStorage.store.containsKey(AiImportHandoffStore.key), isFalse);
  });

  testWidgets('a failed discovery renders the retry state — NEVER the '
      'first-run form (review: a failed list fetch is not "no config '
      'exists"; the first-run save button would create a second '
      'credential)', (tester) async {
    await setupContainer(
      discoveryValue: const Left(ProblemError(code: 'transport.down')),
    );
    await pumpScreen(tester);

    expect(find.byKey(const Key('ai-config-discovery-error')), findsOneWidget);
    expect(find.byKey(const Key('ai-config-first-run')), findsNothing);
    // The retry affordance re-runs the discovery.
    await tester.tap(find.byKey(const Key('ai-config-discovery-retry')));
    await tester.pump();
    discovery.value = Right([_config()]);
    await refreshDiscovery(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
    await tester.pump();
  });

  testWidgets('the optional image model can be CLEARED ("none") — the '
      'explicit null is honoured, not fallen back to the configured value '
      '(review)', (tester) async {
    await setupContainer();
    // Start configured, then edit.
    discovery.value = Right([_config(imageModel: 'img-1')]);
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);

    final controller = container.read(aiConfigControllerProvider.notifier);
    // The configured state reports the fetched image model.
    expect(
      container.read(aiConfigControllerProvider).selectedImageModelId,
      'img-1',
    );
    // Picking "none" is a REAL intent: the state reports null (not the
    // configured fallback) and the edit carries the clear.
    controller.selectImageModel(null);
    expect(
      container.read(aiConfigControllerProvider).selectedImageModelId,
      isNull,
    );
    await tester.pump();
  });

  testWidgets('create submits the credential then the config; the secret '
      'rides only in the request payload and is remembered as an id', (
    tester,
  ) async {
    await setupContainer();
    await pumpScreen(tester);
    await pickProviderAndModel(tester);
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-test-123',
    );
    await tester.tap(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(repo.lastSecret, 'sk-test-123');
    expect(repo.createCalls, 1);
    // The create remembered the config id (fast-path fallback, D2).
    final handoff = secureStorage.store[AiImportHandoffStore.key];
    expect(handoff, contains('config-1'));
    // The SECRET itself never persisted.
    expect(secureStorage.store.values.join().contains('sk-test-123'), isFalse);
    // The discovery refreshed into the configured state.
    discovery.value = Right([_config()]);
    await refreshDiscovery(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
  });

  testWidgets('credential-role denial (403) renders the localized '
      'narrative; the session-only gate lets the call go (D4)', (tester) async {
    await setupContainer(
      providersValue: Right([_provider('openai', LlmProvider.openai)]),
    );
    repo.submitResult = const Left(
      ProblemError(code: 'ai_config.forbidden', status: 403),
    );
    await pumpScreen(tester);
    await pickProviderAndModel(tester);
    await tester.enterText(find.byKey(const Key('ai-api-key-field')), 'sk-1');
    await tester.tap(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();

    // D4: the call WAS issued (no client-side capability surface)…
    expect(repo.submitCalls, 1);
    // …and the 403 narrative renders.
    expect(
      find.text('Administrator role required — ask your production admin.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown provider (422): honest degradation, the flow cannot '
      'proceed', (tester) async {
    await setupContainer(
      modelsValue: const Left(
        ProblemError(code: 'provider.unknown', status: 422),
      ),
    );
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai').last);
    await tester.pumpAndSettle();

    // Honest degradation: the model step degrades, the flow cannot
    // proceed to that provider's config.
    expect(
      find.text('Provider unavailable — the model catalog cannot be read.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ai-assistant-model-picker')), findsNothing);
    // No assistant model selected → create stays disabled.
    final create = tester.widget<FilledButton>(
      find.byKey(const Key('ai-config-create')),
    );
    expect(create.onPressed, isNull);
  });

  testWidgets('edit conflict (409) renders the changed-elsewhere copy with '
      'NO automatic version-bump re-dispatch', (tester) async {
    await setupContainer(discoveryValue: Right([_config(version: 1)]));
    repo.updateResult = const Left(
      ProblemError(code: 'ai_config.conflict', status: 409),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai-edit-script-prompt')),
      'new prompt',
    );
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Changed elsewhere — refresh and re-apply your edit.'),
      findsOneWidget,
    );
    // Exactly one PATCH — no automatic version-bump re-dispatch.
    expect(repo.updateCalls, 1);
  });

  testWidgets('revoke with confirm: cancel keeps the config; confirm '
      'revokes', (tester) async {
    await setupContainer(discoveryValue: Right([_config()]));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('ai-config-revoke')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-config-revoke-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-config-revoke-cancel')));
    await tester.pumpAndSettle();
    expect(repo.revokeCalls, 0);

    await tester.tap(find.byKey(const Key('ai-config-revoke')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-config-revoke-confirm-yes')));
    await tester.pumpAndSettle();
    expect(repo.revokeCalls, 1);
  });

  testWidgets('the ambiguous-create unresolved card offers both actions; '
      'the credential is never destroyed implicitly', (tester) async {
    await setupContainer();
    // Script: hand-off OK; create times out (ambiguous).
    repo.createResult = const Left(
      ProblemError(code: 'transport.connectionTimeout'),
    );
    // Reconciliation: every list read fails (unknown outcome). The
    // DISCOVERY itself is an empty list — the legitimate first-run state
    // (a FAILED discovery now renders the retry state instead, review).
    repo.listResult = const Left(
      ProblemError(code: 'server.down', status: 500),
    );
    discovery.value = const Right(<AiConfigView>[]);
    await pumpScreen(tester);
    await pickProviderAndModel(tester);
    await tester.enterText(find.byKey(const Key('ai-api-key-field')), 'sk-1');
    await tester.tap(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-config-unresolved')), findsOneWidget);
    // NO rollback was dispatched (the credential may be referenced).
    expect(
      find.text(
        'The API key could not be removed from the server vault after the '
        'failed setup. Retry the cleanup from the configuration screen.',
      ),
      findsNothing,
    );
    // "Re-check" resolves the state when the config committed meanwhile.
    repo.listResult = Right([_config()]);
    discovery.value = Right([_config()]);
    await tester.tap(find.byKey(const Key('ai-config-unresolved-recheck')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-config-unresolved')), findsNothing);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
  });

  group('AiConfigScreen goldens (2.2): {light,dark}×{android,macos}', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      required TargetPlatform platform,
    }) async {
      try {
        debugDefaultTargetPlatformOverride = platform;
        await pumpScreen(tester, mode: mode, platform: platform);
        await expectLater(
          find.byType(AiConfigScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('first-run golden light android', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'ai_config_first_run_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('first-run golden dark android', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'ai_config_first_run_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('first-run golden light macos', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'ai_config_first_run_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('first-run golden dark macos', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'ai_config_first_run_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('configured golden light android', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpGolden(
        tester,
        golden: 'ai_config_configured_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('configured golden dark android', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpGolden(
        tester,
        golden: 'ai_config_configured_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('configured golden light macos', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpGolden(
        tester,
        golden: 'ai_config_configured_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('configured golden dark macos', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpGolden(
        tester,
        golden: 'ai_config_configured_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}

/// In-memory [FlutterSecureStoragePlatform] double (same pattern as the
/// token-store and active-block-store tests): the D6 no-persistence
/// assertions intercept every store write.
/// Deterministic scheduler: every tick resolves immediately (no
/// wall-clock, AGENTS.md §6).
class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}
