// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)

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
import 'package:flutter_code_editor/flutter_code_editor.dart';
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

AiImportDefaults _defaults({String script = '', String schedule = ''}) =>
    AiImportDefaults(
      (b) => b
        ..script = script
        ..schedule = schedule,
    );

ModelInfo _model(String id, {bool recommended = false}) => ModelInfo(
  (b) => b
    ..id = id
    ..provider = LlmProvider.openai
    ..recommended = recommended,
);

AiConfigView _config({
  int version = 1,
  String assistantModel = 'gpt-5.6-luna',
  String? imageModel,
  Map<String, String> prompts = const {},
}) => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = assistantModel
    ..provider = LlmProvider.openai
    ..vaultKeyId = 'vk-1'
    ..imageModel = imageModel
    ..prompts.replace(prompts)
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

  /// The last [UpdateAiConfigRequest] passed to [updateConfig] (issue #490:
  /// verify an untouched edit echoes the stored prompts instead of an empty
  /// map).
  UpdateAiConfigRequest? lastUpdateRequest;

  int submitCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int revokeCalls = 0;
  int settingsCalls = 0;

  String? lastSecret;

  /// The provider passed to the most recent [submitCredential] call
  /// (issue #528): the handoff must bind the key to the provider the user
  /// actually selected, not to whichever provider the fake defaults to.
  String? lastProvider;

  @override
  Future<Result<List<AiConfigView>>> listConfigs() async =>
      listResult ?? const Right(<AiConfigView>[]);

  @override
  Future<Result<IdVersionResponse>> submitCredential({
    required String provider,
    required String secret,
  }) async {
    submitCalls++;
    lastProvider = provider;
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
    lastUpdateRequest = request;
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
  late ValueNotifier<Result<AiImportDefaults>> defaults;
  late ProviderContainer container;

  Future<void> setupContainer({
    Result<List<AiConfigView>>? discoveryValue,
    Result<List<AiProviderInfo>>? providersValue,
    Result<List<ModelInfo>>? modelsValue,
    Result<AiImportDefaults>? defaultsValue,
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
    // Defaults default to loaded-but-empty: the first-run form stays
    // prompt-empty unless a test injects real defaults (existing tests keep
    // their exact behavior; no real network call is ever made — the
    // controller watches this provider in build).
    defaults = ValueNotifier(defaultsValue ?? Right(_defaults()));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiConfigRepositoryProvider.overrideWithValue(repo),
        aiConfigDiscoveryProvider.overrideWith((ref) async => discovery.value),
        aiProvidersProvider.overrideWith((ref) async => providers.value),
        aiProviderModelsProvider.overrideWith((ref, key) async => models.value),
        aiImportDefaultsProvider.overrideWith((ref) async => defaults.value),
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

  testWidgets('AI import disabled on this instance (wire code '
      'ai-import.disabled): dedicated state WITHOUT a retry affordance — '
      'retrying cannot fix a server feature flag (issue #422)', (tester) async {
    await setupContainer(
      discoveryValue: const Left(
        ProblemError(code: 'ai-import.disabled', status: 404),
      ),
    );
    await pumpScreen(tester);

    // The dedicated disabled card renders (not the generic retry card).
    expect(find.byKey(const Key('ai-config-disabled')), findsOneWidget);
    expect(find.byKey(const Key('ai-config-discovery-error')), findsNothing);
    expect(
      find.byKey(const Key('ai-config-discovery-retry')),
      findsNothing,
      reason: 'no retry affordance while the feature flag is off',
    );
    expect(find.byKey(const Key('ai-config-first-run')), findsNothing);
    // Code-keyed copy, never the server detail (AGENTS.md §5).
    expect(
      find.textContaining('AI import is not enabled on this instance'),
      findsOneWidget,
    );
  });

  testWidgets('provider discovery refused with the disabled code: the '
      'picker degrades to the disabled copy WITHOUT a retry button '
      '(issue #422)', (tester) async {
    await setupContainer(
      providersValue: const Left(
        ProblemError(code: 'ai-import.disabled', status: 404),
      ),
    );
    await pumpScreen(tester);

    expect(
      find.textContaining('AI import is not enabled on this instance'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-providers-retry')),
      findsNothing,
      reason: 'retrying cannot flip the backend feature flag',
    );
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
      ProblemError(code: 'ai-config.forbidden', status: 403),
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
      ProblemError(code: 'ai-config.version-mismatch', status: 409),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);

    await _enterPrompt(tester, 'ai-edit-script-prompt', 'new prompt');
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

  // --- First-run prefill (issue #471) -------------------------------------

  testWidgets('first-run prefill: provider + recommended model preselected '
      'and prompt fields seeded from the defaults endpoint (issue #471)', (
    tester,
  ) async {
    await setupContainer(
      defaultsValue: Right(_defaults(script: 'S1', schedule: 'S2')),
      modelsValue: Right([
        _model('gpt-5.6-luna', recommended: true),
        _model('gpt-5.6-terra'),
      ]),
    );
    await pumpScreen(tester);

    final state = container.read(aiConfigControllerProvider);
    // Provider: the first curated provider in display order.
    expect(state.selectedProviderKey, 'openai');
    // Assistant model: the recommended model of the preselected provider.
    expect(state.selectedAssistantModelId, 'gpt-5.6-luna');
    // Prompt fields: seeded from GET /v1/ai-import/defaults (editable).
    expect(state.scriptPrompt, 'S1');
    expect(state.schedulePrompt, 'S2');
    // The rendered fields carry the defaults and the provenance hint shows.
    expect(_codeField(tester, 'ai-script-prompt').controller.fullText, 'S1');
    expect(_codeField(tester, 'ai-schedule-prompt').controller.fullText, 'S2');
    expect(find.byKey(const Key('ai-prefill-hint')), findsOneWidget);
  });

  testWidgets('first-run prefill: a model set with NO recommended model '
      'falls back to the first model (backends that predate the flag)', (
    tester,
  ) async {
    await setupContainer(
      defaultsValue: Right(_defaults()),
      modelsValue: Right([_model('gpt-5.6-luna'), _model('gpt-5.6-terra')]),
    );
    await pumpScreen(tester);
    final state = container.read(aiConfigControllerProvider);
    // No model is recommended → the `orElse` fallback (the first model in
    // the set) is what is actually selected.
    expect(state.selectedAssistantModelId, 'gpt-5.6-luna');
    expect(state.selectedProviderKey, 'openai');
    // No defaults text → no provenance hint.
    expect(find.byKey(const Key('ai-prefill-hint')), findsNothing);
    expect(state.scriptPrompt, '');
    expect(state.schedulePrompt, '');
  });

  testWidgets('first-run prefill: a failed defaults fetch degrades to empty '
      'prompt fields with NO blocking state — the user types by hand', (
    tester,
  ) async {
    await setupContainer(
      defaultsValue: const Left(ProblemError(code: 'transport.down')),
    );
    await pumpScreen(tester);

    final state = container.read(aiConfigControllerProvider);
    // Provider + model preselect is independent of the defaults fetch.
    expect(state.selectedProviderKey, 'openai');
    expect(state.selectedAssistantModelId, 'gpt-5.6-luna');
    expect(state.scriptPrompt, '');
    expect(state.schedulePrompt, '');
    expect(find.byKey(const Key('ai-prefill-hint')), findsNothing);
    // The create flow is NOT blocked by the failed defaults fetch.
    expect(find.byKey(const Key('ai-config-create')), findsOneWidget);
  });

  testWidgets('the user\'s own interaction always wins over the prefill '
      '(issue #471): picking a non-first provider and typing over a prompt', (
    tester,
  ) async {
    await setupContainer(
      defaultsValue: Right(_defaults(script: 'S1', schedule: 'S2')),
    );
    await pumpScreen(tester);

    // Provider: pick a non-first provider — the prefill must NOT flip it
    // back to the first one once the user has chosen.
    final controller = container.read(aiConfigControllerProvider.notifier);
    controller.selectProvider('neuralwatt');
    await tester.pumpAndSettle();
    expect(
      container.read(aiConfigControllerProvider).selectedProviderKey,
      'neuralwatt',
    );
    expect(
      container.read(aiConfigControllerProvider).selectedAssistantModelId,
      isNull,
      reason: 'changing providers must not restore the old assistant model',
    );

    // Prompt: typing into the script field is never clobbered by a later
    // defaults delivery, and the OTHER prefilled prompt (schedule) is NOT
    // wiped by editing the script field (CodeRabbit review, PR #489): the
    // touched-guard is per-field.
    await _enterPrompt(tester, 'ai-script-prompt', 'my custom prompt');
    await tester.pump();
    final after1 = container.read(aiConfigControllerProvider);
    expect(after1.scriptPrompt, 'my custom prompt');
    expect(
      after1.schedulePrompt,
      'S2',
      reason:
          'editing the script prompt must not drop the prefilled '
          'schedule default',
    );

    defaults.value = Right(_defaults(script: 'OVERWRITE', schedule: 'S2'));
    container.invalidate(aiImportDefaultsProvider);
    await tester.pumpAndSettle();
    expect(
      container.read(aiConfigControllerProvider).scriptPrompt,
      'my custom prompt',
      reason: 'a typed prompt must never be replaced by the defaults prefill',
    );
    expect(
      container.read(aiConfigControllerProvider).schedulePrompt,
      'S2',
      reason: 'a prefilled prompt the user did not touch stays prefilled',
    );
  });

  testWidgets('configured state with empty stored prompts falls back to '
      'backend defaults; provider/model still come from the config '
      '(issue #520)', (tester) async {
    await setupContainer(
      discoveryValue: Right([_config()]),
      defaultsValue: Right(_defaults(script: 'S1', schedule: 'S2')),
    );
    await pumpScreen(tester);

    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
    final state = container.read(aiConfigControllerProvider);
    expect(state.selectedProviderKey, 'openai');
    expect(state.selectedAssistantModelId, 'gpt-5.6-luna');
    expect(state.scriptPrompt, 'S1');
    expect(state.schedulePrompt, 'S2');
    expect(
      _codeField(tester, 'ai-edit-script-prompt').controller.fullText,
      'S1',
    );
    expect(
      _codeField(tester, 'ai-edit-schedule-prompt').controller.fullText,
      'S2',
    );

    // Recommended save semantics: an untouched configured save persists the
    // visible defaults, repairing a config that was stored with empty prompts.
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();
    expect(repo.lastUpdateRequest!.prompts['script'], 'S1');
    expect(repo.lastUpdateRequest!.prompts['schedule'], 'S2');
  });

  testWidgets('configured model editor keeps the bound provider while PATCHing '
      'assistant model, image model, vault key, and version (issue #509)', (
    tester,
  ) async {
    await setupContainer(discoveryValue: Right([_config(version: 7)]));
    await pumpScreen(tester);

    final providerPicker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('ai-provider-picker')),
    );
    expect(providerPicker.onChanged, isNotNull);

    await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-terra').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-image-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-luna').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    final sent = repo.lastUpdateRequest!;
    expect(sent.provider, LlmProvider.openai);
    expect(sent.assistantModel, 'gpt-5.6-terra');
    expect(sent.imageModel, 'gpt-5.6-luna');
    expect(sent.vaultKeyId, 'vk-1');
    expect(sent.version, 7);
  });

  testWidgets('provider replacement reuses a retained credential without '
      'asking for its secret again (issue #528)', (tester) async {
    await setupContainer(discoveryValue: Right([_config()]));
    await AiImportHandoffStore.secure().rememberCredential(
      'dev-user',
      'neuralwatt',
      const ProviderCredentialReference(
        settingsId: 'settings-neuralwatt',
        settingsVersion: 1,
        vaultKeyId: 'vk-neuralwatt',
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('neuralwatt').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-terra').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ai-config-replacement-api-key-field')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 0);
    expect(repo.lastUpdateRequest!.provider, LlmProvider.neuralwatt);
    expect(repo.lastUpdateRequest!.vaultKeyId, 'vk-neuralwatt');
  });

  testWidgets('provider replacement submits a new credential and retains it '
      'for later provider switches (issue #528)', (tester) async {
    await setupContainer(discoveryValue: Right([_config()]));
    // A DISTINCT vault key for the replacement provider: the assertion can
    // then fail if the implementation reused the original OpenAI key.
    repo.settingsResult = Right(
      SettingsView(
        (b) => b
          ..id = 'settings-1'
          ..provider = 'neuralwatt'
          ..vaultKeyId = 'vk-neuralwatt'
          ..vaultVersion = 1
          ..version = 1
          ..bindingState = CredentialBindingState.active,
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('neuralwatt').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-config-replacement-api-key-field')),
      'new-provider-secret',
    );
    await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-terra').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(repo.lastProvider, 'neuralwatt');
    expect(repo.lastSecret, 'new-provider-secret');
    expect(repo.lastUpdateRequest!.provider, LlmProvider.neuralwatt);
    expect(repo.lastUpdateRequest!.vaultKeyId, 'vk-neuralwatt');
    expect(
      secureStorage.store[AiImportHandoffStore.key],
      contains('neuralwatt'),
    );

    // The just-retained provider can be selected again without a key prompt.
    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('ai-config-replacement-api-key-field')),
      findsNothing,
    );
  });

  testWidgets('provider replacement retains the new credential when the '
      'config PATCH fails (issue #528)', (tester) async {
    await setupContainer(discoveryValue: Right([_config()]));
    repo.updateResult = const Left(
      ProblemError(code: 'ai-config.version-mismatch', status: 409),
    );
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('ai-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('neuralwatt').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-config-replacement-api-key-field')),
      'new-provider-secret',
    );
    await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5.6-terra').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(repo.updateCalls, 1);
    expect(
      find.text('Changed elsewhere — refresh and re-apply your edit.'),
      findsOneWidget,
    );
    expect(
      secureStorage.store[AiImportHandoffStore.key],
      contains('neuralwatt'),
    );
  });

  testWidgets('configured prompt-only edit survives provider-catalog failure '
      'without requiring provider discovery (issue #509)', (tester) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          prompts: {'script': 'Stored Script', 'schedule': 'Stored Schedule'},
        ),
      ]),
      providersValue: const Left(ProblemError(code: 'transport.down')),
    );
    await pumpScreen(tester);

    await _enterPrompt(
      tester,
      'ai-edit-script-prompt',
      'Edited without catalog',
    );
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(repo.lastUpdateRequest!.provider, LlmProvider.openai);
    expect(repo.lastUpdateRequest!.prompts['script'], 'Edited without catalog');
  });

  testWidgets('XML editor highlights tags distinctly and saves the exact '
      'source string without style markup (issue #520)', (tester) async {
    const defaultXml = '<role>Extract scenes</role>';
    const editedXml =
        '<role>Extract scenes</role>\n'
        '<context>Only scenes in this act</context>';
    await setupContainer(
      discoveryValue: Right([_config()]),
      defaultsValue: Right(
        _defaults(script: defaultXml, schedule: '<role>Map days</role>'),
      ),
    );
    await pumpScreen(tester);

    final field = _codeField(tester, 'ai-edit-script-prompt');
    final scheme = Theme.of(
      tester.element(find.byKey(const Key('ai-config-configured'))),
    ).colorScheme;
    final spans = _flattenSpans(field.controller.lastTextSpan!).toList();
    final primaryRuns = spans
        .where((span) => span.style?.color == scheme.primary)
        .map((span) => span.toPlainText())
        .join();
    expect(primaryRuns, contains('<role>'));
    expect(
      spans.map((span) => span.toPlainText()).join(),
      contains('Extract scenes'),
    );

    await _enterPrompt(tester, 'ai-edit-script-prompt', editedXml);
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(container.read(aiConfigControllerProvider).scriptPrompt, editedXml);
    expect(repo.lastUpdateRequest!.prompts['script'], editedXml);
  });

  // --- Edit path: stored prompt texts (issue #490) -------------------------

  testWidgets('edit path: the configured form RENDERS the stored prompt '
      'texts — the fields are never empty at load (issue #490)', (
    tester,
  ) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          prompts: {'script': 'Stored Script', 'schedule': 'Stored Schedule'},
        ),
      ]),
    );
    await pumpScreen(tester);

    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
    final state = container.read(aiConfigControllerProvider);
    // State seeds the stored texts…
    expect(state.scriptPrompt, 'Stored Script');
    expect(state.schedulePrompt, 'Stored Schedule');
    // …and the rendered text fields carry them (the same `_sync`
    // mechanism the prefill already uses, issue #471).
    expect(
      _codeField(tester, 'ai-edit-script-prompt').controller.fullText,
      'Stored Script',
    );
    expect(
      _codeField(tester, 'ai-edit-schedule-prompt').controller.fullText,
      'Stored Schedule',
    );
    // The edit form never shows the first-run prefill provenance hint.
    expect(find.byKey(const Key('ai-prefill-hint')), findsNothing);
  });

  testWidgets('edit path: saving an UNTOUCHED edit preserves the stored '
      'prompts — the update does NOT send an empty map (issue #490)', (
    tester,
  ) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          version: 3,
          prompts: {'script': 'Stored Script', 'schedule': 'Stored Schedule'},
        ),
      ]),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    final sent = repo.lastUpdateRequest!;
    // The prompt map echoes the STORED texts — nothing is cleared by an
    // untouched save.
    expect(sent.prompts['script'], 'Stored Script');
    expect(sent.prompts['schedule'], 'Stored Schedule');
    // The optimistic lock still rides the fetched version.
    expect(sent.version, 3);
  });

  testWidgets('edit path: clearing a stored prompt field is a REAL "remove '
      'prompt" intent — the key is omitted from the update, the other '
      'stored prompt is preserved (issue #490)', (tester) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          prompts: {'script': 'Stored Script', 'schedule': 'Stored Schedule'},
        ),
      ]),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);

    // Clear ONLY the script field; the schedule field stays untouched.
    await _enterPrompt(tester, 'ai-edit-script-prompt', '');
    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    final sent = repo.lastUpdateRequest!;
    // Clearing is a deliberate removal: the cleared key is OMITTED (the
    // backend replaces the map wholesale; omitting = remove).
    expect(sent.prompts.containsKey('script'), isFalse);
    // The untouched stored schedule prompt survives.
    expect(sent.prompts['schedule'], 'Stored Schedule');
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

CodeField _codeField(WidgetTester tester, String key) =>
    tester.widget<CodeField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(CodeField),
      ),
    );

Future<void> _enterPrompt(WidgetTester tester, String key, String text) =>
    tester.enterText(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
      text,
    );

Iterable<InlineSpan> _flattenSpans(InlineSpan span) sync* {
  yield span;
  if (span is TextSpan) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _flattenSpans(child);
    }
  }
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
