// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
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

import 'dart:async';

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
import 'package:frontend_flutter/auth/capabilities.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_config_repository.dart';
import 'package:frontend_flutter/data/ai_import_handoff_store.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_controller.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_screen.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/ai_config_state.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

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
  defaultProjectId: 'series-1',
);

/// A provider row from `GET /ai-import/providers`. [decisionCapable] is the
/// backend-decided capability flag (issue #736) the Decision provider picker
/// filters on — the client keeps NO provider-id allowlist of its own. `null`
/// models a backend that predates the field (absent on the wire).
AiProviderInfo _provider(
  String key,
  LlmProvider provider, {
  bool? decisionCapable = false,
}) => AiProviderInfo(
  (b) => b
    ..provider = provider
    ..decisionCapable = decisionCapable
    ..key = key,
);

AiImportDefaults _defaults({
  String script = '',
  String schedule = '',
  String scheduleFlat = '',
}) => AiImportDefaults(
  (b) => b
    ..script = script
    ..schedule = schedule
    ..scheduleFlat = scheduleFlat,
);

ModelInfo _model(
  String id, {
  bool recommended = false,
  ModelPricing? pricing,

  /// The `reasoning_effort` levels this model DECLARES (2026-11-20
  /// investigation). Empty models the pre-field backend AND a provider whose
  /// catalogue carries no such capability — both mean "no choosable level".
  List<ReasoningEffort> efforts = const [],
}) => ModelInfo(
  (b) => b
    ..id = id
    ..provider = LlmProvider.openai
    ..recommended = recommended
    ..pricing = pricing?.toBuilder()
    ..supportedReasoningEfforts.replace(efforts),
);

/// A pricing snapshot fixture (issue #675): 1.45 in / 4 out per 1M tokens
/// (USD), with the Neuralwatt-style energy rate when requested. The image
/// fields (#673 slots) model the two seeded image-rate shapes: a flat
/// per-image rate (OpenAI `gpt-image-*`) or an image-output token rate
/// (Gemini `*-image`).
ModelPricing _pricing({
  int? energyNanoPerKwh,
  int? imageNanoPerUnit,
  int? imageOutputNanoPerMillion,
  Currency currency = Currency.USD,
}) => ModelPricing(
  (b) => b
    ..currency = currency
    ..inputNanoPerMillion = 1450000000
    ..outputNanoPerMillion = 4000000000
    ..priceAsOf = DateTime.utc(2026, 1, 1)
    ..pricingSource = PricingSource.curatedSeed
    ..energyNanoPerKwh = energyNanoPerKwh
    ..imageNanoPerUnit = imageNanoPerUnit
    ..imageOutputNanoPerMillion = imageOutputNanoPerMillion,
);

/// An active config view. [storedPromptKinds] is left ABSENT when null, which
/// models a server that predates the field (the client must then claim nothing
/// about overrides rather than asserting "none exist").
AiConfigView _config({
  int version = 1,
  String assistantModel = 'gpt-5.6-luna',
  String? imageModel,
  Map<String, String> prompts = const {},
  List<DocumentKind>? storedPromptKinds,
  LlmProvider provider = LlmProvider.openai,
  LlmProvider? decisionProvider,
  String? decisionModel,
  String? decisionVaultKeyId,

  /// The stored `reasoning_effort`; `auto` models the pre-field backend.
  ReasoningEffortChoice reasoningEffort = ReasoningEffortChoice.auto,

  /// The stored zero-data-retention attestation (issue #968).
  bool zdrAttested = false,
}) {
  final base = AiConfigView(
    (b) => b
      ..id = 'config-1'
      ..userId = 'dev-user'
      ..assistantModel = assistantModel
      ..provider = provider
      ..vaultKeyId = 'vk-1'
      ..imageModel = imageModel
      ..prompts.replace(prompts)
      ..promptKinds.replace(
        BuiltList(const [DocumentKind.script, DocumentKind.schedule]),
      )
      ..revoked = false
      ..reasoningEffort = reasoningEffort
      ..zdrAttested = zdrAttested
      ..version = version,
  );
  return storedPromptKinds == null
      ? base.rebuild(
          (b) => b
            ..decisionProvider = decisionProvider
            ..decisionModel = decisionModel
            ..decisionVaultKeyId = decisionVaultKeyId,
        )
      : base.rebuild(
          (b) => b
            ..decisionProvider = decisionProvider
            ..decisionModel = decisionModel
            ..decisionVaultKeyId = decisionVaultKeyId
            ..storedPromptKinds.replace(storedPromptKinds),
        );
}

/// The locale this harness renders in (no explicit `locale:` on the
/// `MaterialApp`, so the test binding's `en_US` default applies — the same
/// reason the neighbouring assertions use English copy).
AppLocalizations l10nEn() => lookupAppLocalizations(const Locale('en'));

/// A provider-health answer from `GET /ai-import/providers/{provider}/health`
/// (issue #942 W4). Defaults model a usable, configured account whose provider
/// reports no budget at all.
AiProviderHealthView _healthView({
  bool credentialConfigured = true,
  AccountProbeStatus status = AccountProbeStatus.usable,
  AiProviderBudgetView? budget,
  List<AiProviderBreakerView> breakers = const <AiProviderBreakerView>[],
}) => AiProviderHealthView(
  (b) => b
    ..provider = LlmProvider.openai
    ..credentialConfigured = credentialConfigured
    ..probeStatus = status
    ..budget = budget?.toBuilder()
    ..breakers.replace(breakers),
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

  /// The last [CreateAiConfigRequest] passed to [createConfig] (issue #675:
  /// verify the `cost_display_preference` the create carried).
  CreateAiConfigRequest? lastCreateRequest;

  /// `GET /v1/ai-import/providers/{provider}/health` (issue #942 W4). `null`
  /// answers a usable account with no budget read — the honest "the provider
  /// reports no figure" default, so the pre-#942 tests are unaffected.
  Result<AiProviderHealthView>? healthResult;

  /// The provider keys the health route was called with, in call order. Empty
  /// is the assertion that matters for the #816 short-circuit: a resolved
  /// capability denial must reach the device's own repository NEVER.
  final List<String> healthCalls = <String>[];

  @override
  Future<Result<AiProviderHealthView>> fetchProviderHealth({
    required String providerKey,
    String? model,
  }) async {
    healthCalls.add(providerKey);
    return healthResult ??
        Right(
          AiProviderHealthView(
            (b) => b
              ..provider = LlmProvider.openai
              ..credentialConfigured = true
              ..probeStatus = AccountProbeStatus.usable
              ..breakers = ListBuilder<AiProviderBreakerView>(),
          ),
        );
  }

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

  /// `GET /v1/ai-import/config/{id}` — the round-trip read-back the controller
  /// runs before reporting a save as successful (issue #769).
  ///
  /// `null` (the default) DERIVES the stored view from the last submitted
  /// request — the honest "the server stored what was sent" case, so the
  /// pre-#769 tests keep their meaning without a real network call. A test
  /// modelling the reported defect sets an explicit value that omits the
  /// triple.
  Result<AiConfigView>? getConfigResult;
  int getConfigCalls = 0;

  /// Scripted read-back sequence (issue #769 retry): every [getConfig] call
  /// consumes one entry, so a test can model projector lag — a mismatch that
  /// the next attempt confirms — without a real network call. An exhausted
  /// script falls back to [getConfigResult] / the echoed submitted view.
  List<Result<AiConfigView>>? getConfigScript;

  @override
  Future<Result<AiConfigView>> getConfig(String id) async {
    getConfigCalls++;
    final script = getConfigScript;
    if (script != null && script.isNotEmpty) return script.removeAt(0);
    final override = getConfigResult;
    if (override != null) return override;
    return Right(storedViewFor(id));
  }

  /// The view the fake reports as stored for [id]: the last PATCH/CREATE body
  /// echoed back, so the read-back confirms exactly what the controller sent.
  AiConfigView storedViewFor(String id) {
    final update = lastUpdateRequest;
    final create = lastCreateRequest;
    return AiConfigView(
      (b) => b
        ..id = id
        ..userId = 'dev-user'
        ..provider = update?.provider ?? create?.provider ?? LlmProvider.openai
        ..assistantModel =
            update?.assistantModel ?? create?.assistantModel ?? 'gpt-5.6-luna'
        ..vaultKeyId = update?.vaultKeyId ?? create?.vaultKeyId ?? 'vk-1'
        ..revoked = false
        ..version = 2
        ..decisionProvider =
            update?.decisionProvider ?? create?.decisionProvider
        ..decisionModel = update?.decisionModel ?? create?.decisionModel
        ..decisionVaultKeyId =
            update?.decisionVaultKeyId ?? create?.decisionVaultKeyId,
    );
  }

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
    lastCreateRequest = request;
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
  late ValueNotifier<Result<List<ModelInfo>>> decisionModels;
  late ValueNotifier<Result<List<ModelInfo>>> imageModels;
  late ValueNotifier<Result<AiImportDefaults>> defaults;
  late ProviderContainer container;

  Future<void> setupContainer({
    Result<List<AiConfigView>>? discoveryValue,
    Result<List<AiProviderInfo>>? providersValue,
    Result<List<ModelInfo>>? modelsValue,
    Result<List<ModelInfo>>? decisionModelsValue,
    Result<List<ModelInfo>>? imageModelsValue,
    Result<AiImportDefaults>? defaultsValue,

    /// The `GET /v1/me/capabilities` seam (issue #816). Defaults to a granted
    /// credential role so the pre-#942 cases keep their behaviour.
    MyCapabilitiesFetch? capabilitiesFetch,

    /// Replaces the provider-health PROVIDER itself (issue #942 W4). Only for
    /// rendering states the repository seam cannot produce — the #816 gate is
    /// covered by [aiProviderHealthProvider]'s own test, which must exercise the
    /// real provider.
    Result<AiProviderHealthView>? healthOverride,

    /// When true the extraction model catalogue NEVER resolves — the LOADING
    /// state in which the screen knows nothing about the selected model (review
    /// finding 5: a pending catalogue must not read as "this model declares no
    /// reasoning effort").
    bool modelsPending = false,
  }) async {
    repo = FakeAiConfigRepository(BreakdownApi());
    discovery = ValueNotifier(discoveryValue ?? const Right(<AiConfigView>[]));
    providers = ValueNotifier(
      providersValue ??
          Right([
            _provider('openai', LlmProvider.openai),
            // Decision-capable per the backend predicate (issue #736): the
            // decision provider picker renders THIS route flag.
            _provider(
              'neuralwatt',
              LlmProvider.neuralwatt,
              decisionCapable: true,
            ),
          ]),
    );
    models = ValueNotifier(
      modelsValue ?? Right([_model('gpt-5.6-luna'), _model('gpt-5.6-terra')]),
    );
    // The DECISION catalog (issue #731): a distinct route and catalog from
    // the assistant/extraction list — neuralwatt's curated decision models
    // (`clef-flash` recommended, `clef`), never the extraction list.
    decisionModels = ValueNotifier(
      decisionModelsValue ??
          Right([_model('clef-flash', recommended: true), _model('clef')]),
    );
    // The IMAGE catalog (issue #732): a distinct route and catalog from
    // the assistant/extraction list — OpenAI's curated image models,
    // never the extraction list. Key-aware (mirror of the decision
    // fixture): a text-only provider key serves an EMPTY catalog (the
    // backend's honest degradation), so the picker collapses to
    // "— none —" instead of listing LLMs.
    imageModels = ValueNotifier(
      imageModelsValue ?? Right([_model('gpt-image-2'), _model('gpt-image-1')]),
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
        aiProviderModelsProvider.overrideWith(
          (ref, key) async => modelsPending
              // Never completes: the LOADING branch (a `Future` that stays
              // pending, no timer, so `pumpAndSettle` is unaffected).
              ? Completer<Result<List<ModelInfo>>>().future
              : models.value,
        ),
        // Key-aware (CodeRabbit #733): a controller that passed the EXTRACTION
        // provider key to the decision route would surface the extraction
        // catalog here — the clef assertions in the decision-picker tests
        // would fail. The decision catalog is only served for the decision-
        // capable key; every other key falls back to the extraction list.
        aiDecisionProviderModelsProvider.overrideWith(
          (ref, key) async =>
              key == 'neuralwatt' ? decisionModels.value : models.value,
        ),
        // Key-aware (issue #732): only the image-capable key serves the
        // image catalog; every text-only key serves the backend's empty
        // 200 (picker collapses to "— none —", never the extraction list).
        aiImageProviderModelsProvider.overrideWith(
          (ref, key) async =>
              key == 'openai' ? imageModels.value : const Right(<ModelInfo>[]),
        ),
        aiImportDefaultsProvider.overrideWith((ref) async => defaults.value),
        // Provider health + budget (issue #942 W4) is deliberately NOT
        // overridden: the REAL `aiProviderHealthProvider` must run so the #816
        // capability short-circuit is exercised (an override would replace the
        // gate under test). Its only effect is one `fetchProviderHealth` call on
        // the repository fake, which answers locally — no socket, no wall clock.
        if (healthOverride != null)
          aiProviderHealthProvider.overrideWith(
            (ref, key) async => healthOverride,
          ),
        myCapabilitiesFetchProvider.overrideWithValue(
          capabilitiesFetch ??
              () async => const Right(
                MyCapabilities(canManageAiConfig: true, canReadOps: false),
              ),
        ),
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
    double height = 2400,
    double width = 800,
    double textScale = 1.0,

    /// Pins the rendered locale. Omitted, `l10nOf` falls back to
    /// `AppLocalizationsEn` (the suite's default) and no delegate is installed.
    /// Pass `Locale('de')` to render the TEMPLATE locale — the delivery
    /// language, whose labels are the longest ones the layout has to survive.
    Locale? locale,

    /// `false` for a screen with a FOREVER-running animation (a pending provider
    /// keeps a spinner alive, so `pumpAndSettle` would never return): pumps a
    /// fixed number of frames instead.
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
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
            locale: locale,
            localizationsDelegates: locale == null
                ? null
                : AppLocalizations.localizationsDelegates,
            supportedLocales: locale == null
                ? const [Locale('en')]
                : AppLocalizations.supportedLocales,
            // Deterministic host tests (AGENTS.md §6): the Karl Kleiderbügel
            // figure is time-driven, so freeze animations — the static
            // pose is exactly the remove-animations rendering (spec
            // `flutter-easter-eggs`).
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: const AiConfigScreen(),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // A pending catalogue animates its spinner forever, so settling would
        // time out. Three frames are enough for the synchronous providers and
        // the first layout.
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  }

  /// Pushes the screen as a SECOND route so a system back actually pops it
  /// (the `home:` route of [pumpScreen] cannot be popped — the Navigator
  /// refuses to pop its last route, which would make a guard test pass for the
  /// wrong reason).
  Future<void> pumpPushedScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open-ai-config'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiConfigScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-ai-config')));
    await tester.pumpAndSettle();
  }

  /// The scoped credential-role denial scenario shared by the
  /// `ai-config.forbidden` / `settings.forbidden` tests (CodeRabbit
  /// review, issues #470/#643): dedicated denial card, no retry, the
  /// "administrator role required" narrative.
  Future<void> pumpScopedDenial(WidgetTester tester, String code) async {
    await setupContainer(
      discoveryValue: Left(ProblemError(code: code, status: 403)),
    );
    await pumpScreen(tester);

    // The dedicated denial card renders (not the generic retry card).
    expect(
      find.byKey(const Key('ai-config-discovery-forbidden')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ai-config-discovery-error')), findsNothing);
    expect(
      find.byKey(const Key('ai-config-discovery-retry')),
      findsNothing,
      reason: 'retrying cannot flip a credential role',
    );
    expect(find.byKey(const Key('ai-config-first-run')), findsNothing);
    // The [aiConfigErrorCopy] narrative — the same copy the screen's
    // command banner uses for these codes (never the raw code, never
    // the server detail).
    expect(find.textContaining('Administrator role required'), findsOneWidget);
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

  /// Picks a `reasoning_effort` level. The picker is a dropdown: the closed
  /// field only PAINTS the selected entry, so a level must be opened and then
  /// tapped in the menu. `.last` is the menu copy — the closed field keeps every
  /// entry in its sizing `IndexedStack`.
  Future<void> pickReasoningEffort(WidgetTester tester, String level) async {
    // Resolved through the localization, like the provider/model pickers
    // above: a by-key tap on a menu entry does not hit-test (the menu paints
    // inside an overlay list), a `.last` text tap does.
    final l10n = AppLocalizationsEn();
    final label = switch (level) {
      'auto' => l10n.aiConfigReasoningEffortAuto,
      'minimal' => l10n.aiConfigReasoningEffortMinimal,
      'low' => l10n.aiConfigReasoningEffortLow,
      'medium' => l10n.aiConfigReasoningEffortMedium,
      _ => l10n.aiConfigReasoningEffortHigh,
    };
    await tester.ensureVisible(
      find.byKey(const Key('ai-reasoning-effort-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-reasoning-effort-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Picks the curated Decision pair (neuralwatt / clef-flash) in the Decision
  /// Model pickers — the same-provider case, so the same-key reuse path
  /// applies and no separate Decision key field is rendered (issue #723).
  Future<void> pickDecisionProviderAndModel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('neuralwatt').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('clef-flash').last);
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

  testWidgets('discovery that produced NO answer (transport.connectionError) '
      'renders the dedicated unreachable state with a Retry — not the '
      'generic discovery error, never the first-run form (issue #809)', (
    tester,
  ) async {
    await setupContainer(
      discoveryValue: const Left(
        ProblemError(code: 'transport.connectionError'),
      ),
    );
    await pumpScreen(tester);

    // A failed read is not "no configuration exists": the first-run form
    // (whose save would create a SECOND credential) never renders here.
    expect(
      find.byKey(const Key('ai-config-backend-unreachable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ai-config-first-run')), findsNothing);
    expect(find.byKey(const Key('ai-config-discovery-error')), findsNothing);
    // Catalog copy only (AGENTS.md §5) — the same wording the Settings
    // entry's unreachable subtitle uses, so entry and screen agree.
    expect(find.text('Backend not reachable yet'), findsOneWidget);
    expect(
      find.textContaining('This does not mean that no configuration exists'),
      findsOneWidget,
    );

    // The Retry re-runs discovery; once the backend answers, the resolved
    // state renders.
    await tester.tap(
      find.byKey(const Key('ai-config-backend-unreachable-retry')),
    );
    await tester.pump();
    discovery.value = Right([_config()]);
    await refreshDiscovery(tester);

    expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-config-backend-unreachable')),
      findsNothing,
    );
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

  testWidgets('scoped credential-role denial on discovery (wire code '
      'ai-config.forbidden): the localized administrator-role narrative '
      'WITHOUT a retry affordance — a 403 is a denial, not a retryable '
      'load error (issues #470/#643, CodeRabbit review)', (tester) async {
    await pumpScopedDenial(tester, 'ai-config.forbidden');
  });

  testWidgets('scoped credential-role denial on discovery (wire code '
      'settings.forbidden): same localized denial, no retry (issue #470)', (
    tester,
  ) async {
    await pumpScopedDenial(tester, 'settings.forbidden');
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
    await pumpScreen(tester, height: 2400);
    await pickProviderAndModel(tester);
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-test-123',
    );
    await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();
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
    await pumpScreen(tester, height: 2400);
    await pickProviderAndModel(tester);
    await tester.enterText(find.byKey(const Key('ai-api-key-field')), 'sk-1');
    await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();
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
    await pumpScreen(tester, height: 2400);
    await pickProviderAndModel(tester);
    await tester.enterText(find.byKey(const Key('ai-api-key-field')), 'sk-1');
    await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
    await tester.pumpAndSettle();
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
    // The image picker shows the IMAGE catalog (issue #732), not the
    // extraction list.
    await tester.tap(find.text('gpt-image-2').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-config-edit-save')));
    await tester.pumpAndSettle();

    final sent = repo.lastUpdateRequest!;
    expect(sent.provider, LlmProvider.openai);
    expect(sent.assistantModel, 'gpt-5.6-terra');
    expect(sent.imageModel, 'gpt-image-2');
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

  // Task 6.3 (`ai-import` — the configuration surface must say when a stored
  // prompt overrides the deployment default, and offer a reset).
  testWidgets('a stored override is NAMED per kind and the reset writes the '
      'deployment default into the editor', (tester) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          prompts: const {'script': 'STORED'},
          storedPromptKinds: const [DocumentKind.script],
        ),
      ]),
      defaultsValue: Right(
        _defaults(
          script: 'deployment script default',
          schedule: 'sched default',
        ),
      ),
    );
    await pumpScreen(tester);

    // Script: an override is in effect -> say so, and offer the way out.
    expect(find.textContaining('A stored prompt is in effect'), findsOneWidget);
    expect(find.byKey(const Key('ai-prompt-reset-script')), findsOneWidget);
    // Schedule: no override -> the deployment default governs every run.
    expect(
      find.textContaining('No stored prompt — the deployment default is in'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ai-prompt-reset-schedule')), findsNothing);

    await tester.tap(find.byKey(const Key('ai-prompt-reset-script')));
    await tester.pumpAndSettle();
    // The editor now holds the deployment text; saving is what persists it
    // (a reset never dispatches a command behind the user's back).
    expect(
      _codeField(tester, 'ai-edit-script-prompt').controller.fullText,
      'deployment script default',
    );
    expect(
      container.read(aiConfigControllerProvider).scriptPrompt,
      'deployment script default',
    );
    expect(repo.updateCalls, 0, reason: 'reset is a draft edit, not a command');
  });

  testWidgets('reset is DISABLED when the deployment defaults could not be '
      'fetched — there is nothing honest to reset to', (tester) async {
    await setupContainer(
      discoveryValue: Right([
        _config(
          prompts: const {'script': 'stored'},
          storedPromptKinds: const [DocumentKind.script],
        ),
      ]),
      defaultsValue: const Left(ProblemError(code: 'ai.defaults-missing')),
    );
    await pumpScreen(tester);

    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ai-prompt-reset-script')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a server that does not report stored kinds claims NOTHING about '
      'overrides — absence is not "no override" (honest degradation)', (
    tester,
  ) async {
    await setupContainer(
      discoveryValue: Right([
        _config(prompts: const {'script': 'stored'}),
      ]),
    );
    await pumpScreen(tester);

    expect(find.textContaining('A stored prompt is in effect'), findsNothing);
    expect(
      find.textContaining('No stored prompt — the deployment default'),
      findsNothing,
    );
    expect(find.byKey(const Key('ai-prompt-reset-script')), findsNothing);
  });

  testWidgets('the AI-literacy helper card precedes the first-run and the '
      'configured forms and stays persistent (issue #538)', (tester) async {
    await setupContainer();
    await pumpScreen(tester);
    // First-run state: helper ABOVE the form.
    expect(find.byKey(const Key('ai-config-literacy')), findsOneWidget);
    final literacyY = tester
        .getTopLeft(find.byKey(const Key('ai-config-literacy')))
        .dy;
    final formY = tester
        .getTopLeft(find.byKey(const Key('ai-config-first-run')))
        .dy;
    expect(
      literacyY < formY,
      isTrue,
      reason: 'the Art. 4 helper is scroll-ordered above the forms',
    );

    // The CONFIGURED state too: a configured discovery result must keep the
    // helper card (and keep it above the configured form) — a first-run-only
    // assertion cannot detect its removal there.
    discovery.value = Right([_config()]);
    await refreshDiscovery(tester);
    expect(find.byKey(const Key('ai-config-literacy')), findsOneWidget);
    final configuredLiteracyY = tester
        .getTopLeft(find.byKey(const Key('ai-config-literacy')))
        .dy;
    final configuredFormY = tester
        .getTopLeft(find.byKey(const Key('ai-config-configured')))
        .dy;
    expect(
      configuredLiteracyY < configuredFormY,
      isTrue,
      reason: 'the helper is also scroll-ordered above the configured form',
    );
  });

  group(
    'model pricing signals in the pickers (issue #675, flutter-ai-config)',
    () {
      testWidgets('a priced model renders the formatted token + energy rate — '
          'never a hardcoded price', (tester) async {
        await setupContainer(
          modelsValue: Right([
            _model(
              'm-priced',
              pricing: _pricing(energyNanoPerKwh: 10000000000),
            ),
            _model('m-unpriced'),
          ]),
        );
        await pumpScreen(tester);
        await tester.tap(find.byKey(const Key('ai-provider-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('openai').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
        await tester.pumpAndSettle();

        // Formatted from ModelInfo.pricing — input $1.45 / output $4 per 1M
        // tokens, plus the energy rate $10 / kWh.
        expect(
          find.text(r'$1.45 → $4 / 1M tokens · $10 / kWh'),
          findsOneWidget,
        );
        // The unpriced model renders the localized Unknown copy.
        expect(find.text('Unknown'), findsOneWidget);
        // NEVER a fabricated zero anywhere in the menu.
        expect(find.textContaining(r'$0.00'), findsNothing);
        expect(find.text('0'), findsNothing);
      });

      testWidgets('an unpriced (Ollama-style) model renders Unknown and never '
          'a zero — the pricing==null honesty rule', (tester) async {
        await setupContainer(
          providersValue: Right([_provider('ollama', LlmProvider.ollama)]),
          modelsValue: Right([_model('llama-local'), _model('qwen-local')]),
        );
        await pumpScreen(tester);
        await tester.tap(find.byKey(const Key('ai-provider-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ollama').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
        await tester.pumpAndSettle();

        expect(find.text('Unknown'), findsNWidgets(2));
        expect(find.textContaining(r'$0'), findsNothing);
        expect(find.text('0'), findsNothing);
      });

      testWidgets('an image model renders its IMAGE-specific rate — flat per '
          'image or per 1M image-output tokens, never a zero token caption '
          '(issue #732, CodeRabbit review)', (tester) async {
        await setupContainer(
          imageModelsValue: Right([
            // OpenAI-style: flat per-image rate (backend seed:
            // image_nano_per_unit = 40000000, token rates 0).
            _model(
              'gpt-image-2',
              pricing: _pricing(imageNanoPerUnit: 40000000),
            ),
            // Gemini-style: image-output token rate (backend seed:
            // image_output_nano_per_million = 120000000).
            _model(
              'gemini-3.1-flash-image',
              pricing: _pricing(imageOutputNanoPerMillion: 120000000),
            ),
          ]),
        );
        await pumpScreen(tester, height: 2400);
        await tester.tap(find.byKey(const Key('ai-provider-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('openai').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-image-model-picker')));
        await tester.pumpAndSettle();

        // The applicable image rate is formatted, never the token caption
        // (whose seeded rates are 0 → a misleading "$0.00 → $0.00").
        expect(find.text(r'$0.04 / image'), findsOneWidget);
        expect(find.text(r'$0.12 / 1M image tokens'), findsOneWidget);
        expect(find.textContaining(r'$0.00 → $0.00'), findsNothing);
      });
    },
  );

  group('cost display preference selector (issue #675, flutter-ai-config)', () {
    testWidgets('the selector defaults to token and the create carries the '
        'switched energy preference', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Default is token (spec: defaulting to `token`).
      final selector = tester.widget<SegmentedButton<CostDisplayPreference>>(
        find.byKey(const Key('ai-cost-display-picker')),
      );
      expect(selector.selected, {CostDisplayPreference.token});

      await pickProviderAndModel(tester);
      // Switch to energy.
      await tester.ensureVisible(
        find.byKey(const Key('ai-cost-display-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-cost-display-energy')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'sk-test-123',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(
        repo.lastCreateRequest!.costDisplayPreference,
        CostDisplayPreference.energy,
      );
    });

    testWidgets('the configured form echoes the stored preference and the '
        'PATCH carries it', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config().rebuild(
            (b) => b..costDisplayPreference = CostDisplayPreference.energy,
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      // The selector echoes the configured value.
      final selector = tester.widget<SegmentedButton<CostDisplayPreference>>(
        find.byKey(const Key('ai-cost-display-picker')),
      );
      expect(selector.selected, {CostDisplayPreference.energy});

      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();
      expect(
        repo.lastUpdateRequest!.costDisplayPreference,
        CostDisplayPreference.energy,
      );
    });

    // --- Reasoning effort (2026-11-20 output-budget investigation) ---

    testWidgets('the picker offers exactly the levels the selected model '
        'declares, plus auto — never a level it would refuse with a 422', (
      tester,
    ) async {
      await setupContainer(
        modelsValue: Right([
          // GLM-style catalogue: `low|high`, NO `medium`. This is the set the
          // backend would accept, so `medium` must not be offered.
          _model(
            'gpt-5.6-luna',
            efforts: [ReasoningEffort.low, ReasoningEffort.high],
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);
      await pickProviderAndModel(tester);

      expect(
        find.byKey(const Key('ai-reasoning-effort-picker')),
        findsOneWidget,
      );
      final picker = tester.widget<DropdownButton<ReasoningEffortChoice>>(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      // `auto` is always offered, the declared levels follow in enum order —
      // and nothing the pair does not declare, because the aggregate would
      // answer that with a 422 at save time.
      expect(picker.items!.map((item) => item.value).toList(), [
        ReasoningEffortChoice.auto,
        ReasoningEffortChoice.low,
        ReasoningEffortChoice.high,
      ]);
      expect(picker.value, ReasoningEffortChoice.auto);
    });

    testWidgets('the picker stays ONE readable row on a 360dp phone with every '
        'level declared', (tester) async {
      await setupContainer(
        modelsValue: Right([
          _model('gpt-5.6-luna', efforts: ReasoningEffort.values.toList()),
        ]),
      );
      // The narrowest supported Android width in the TEMPLATE locale: German
      // labels are the longest ones the control has to survive.
      await pumpScreen(
        tester,
        height: 2400,
        width: 360,
        locale: const Locale('de'),
      );
      await pickProviderAndModel(tester);
      await tester.ensureVisible(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the picker must not overflow a 360dp row',
      );

      // The regression this pins: the five segments of the old control did not
      // fit 328dp of content width, so each label was squeezed into a
      // per-character column ("Automatisch" rendered 11px wide and 220px
      // tall) and the row grew to 236px. One row is the whole claim.
      final pickerRect = tester.getRect(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      expect(
        pickerRect.height,
        lessThanOrEqualTo(64),
        reason: 'the picker must stay a single row, was ${pickerRect.height}px',
      );
      expect(pickerRect.right, lessThanOrEqualTo(360));

      // Narrow must not mean fewer choices: the menu offers `auto` plus every
      // level the model declares.
      await tester.tap(find.byKey(const Key('ai-reasoning-effort-picker')));
      await tester.pumpAndSettle();
      for (final level in ReasoningEffort.values) {
        expect(
          find.byKey(Key('ai-reasoning-effort-${level.name}')).last,
          findsOneWidget,
          reason: '${level.name} must stay reachable on a 360dp phone',
        );
      }
    });

    testWidgets('a model that declares no parameter renders the honest '
        'sentence instead of an empty picker', (tester) async {
      // The default fixture carries no capability: the pre-field backend AND
      // a provider catalogue without the parameter look like this.
      await setupContainer();
      await pumpScreen(tester, height: 2400);
      await pickProviderAndModel(tester);

      expect(find.byKey(const Key('ai-reasoning-effort-picker')), findsNothing);
      expect(
        find.byKey(const Key('ai-reasoning-effort-unavailable')),
        findsOneWidget,
      );
    });

    testWidgets('the chosen level reaches the create request', (tester) async {
      await setupContainer(
        modelsValue: Right([
          _model('gpt-5.6-luna', efforts: [ReasoningEffort.low]),
        ]),
      );
      await pumpScreen(tester, height: 2400);
      await pickProviderAndModel(tester);
      await pickReasoningEffort(tester, 'low');
      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'sk-test-123',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(
        repo.lastCreateRequest!.reasoningEffort,
        ReasoningEffortChoice.low,
      );
    });

    testWidgets('the configured form echoes the stored level', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(reasoningEffort: ReasoningEffortChoice.high),
        ]),
        modelsValue: Right([
          _model(
            'gpt-5.6-luna',
            efforts: [ReasoningEffort.low, ReasoningEffort.high],
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      final picker = tester.widget<DropdownButton<ReasoningEffortChoice>>(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      expect(picker.value, ReasoningEffortChoice.high);
    });

    testWidgets('RESETTING a stored level to auto reaches the PATCH — the '
        'direction a nullable field could never express', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(reasoningEffort: ReasoningEffortChoice.high),
        ]),
        modelsValue: Right([
          _model(
            'gpt-5.6-luna',
            efforts: [ReasoningEffort.low, ReasoningEffort.high],
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      await pickReasoningEffort(tester, 'auto');
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      // `auto` is a VALUE on the wire — not an omitted field, not a null. This
      // is the assertion that pins Option A: with `Option<ReasoningEffort>` the
      // generated client would have dropped the field and the level would have
      // survived the user's reset.
      expect(
        repo.lastUpdateRequest!.reasoningEffort,
        ReasoningEffortChoice.auto,
      );
    });

    testWidgets('switching to a model that does not declare the drafted level '
        'drops the draft to auto instead of dispatching a 422', (tester) async {
      await setupContainer(
        modelsValue: Right([
          _model('gpt-5.6-luna', efforts: [ReasoningEffort.medium]),
          // The second model declares nothing (a provider catalogue without the
          // parameter) — a draft of `medium` must not survive the switch.
          _model('gpt-5.6-terra'),
        ]),
      );
      await pumpScreen(tester, height: 2400);
      await pickProviderAndModel(tester);
      await pickReasoningEffort(tester, 'medium');

      // Switch to the model that declares nothing: the picker gives way to the
      // honest sentence.
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.6-terra').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-reasoning-effort-picker')), findsNothing);

      // Switch BACK: the draft no longer holds the level it did before, which
      // is the actual claim — a hidden picker alone would prove nothing.
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();

      final picker = tester.widget<DropdownButton<ReasoningEffortChoice>>(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      expect(picker.value, ReasoningEffortChoice.auto);
    });

    // --- Reasoning-effort selector: catalogue rotation and unknown catalogues
    // (review findings 4 and 5) ---

    testWidgets('a stored level the model no longer declares stays visible, '
        'selected AND unchanged (catalogue rotation)', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          // Stored while the same model id declared `minimal` (Neuralwatt); the
          // catalogue now declares `low|high` (the OpenCode shape).
          _config(reasoningEffort: ReasoningEffortChoice.minimal),
        ]),
        modelsValue: Right([
          _model(
            'gpt-5.6-luna',
            efforts: [ReasoningEffort.low, ReasoningEffort.high],
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      final picker = tester.widget<DropdownButton<ReasoningEffortChoice>>(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      // The effective choice is the stored level — a picker that renders NO
      // selected segment while the PATCH still carries `minimal` is the bug.
      expect(picker.value, ReasoningEffortChoice.minimal);
      expect(
        find.byKey(const Key('ai-reasoning-effort-minimal')),
        findsOneWidget,
        reason: 'the undeclared stored level must stay visible',
      );
      expect(
        picker.items!
            .firstWhere((item) => item.value == ReasoningEffortChoice.minimal)
            .enabled,
        isFalse,
        reason: 'it is not choosable — it is shown, not offered',
      );
      // `auto` and the levels the model DOES declare stay choosable.
      for (final choice in [
        ReasoningEffortChoice.auto,
        ReasoningEffortChoice.low,
        ReasoningEffortChoice.high,
      ]) {
        expect(
          picker.items!.firstWhere((item) => item.value == choice).enabled,
          isTrue,
          reason: '$choice must stay selectable',
        );
      }
      // The rotation is stated instead of silently corrected.
      expect(
        find.byKey(const Key('ai-reasoning-effort-stored')),
        findsOneWidget,
      );

      // An untouched save transmits the STORED level: the user changed nothing,
      // so the value the aggregate keeps must not silently become `auto`.
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();
      expect(repo.updateCalls, 1);
      expect(
        repo.lastUpdateRequest!.reasoningEffort,
        ReasoningEffortChoice.minimal,
      );

      // Only an EXPLICIT pick moves it — here the existing reset path.
      await pickReasoningEffort(tester, 'auto');
      expect(find.byKey(const Key('ai-reasoning-effort-stored')), findsNothing);
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();
      expect(
        repo.lastUpdateRequest!.reasoningEffort,
        ReasoningEffortChoice.auto,
      );
    });

    testWidgets('a failed model catalogue is UNKNOWN, not "this model offers '
        'nothing" — and does not reset the stored level', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(reasoningEffort: ReasoningEffortChoice.high),
        ]),
        modelsValue: const Left(
          ProblemError(code: 'ai-import.models-unavailable', status: 503),
        ),
      );
      await pumpScreen(tester, height: 2400);

      // A 503 of the catalogue must never become a statement about the model.
      expect(
        find.byKey(const Key('ai-reasoning-effort-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ai-reasoning-effort-unknown')),
        findsOneWidget,
      );
      final picker = tester.widget<DropdownButton<ReasoningEffortChoice>>(
        find.byKey(const Key('ai-reasoning-effort-picker')),
      );
      expect(
        picker.value,
        ReasoningEffortChoice.high,
        reason: 'the stored level is kept, not reset to auto',
      );

      // A prompt-only edit over the unknown catalogue still carries `high`.
      await _enterPrompt(tester, 'ai-edit-script-prompt', 'Edited blind');
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();
      expect(repo.updateCalls, 1);
      expect(
        repo.lastUpdateRequest!.reasoningEffort,
        ReasoningEffortChoice.high,
      );
    });

    testWidgets('a LOADING model catalogue is unknown too — the same false '
        'sentence must not render', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(reasoningEffort: ReasoningEffortChoice.high),
        ]),
        modelsPending: true,
      );
      await pumpScreen(tester, height: 2400, settle: false);

      expect(
        find.byKey(const Key('ai-reasoning-effort-unavailable')),
        findsNothing,
        reason: 'a pending catalogue knows nothing about the model',
      );
      expect(
        find.byKey(const Key('ai-reasoning-effort-unknown')),
        findsOneWidget,
      );
    });

    // --- Decision Model section (issue #723) ---

    testWidgets('first-run: the decision section renders with the honest '
        'disabled default and no model picker', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-decision-section')), findsOneWidget);
      expect(
        find.byKey(const Key('ai-decision-provider-disabled')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-decision-model-picker')), findsNothing);
    });

    testWidgets('same decision provider: the same-key toggle renders (on by '
        'default) and create reuses the extraction vault key without a '
        'second credential (issue #723, spec scenario 1)', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Extraction provider = neuralwatt.
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();

      // Decision provider = neuralwatt (the same provider).
      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      // The model picker renders with the DECISION catalog (issue #731:
      // `clef-flash`/`clef`, not the extraction list); the same-key toggle
      // renders ON; no separate decision key field.
      expect(find.byKey(const Key('ai-decision-model-picker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('clef-flash').last);
      await tester.pumpAndSettle();
      final toggle = tester.widget<CheckboxListTile>(
        find.byKey(const Key('ai-decision-same-key-toggle')),
      );
      expect(toggle.value, isTrue);
      expect(find.byKey(const Key('ai-decision-api-key-field')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'extraction-secret',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      // Exactly ONE credential submission (the extraction key), and the
      // create carries the decision slot bound to the SAME vault key.
      expect(repo.submitCalls, 1);
      expect(repo.lastCreateRequest!.decisionProvider, LlmProvider.neuralwatt);
      expect(
        repo.lastCreateRequest!.decisionVaultKeyId,
        repo.lastCreateRequest!.vaultKeyId,
      );
      expect(repo.lastCreateRequest!.decisionModel, 'clef-flash');
    });

    testWidgets('split billing: a different decision provider prompts for a '
        'separate key, binds it as a second credential and remembers it '
        '(issue #723, spec scenario 2)', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Extraction provider = openai (default suggestion).
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('openai').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();

      // Decision provider = neuralwatt (different from extraction).
      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      // No same-key toggle across providers; the masked decision key
      // field renders instead.
      expect(
        find.byKey(const Key('ai-decision-same-key-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ai-decision-api-key-field')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('clef-flash').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'extraction-secret',
      );
      await tester.enterText(
        find.byKey(const Key('ai-decision-api-key-field')),
        'decision-secret',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      // TWO credential submissions: the extraction one (openai) and the
      // decision one (neuralwatt — the provider the user selected).
      expect(repo.submitCalls, 2);
      expect(repo.lastProvider, 'neuralwatt');
      expect(repo.lastCreateRequest!.decisionProvider, LlmProvider.neuralwatt);
      expect(repo.lastCreateRequest!.decisionVaultKeyId, isNotNull);

      // The decision credential reference is remembered under the
      // decision-scoped hand-off slot for the next edit.
      final sub = (await container.read(authSessionControllerProvider.future))!
          .sub;
      final remembered = (await AiImportHandoffStore.secure().read(sub))
          .getRight()
          .toNullable()!;
      expect(remembered.decisionCredentialFor('neuralwatt'), isNotNull);
    });

    testWidgets('the decision model picker surfaces the curated DECISION '
        'catalog (neuralwatt: clef-flash/clef) while the assistant picker '
        'stays on the extraction list (issue #731 regression)', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Extraction provider = neuralwatt, assistant model picked from the
      // extraction catalog.
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      // The assistant picker shows the EXTRACTION list only.
      expect(find.text('gpt-5.6-luna').last, findsOneWidget);
      expect(find.text('clef-flash'), findsNothing);
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();

      // Decision provider = neuralwatt: the decision picker must show the
      // curated decision catalog (clef-flash/clef), NOT the extraction
      // list (deepseek/glm/kimi/qwen stand-ins are the gpt fixtures here).
      // The key-aware decision fixture (see setupContainer) only serves the
      // clef catalog for the 'neuralwatt' key — a controller that called the
      // decision route with the extraction provider's key (or the extraction
      // provider function) would surface gpt entries here and fail below.
      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
      await tester.pumpAndSettle();
      // The decision catalog is open: clef-flash and clef are present.
      expect(find.text('clef-flash').last, findsOneWidget);
      expect(find.text('clef').last, findsOneWidget);
      // …and the extraction entries are NOT in the decision menu.
      expect(find.text('gpt-5.6-terra'), findsNothing);
      await tester.tap(find.text('clef-flash').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'extraction-secret',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      // The create carries a decision model from the DECISION catalog.
      expect(repo.lastCreateRequest!.decisionModel, 'clef-flash');
    });

    testWidgets('the decision picker degrades with the honest 422 "provider '
        'unavailable" copy — never the generic catalog copy, and never at '
        'the expense of the assistant picker (issue #731 fix point 4)', (
      tester,
    ) async {
      // The decision-models route answers 422 for this provider (unknown /
      // not decision-capable). Pre-fix the decision picker flattened EVERY
      // failure to `aiConfigModelCatalogUnavailable`, so a provider the
      // server rejects outright looked like a transient catalog problem.
      await setupContainer(
        decisionModelsValue: const Left(
          ProblemError(code: 'provider.unknown', status: 422),
        ),
      );
      await pumpScreen(tester, height: 2400);

      // Extraction provider = neuralwatt (its assistant catalog resolves).
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      // 422 → the provider-unavailable narrative, exactly as the assistant
      // and image pickers render it.
      expect(find.byKey(const Key('ai-decision-models-degraded')), findsOne);
      expect(
        find.text('Provider unavailable — the model catalog cannot be read.'),
        findsOneWidget,
      );
      expect(find.text('The model catalog could not be loaded.'), findsNothing);
      // No decision picker to pick from, so the section cannot bind a model.
      expect(find.byKey(const Key('ai-decision-model-picker')), findsNothing);
      // …while the assistant catalog is UNAFFECTED by the decision route's
      // failure (the two providers are independent).
      expect(find.byKey(const Key('ai-assistant-model-picker')), findsOne);
    });

    testWidgets('a non-422 decision-catalog failure keeps the generic '
        '"catalog could not be loaded" copy (issue #731 fix point 4)', (
      tester,
    ) async {
      await setupContainer(
        decisionModelsValue: const Left(
          ProblemError(code: 'transport.error', status: 503),
        ),
      );
      await pumpScreen(tester, height: 2400);

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      // A transport-class failure is NOT a provider-unavailable verdict: the
      // catalog copy stays, so the 422 branch is a real discriminator rather
      // than a blanket replacement.
      expect(find.byKey(const Key('ai-decision-models-degraded')), findsOne);
      expect(
        find.text('The model catalog could not be loaded.'),
        findsOneWidget,
      );
      expect(
        find.text('Provider unavailable — the model catalog cannot be read.'),
        findsNothing,
      );
    });

    testWidgets('the image model picker surfaces the curated IMAGE catalog '
        '(openai: gpt-image-*) while the assistant picker stays on the '
        'extraction list (issue #732 regression)', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Extraction provider = openai (the first curated provider, also the
      // first-run suggestion). The image picker must show the IMAGE
      // catalog (gpt-image-*), NOT the extraction list — pre-#732 it
      // iterated the same state.models list as the assistant picker.
      await tester.tap(find.byKey(const Key('ai-image-model-picker')));
      await tester.pumpAndSettle();
      expect(find.text('gpt-image-2').last, findsOneWidget);
      expect(find.text('gpt-image-1').last, findsOneWidget);
      // …and the extraction entries are NOT in the image menu.
      expect(find.text('gpt-5.6-terra'), findsNothing);
      await tester.tap(find.text('gpt-image-2').last);
      await tester.pumpAndSettle();

      // The assistant picker still lists the EXTRACTION catalog.
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      expect(find.text('gpt-5.6-luna').last, findsOneWidget);
      // gpt-image-1 is unselected, so its only possible render is inside
      // the (closed) image picker — absent here means the assistant menu
      // carries no image entries.
      expect(find.text('gpt-image-1'), findsNothing);
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();

      // The picked image model rides the create payload.
      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'extraction-secret',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      expect(repo.lastCreateRequest!.imageModel, 'gpt-image-2');
    });

    testWidgets('the image model picker collapses to "— none —" with a '
        'greyed-out field and a hint for a text-only provider '
        '(issue #732 honest degradation)', (tester) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Extraction provider = neuralwatt — no curated image models (the
      // backend serves an EMPTY 200 on the image-models route).
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      // The picker renders greyed out (null onChanged) with the hint —
      // the honest "no image models" degradation, never the LLM list.
      final imagePicker = tester.widget<DropdownButtonFormField<String?>>(
        find.byKey(const Key('ai-image-model-picker')),
      );
      expect(imagePicker.onChanged, isNull);
      expect(find.byKey(const Key('ai-image-models-none')), findsOneWidget);
    });

    testWidgets('the image picker stays usable when the assistant catalog is '
        'degraded — independent honest states (issue #732, CodeRabbit '
        'review)', (tester) async {
      await setupContainer(
        // Assistant/extraction catalog fails (e.g. 422 provider
        // unavailable) while the image catalog succeeds.
        modelsValue: const Left(
          ProblemError(code: 'provider.unavailable', status: 422),
        ),
      );
      await pumpScreen(tester, height: 2400);

      // The assistant picker renders its degraded copy…
      expect(find.byKey(const Key('ai-models-degraded')), findsOneWidget);
      // …while the image picker is STILL rendered and usable — a user
      // editing an existing configuration can change or clear its image
      // model although the assistant catalog is degraded.
      await tester.tap(find.byKey(const Key('ai-image-model-picker')));
      await tester.pumpAndSettle();
      expect(find.text('gpt-image-2').last, findsOneWidget);
      await tester.tap(find.text('gpt-image-2').last);
      await tester.pumpAndSettle();
      expect(
        container.read(aiConfigControllerProvider).selectedImageModelId,
        'gpt-image-2',
      );
    });

    testWidgets('edit: an untouched decision slot echoes the stored binding — '
        'no accidental clear (issue #723, task 1.2)', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(
            decisionProvider: LlmProvider.neuralwatt,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-decision',
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateRequest!.decisionProvider, LlmProvider.neuralwatt);
      expect(repo.lastUpdateRequest!.decisionModel, 'clef-flash');
      expect(repo.lastUpdateRequest!.decisionVaultKeyId, 'vk-decision');
    });

    testWidgets('edit: a stored SAME-PROVIDER split-billing binding survives '
        'an untouched save — the derived toggle stays off and the stored '
        'decision key is echoed, never rebound to the extraction key '
        '(CodeRabbit review, issue #723)', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(
            decisionProvider: LlmProvider.openai,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-decision',
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      // The same-provider toggle renders, DERIVED OFF from the stored
      // split-billing binding (decision key ≠ extraction key).
      final toggle = tester.widget<CheckboxListTile>(
        find.byKey(const Key('ai-decision-same-key-toggle')),
      );
      expect(toggle.value, isFalse);

      // An unrelated save (no decision interaction) echoes the stored
      // binding — it must NOT silently rebind to the extraction key.
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateRequest!.decisionProvider, LlmProvider.openai);
      expect(repo.lastUpdateRequest!.decisionModel, 'clef-flash');
      expect(repo.lastUpdateRequest!.decisionVaultKeyId, 'vk-decision');
      expect(repo.lastUpdateRequest!.vaultKeyId, 'vk-1');
    });

    testWidgets('edit: picking the disabled entry CLEARS the decision slot '
        'via the tri-state explicit null (issue #723)', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(
            decisionProvider: LlmProvider.neuralwatt,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-decision',
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-decision-provider-disabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      // The patched tri-state serializer sends explicit JSON nulls — the
      // backend clears the stored Decision Model (omitted would keep it).
      expect(repo.lastUpdateRequest!.decisionProvider, isNull);
      expect(repo.lastUpdateRequest!.decisionModel, isNull);
      expect(repo.lastUpdateRequest!.decisionVaultKeyId, isNull);
    });

    // --- Zero-data-retention attestation (issue #968) ---

    group('zero-data-retention attestation (issue #968)', () {
      testWidgets(
        'create: the ZDR attestation is OFF by default and travels on '
        'the create request once enabled (issue #968)',
        (tester) async {
          await setupContainer();
          await pumpScreen(tester, height: 2400);

          // Fail-closed default: an untouched form attests nothing.
          final toggle = tester.widget<CheckboxListTile>(
            find.byKey(const Key('ai-zdr-attested-toggle')),
          );
          expect(toggle.value, isFalse);

          await tester.tap(find.byKey(const Key('ai-zdr-attested-toggle')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.byKey(const Key('ai-zdr-attested-toggle')),
                )
                .value,
            isTrue,
          );

          await tester.enterText(
            find.byKey(const Key('ai-api-key-field')),
            'extraction-secret',
          );
          await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('ai-config-create')));
          await tester.pumpAndSettle();

          expect(repo.lastCreateRequest!.zdrAttested, isTrue);
        },
      );

      testWidgets(
        'edit: a stored attestation is seeded ON and an unrelated save '
        'keeps it, while flipping it off revokes it explicitly (issue #968)',
        (tester) async {
          await setupContainer(
            discoveryValue: Right([_config(zdrAttested: true)]),
          );
          await pumpScreen(tester, height: 2400);

          // The stored attestation is the seeded baseline, so an unrelated save
          // (the prompt is untouched) is not an unsaved change.
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.byKey(const Key('ai-zdr-attested-toggle')),
                )
                .value,
            isTrue,
          );

          await tester.tap(find.byKey(const Key('ai-config-edit-save')));
          await tester.pumpAndSettle();
          expect(repo.lastUpdateRequest!.zdrAttested, isTrue);

          // Revoking it is an explicit, dispatched change — never a silent side
          // effect of another edit.
          await tester.tap(find.byKey(const Key('ai-zdr-attested-toggle')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('ai-config-edit-save')));
          await tester.pumpAndSettle();
          expect(repo.lastUpdateRequest!.zdrAttested, isFalse);
        },
      );
    });

    // --- Round-trip verification of the Decision Model (issue #769) ---

    testWidgets('edit: the PATCH body carries the Decision Model triple AND '
        'the save is only reported as successful once the read-back confirms '
        'it (issue #769)', (tester) async {
      // Extraction and decision provider are the SAME (neuralwatt): the
      // same-key reuse path applies, so the save needs no separate Decision
      // credential — the dispatch under test is the PATCH itself.
      await setupContainer(
        discoveryValue: Right([_config(provider: LlmProvider.neuralwatt)]),
      );
      await pumpScreen(tester, height: 2400);

      // Pick a decision provider + model (neuralwatt / clef-flash is the
      // curated pair the fixture serves).
      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('clef-flash').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      // (a) The wire body carries all three parts — the regression this test
      // exists for: a client that silently dropped one of them would leave
      // the backend with no scoring configuration at all.
      expect(repo.lastUpdateRequest!.decisionProvider, LlmProvider.neuralwatt);
      expect(repo.lastUpdateRequest!.decisionModel, 'clef-flash');
      expect(
        repo.lastUpdateRequest!.decisionVaultKeyId,
        isNotNull,
        reason: 'the binding must ride along (shared or own key)',
      );

      // (b) The read-back was actually performed before success.
      expect(repo.getConfigCalls, greaterThan(0));
    });

    testWidgets('edit: a read-back WITHOUT the submitted Decision Model is a '
        'failure, not a silent success — the localized error renders and the '
        'draft is preserved (issue #769)', (tester) async {
      // Extraction and decision provider are the SAME (neuralwatt): the
      // same-key reuse path applies, so the save needs no separate Decision
      // credential — the dispatch under test is the PATCH itself.
      await setupContainer(
        discoveryValue: Right([_config(provider: LlmProvider.neuralwatt)]),
      );
      await pumpScreen(tester, height: 2400);

      // Model the reported defect: the PATCH is acknowledged, but the
      // authoritative view has NULL decision columns.
      repo.getConfigResult = Right(_config(assistantModel: 'gpt-5.6-luna'));

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-decision-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('clef-flash').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      // The screen localizes its OWN copy keyed on the client-detected code;
      // the English catalog string is the assertion target (the same style as
      // every other error-copy test in this file).
      expect(
        find.text(
          "The decision model was not saved. The configuration was sent, but "
          "the server's read-back does not contain it — please check the "
          'selection and save again.',
        ),
        findsOneWidget,
        reason:
            'a non-persisted Decision Model must be surfaced, keyed on the '
            'client-detected code ai_config.decision_not_persisted',
      );
      expect(repo.getConfigCalls, greaterThan(0));
    });

    testWidgets('edit: projector lag that clears inside the retry budget is '
        'NOT reported as a persistence failure (issue #769 review)', (
      tester,
    ) async {
      await setupContainer(
        discoveryValue: Right([_config(provider: LlmProvider.neuralwatt)]),
      );
      await pumpScreen(tester, height: 2400);

      // The first read-back still sees the pre-PATCH projection (NULL decision
      // columns), the second one sees the committed triple — exactly the
      // projector lag the client must reconcile with a bounded-retry refetch
      // (AGENTS.md §4) instead of reporting a false "not persisted".
      repo.getConfigScript = [
        Right(_config(provider: LlmProvider.neuralwatt)),
        Right(
          _config(
            provider: LlmProvider.neuralwatt,
            decisionProvider: LlmProvider.neuralwatt,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-1',
          ),
        ),
      ];

      await pickDecisionProviderAndModel(tester);
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      expect(
        repo.getConfigCalls,
        2,
        reason: 'the lagging first read must be retried, not believed',
      );
      expect(
        find.text(
          "The decision model was not saved. The configuration was sent, but "
          "the server's read-back does not contain it — please check the "
          'selection and save again.',
        ),
        findsNothing,
        reason: 'a lagging projection is not a persistence failure',
      );
    });

    testWidgets('edit: a failed read-back replaces the stale pre-PATCH view, '
        'so the retry is not rejected as a version conflict (issue #769 '
        'review)', (tester) async {
      await setupContainer(
        discoveryValue: Right([
          _config(provider: LlmProvider.neuralwatt, version: 1),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      // The projection lags on every attempt of the FIRST save and settles on
      // the committed version (5) — the version the retry must use.
      repo.getConfigScript = [
        for (var attempt = 0; attempt < kMaxReconcileAttempts; attempt++)
          Right(_config(provider: LlmProvider.neuralwatt, version: 5)),
      ];

      await pickDecisionProviderAndModel(tester);
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      expect(
        repo.lastUpdateRequest!.version,
        1,
        reason: 'the first PATCH carries the cached version',
      );
      expect(
        find.byKey(const Key('ai-config-error-banner')),
        findsOneWidget,
        reason: 'the mismatch is never silently dropped',
      );

      // Retry: the scripted lag is exhausted, so the fake echoes the submitted
      // body and the save succeeds. The PATCH must carry the authoritative
      // version from the read-back — the stale cached 1 would be a 409.
      await tester.tap(find.byKey(const Key('ai-config-edit-save')));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateRequest!.version, 5);
      expect(find.byKey(const Key('ai-config-error-banner')), findsNothing);
    });

    testWidgets('create: a read-back WITHOUT the submitted Decision Model '
        'surfaces the error above the (real) created configuration instead of '
        'dropping it with the discovery refresh (issue #769 review)', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester, height: 2400);

      // Same-provider (neuralwatt) decision binding: the same-key reuse path
      // applies, so no separate Decision key field is rendered.
      await tester.tap(find.byKey(const Key('ai-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-assistant-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.6-luna').last);
      await tester.pumpAndSettle();
      await pickDecisionProviderAndModel(tester);

      // The create is acknowledged but the stored config carries no decision
      // columns — the reported defect.
      repo.getConfigResult = Right(_config(provider: LlmProvider.neuralwatt));

      await tester.enterText(
        find.byKey(const Key('ai-api-key-field')),
        'sk-test-123',
      );
      await tester.ensureVisible(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-create')));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      // The created config is real → the configured view renders …
      expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
      // … and the mismatch is still surfaced: refreshing the projection must
      // never swallow the verdict (that is the "looked saved" defect itself).
      expect(
        find.text(
          "The decision model was not saved. The configuration was sent, but "
          "the server's read-back does not contain it — please check the "
          'selection and save again.',
        ),
        findsOneWidget,
      );
    });

    // --- Decision provider capability from the route (issue #736) ---

    testWidgets('the decision provider picker renders exactly the providers '
        'the route reports decision_capable — a newly capable provider '
        'appears, a de-listed one disappears (issue #736 regression)', (
      tester,
    ) async {
      // The route is the authority: `eurouter` is reported capable (a
      // provider the pre-#736 client allowlist would only show after a code
      // change), `openrouter` is reported NOT capable (de-listed by the
      // backend), `openai`/`gemini` were never capable.
      await setupContainer(
        providersValue: Right([
          _provider('openai', LlmProvider.openai),
          _provider('gemini', LlmProvider.gemini),
          _provider(
            'neuralwatt',
            LlmProvider.neuralwatt,
            decisionCapable: true,
          ),
          _provider('eurouter', LlmProvider.eurouter, decisionCapable: true),
          _provider('openrouter', LlmProvider.openrouter),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();

      // The explicit "disabled" entry stays (never derived from the route).
      expect(
        find.byKey(const Key('ai-decision-provider-disabled')),
        findsWidgets,
      );
      // Capable providers are offered …
      expect(
        find.byKey(const Key('ai-decision-provider-neuralwatt')),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('ai-decision-provider-eurouter')),
        findsWidgets,
      );
      // … non-capable ones are not (the picker would otherwise offer a
      // provider whose decision-models route answers 422 — the dead end
      // this issue removes).
      expect(
        find.byKey(const Key('ai-decision-provider-openai')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ai-decision-provider-gemini')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ai-decision-provider-openrouter')),
        findsNothing,
      );
    });

    testWidgets('a configured decision provider the route no longer reports '
        'decision-capable still renders (stale-key fallback, issue #736)', (
      tester,
    ) async {
      // The backend de-listed `neuralwatt` as decision-capable — modelled
      // here as an ABSENT flag (`null`), i.e. exactly what a backend that
      // predates the field serves (CodeRabbit review). The stored config must
      // still be representable, otherwise the Dropdown asserts on an unknown
      // initialValue and the user cannot open the screen at all.
      await setupContainer(
        discoveryValue: Right([
          _config(
            decisionProvider: LlmProvider.neuralwatt,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-decision',
          ),
        ]),
        providersValue: Right([
          _provider('openai', LlmProvider.openai),
          _provider(
            'neuralwatt',
            LlmProvider.neuralwatt,
            decisionCapable: null,
          ),
        ]),
      );
      await pumpScreen(tester, height: 2400);

      // The section and its model picker still render — the stored model is
      // echoed, not silently dropped (the Dropdown would have thrown on an
      // initialValue that is absent from `items`).
      expect(find.byKey(const Key('ai-decision-section')), findsOneWidget);
      expect(find.byKey(const Key('ai-decision-model-picker')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();

      // The stale entry renders with the stored key as its label, next to
      // the always-present "disabled" entry.
      expect(
        find.byKey(const Key('ai-decision-provider-neuralwatt')),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('ai-decision-provider-disabled')),
        findsWidgets,
      );
    });
  });

  group('unsaved changes (draft-vs-stored guard)', () {
    // The reported defect: a Decision Model picked in the AI-config form was
    // never persisted because the save affordance sat at the end of the long
    // scrolling form and leaving the screen silently dropped the draft — the
    // app looked configured while the aggregate had no such state. The fix is
    // a persistent primary action plus an explicit discard decision.
    test(
      'an untouched, seeded form is NOT dirty; a picked Decision Model is',
      () {
        final stored = _config(prompts: const {'script': 'stored script'});
        final seeded = AiConfigScreenState(
          config: stored,
          providers: const AsyncValue.data(<AiProviderInfo>[]),
          models: const AsyncValue.data(<ModelInfo>[]),
          selectedProviderKey: 'openai',
          selectedAssistantModelId: 'gpt-5.6-luna',
          scriptPrompt: 'stored script',
        );
        expect(
          seeded.hasUnsavedChanges,
          isFalse,
          reason: 'a re-seeded form is not an edit',
        );

        final picked = seeded.copyWith(
          selectedDecisionProviderKey: 'neuralwatt',
          selectedDecisionModelId: 'clef-flash',
        );
        expect(picked.hasUnsavedChanges, isTrue);

        // Clearing the Decision Model is a REAL change too (tri-state null).
        final cleared = AiConfigScreenState(
          config: _config(
            decisionProvider: LlmProvider.neuralwatt,
            decisionModel: 'clef-flash',
            decisionVaultKeyId: 'vk-1',
          ),
          providers: const AsyncValue.data(<AiProviderInfo>[]),
          models: const AsyncValue.data(<ModelInfo>[]),
          selectedProviderKey: 'openai',
          selectedAssistantModelId: 'gpt-5.6-luna',
        );
        expect(
          cleared.hasUnsavedChanges,
          isTrue,
          reason: 'the stored Decision Model is not echoed by the form',
        );
      },
    );

    testWidgets('the action bar marks unsaved changes and keeps the save '
        'reachable', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpScreen(tester);

      // Always visible (sticky), and clean before any edit.
      expect(find.byKey(const Key('ai-config-action-bar')), findsOneWidget);
      expect(find.byKey(const Key('ai-config-edit-save')), findsOneWidget);
      expect(find.byKey(const Key('ai-config-unsaved-label')), findsNothing);
      expect(find.byKey(const Key('ai-config-discard-changes')), findsNothing);

      // A Decision Model edit — the exact case that used to be lost.
      await tester.tap(find.byKey(const Key('ai-decision-provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('neuralwatt').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-config-unsaved-label')), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(
        find.byKey(const Key('ai-config-discard-changes')),
        findsOneWidget,
      );
      // Nothing was dispatched yet — the change lives in the draft.
      expect(repo.updateCalls, 0);
    });

    testWidgets('discard drops the draft back to the stored configuration '
        'without dispatching', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpScreen(tester);

      await pickDecisionProviderAndModel(tester);
      expect(find.byKey(const Key('ai-config-unsaved-label')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-config-discard-changes')));
      await tester.pumpAndSettle();

      // The stored configuration is rendered again: no decision selection,
      // no unsaved marker, no PATCH.
      expect(find.byKey(const Key('ai-config-unsaved-label')), findsNothing);
      final state = container.read(aiConfigControllerProvider);
      expect(state.selectedDecisionProviderKey, isNull);
      expect(state.selectedDecisionModelId, isNull);
      expect(repo.updateCalls, 0);
    });

    test('discard resets the form drafts but never the unresolved-create '
        'state', () async {
      await setupContainer();
      // CodeRabbit review (PR #807): `reset()` dropped `unresolved`, so the
      // bar's Discard deleted the only in-app handle on an unconfirmed create
      // (its Re-check / Clean-up actions and the credential's settings
      // identity). The lifecycle state is not a form value and must survive.
      final drafts = container.read(aiConfigDraftsProvider.notifier);
      drafts.mutate((d) {
        d.selectedDecisionProviderKey = 'neuralwatt';
        d.decisionProviderTouched = true;
        d.unresolved = AiConfigUnresolved(
          settingsId: 'settings-1',
          settingsVersion: 1,
          vaultKeyId: 'vk-1',
          providerKey: 'openai',
          assistantModelId: 'gpt-5.6-luna',
          imageModelId: null,
          scriptPrompt: '',
          schedulePrompt: '',
          error: const ProblemError(code: 'transport.connectionTimeout'),
        );
      });
      expect(container.read(aiConfigDraftsProvider).unresolved, isNotNull);

      drafts.reset();

      final reset = container.read(aiConfigDraftsProvider);
      expect(
        reset.unresolved,
        isNotNull,
        reason: 'lifecycle state is preserved',
      );
      expect(
        reset.selectedDecisionProviderKey,
        isNull,
        reason: 'form drafts are dropped',
      );
      expect(reset.decisionProviderTouched, isFalse);
    });

    testWidgets('the dirty action bar stays inside a narrow screen at a large '
        'text scale', (tester) async {
      // A `Row` gave the two action labels unbounded width, so a long label at
      // a large text scale ran past the bar and could hide the save action
      // (CodeRabbit review, PR #807). The bar wraps now, so nothing overflows
      // and the primary action keeps its full hit rect on screen.
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpScreen(tester, width: 320, height: 1200, textScale: 3.0);

      // Dirty the form through the draft store instead of the pickers: the
      // ListView is lazy, so at 3x text scale the Decision picker is not even
      // built, and opening its menu would put the test's overflow assertion on
      // the menu rather than on the bar.
      container.read(aiConfigDraftsProvider.notifier).mutate((d) {
        d.selectedDecisionProviderKey = 'neuralwatt';
        d.decisionProviderTouched = true;
        d.selectedDecisionModelId = 'clef-flash';
        d.decisionModelTouched = true;
      });
      await tester.pumpAndSettle();

      // No RenderFlex overflow was reported while laying the bar out.
      // `takeException` CLEARS the pending exception, so it is read exactly
      // once — an earlier debug read made this assertion vacuous (CodeRabbit
      // review, PR #951).
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ai-config-unsaved-label')), findsOneWidget);

      final save = find.byKey(const Key('ai-config-edit-save'));
      expect(save, findsOneWidget);
      final rect = tester.getRect(save);
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(
        rect.right,
        lessThanOrEqualTo(320.0),
        reason: 'the save action must stay on screen, got $rect',
      );
    });

    testWidgets('back navigation with unsaved changes asks before discarding '
        '(keep editing leaves the draft intact)', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpPushedScreen(tester);
      await pickDecisionProviderAndModel(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-config-unsaved-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-config-unsaved-keep-editing')));
      await tester.pumpAndSettle();

      // Still on the screen, draft intact.
      expect(find.byKey(const Key('ai-config-unsaved-dialog')), findsNothing);
      expect(find.byKey(const Key('ai-config-configured')), findsOneWidget);
      expect(find.byKey(const Key('ai-config-unsaved-label')), findsOneWidget);
    });

    testWidgets('back navigation with unsaved changes: confirming the discard '
        'drops the draft and leaves', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpPushedScreen(tester);
      await pickDecisionProviderAndModel(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-config-unsaved-discard')));
      await tester.pumpAndSettle();

      // Back on the host route — and nothing was dispatched: the stored
      // configuration was never half-saved by leaving the screen.
      expect(find.byKey(const Key('open-ai-config')), findsOneWidget);
      expect(find.byKey(const Key('ai-config-configured')), findsNothing);
      expect(repo.updateCalls, 0);
    });

    testWidgets('back navigation WITHOUT unsaved changes is not intercepted', (
      tester,
    ) async {
      await setupContainer(discoveryValue: Right([_config()]));
      await pumpPushedScreen(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-config-unsaved-dialog')), findsNothing);
      expect(find.byKey(const Key('open-ai-config')), findsOneWidget);
    });
  });

  group('provider health + budget (issue #942 W4/W5)', () {
    testWidgets('a usable account renders its remaining budget', (
      tester,
    ) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(budget: AiProviderBudgetView((b) => b..remaining = 12.5)),
      );
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-config-provider-health')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-config-provider-health-status')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-status')),
            )
            .data,
        l10nEn().aiConfigProviderHealthUsable,
      );
      // The provider key the route was asked about is the WIRE key from the
      // catalog, not the Dart enum name.
      expect(repo.healthCalls, contains('openai'));
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-budget')),
            )
            .data,
        contains('12'),
      );
    });

    testWidgets('a provider that reports no limit is not a fabricated zero', (
      tester,
    ) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(budget: AiProviderBudgetView((b) => b..remaining = null)),
      );
      await pumpScreen(tester);

      final budget = tester.widget<Text>(
        find.byKey(const Key('ai-config-provider-health-budget')),
      );
      expect(budget.data, l10nEn().aiConfigProviderHealthBudgetUnlimited);
      expect(budget.data, isNot(contains('0')));
    });

    testWidgets('a provider without a budget read renders "unknown"', (
      tester,
    ) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(_healthView());
      await pumpScreen(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-budget')),
            )
            .data,
        l10nEn().aiConfigProviderHealthBudgetUnknown,
      );
    });

    testWidgets(
      'an exhausted quota gets its own narrative, never "unreachable"',
      (tester) async {
        await setupContainer(discoveryValue: Right([_config()]));
        repo.healthResult = Right(
          _healthView(
            status: AccountProbeStatus.notUsable,
            budget: AiProviderBudgetView((b) => b..remaining = 0),
          ),
        );
        await pumpScreen(tester);

        final status = tester.widget<Text>(
          find.byKey(const Key('ai-config-provider-health-status')),
        );
        expect(status.data, l10nEn().aiConfigProviderHealthNotUsable);
        // The #809 rule: a provider problem must never be rendered as a BACKEND
        // reachability problem.
        expect(
          find.text(l10nEn().aiConfigBackendUnreachableTitle),
          findsNothing,
        );
      },
    );

    testWidgets('an unconfigured provider is stated, not blamed', (
      tester,
    ) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(
          credentialConfigured: false,
          status: AccountProbeStatus.unknown,
        ),
      );
      await pumpScreen(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-status')),
            )
            .data,
        l10nEn().aiConfigProviderHealthUnconfigured,
      );
    });

    testWidgets('a paused pair names its next probe', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(
          breakers: [
            AiProviderBreakerView(
              (b) => b
                ..provider = LlmProvider.openai
                ..model = 'gpt-5.6-luna'
                ..state = ProviderBreakerState.open
                ..consecutiveFailures = 3
                ..flapCount = 1
                ..retryAt = DateTime.utc(2026, 11, 19, 10, 30)
                ..trialGranted = false,
            ),
          ],
        ),
      );
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-config-provider-health-held-gpt-5.6-luna')),
        findsOneWidget,
      );
      expect(
        find.text(l10nEn().aiConfigProviderHealthHeldTitle),
        findsOneWidget,
      );
    });

    testWidgets('a granted trial says so instead of claiming a running call', (
      tester,
    ) async {
      // `trial_granted` is the GRANT: the server stamps the job id and returns
      // the job to the queue, so no provider call needs to be running yet. Copy
      // that says "in flight" asserts an execution nobody observed.
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(
          breakers: [
            AiProviderBreakerView(
              (b) => b
                ..provider = LlmProvider.openai
                ..model = 'gpt-5.6-luna'
                ..state = ProviderBreakerState.halfOpen
                ..consecutiveFailures = 3
                ..flapCount = 1
                ..trialGranted = true,
            ),
          ],
        ),
      );
      await pumpScreen(tester);

      expect(
        find.text(l10nEn().aiConfigProviderHealthTrial('gpt-5.6-luna')),
        findsOneWidget,
      );
      expect(find.textContaining('in flight'), findsNothing);
    });

    testWidgets('a resolved capability denial renders no permission and no '
        'retry', (tester) async {
      // The RENDERING of the denial. The gate itself (that nothing is
      // dispatched) is asserted on the real provider below, because a widget
      // override would replace the very code under test.
      await setupContainer(
        discoveryValue: Right([_config()]),
        healthOverride: const Left(
          ProblemError(code: kAiConfigCapabilityDeniedCode, status: 403),
        ),
      );
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-config-provider-health-forbidden')),
        findsOneWidget,
      );
      // A denial is not a transient failure: retrying cannot flip a role.
      expect(
        find.byKey(const Key('ai-config-provider-health-retry')),
        findsNothing,
      );
    });

    test('aiProviderHealth short-circuits on a resolved capability denial', () async {
      await setupContainer(
        capabilitiesFetch: () async => const Right(
          MyCapabilities(canManageAiConfig: false, canReadOps: false),
        ),
      );
      // Resolve the capability answer FIRST — the state the screen is in, since
      // the Settings entry that owns the route watches it before the push.
      await container.read(myCapabilitiesProvider.future);

      final result = await container.read(
        aiProviderHealthProvider('openai').future,
      );

      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        kAiConfigCapabilityDeniedCode,
      );
      // #816: the gated read is NOT dispatched — the assertion is about the
      // request, not the rendering.
      expect(repo.healthCalls, isEmpty);
    });

    test(
      'aiProviderHealth dispatches when the capability answer is unknown',
      () async {
        await setupContainer(
          capabilitiesFetch: () async =>
              Left(ProblemError(code: 'transport.connectionError')),
        );
        // An errored capability read is UNKNOWN, never a denial.
        await expectLater(
          container.read(myCapabilitiesProvider.future),
          throwsA(anything),
        );

        final result = await container.read(
          aiProviderHealthProvider('openai').future,
        );

        expect(result.isRight(), isTrue);
        expect(repo.healthCalls, isNotEmpty);
      },
    );

    testWidgets('an unknown capability state still dispatches (unknown is '
        'never a denial)', (tester) async {
      await setupContainer(
        discoveryValue: Right([_config()]),
        capabilitiesFetch: () async =>
            Left(ProblemError(code: 'transport.connectionError')),
      );
      await pumpScreen(tester);

      expect(repo.healthCalls, isNotEmpty);
      expect(
        find.byKey(const Key('ai-config-provider-health-forbidden')),
        findsNothing,
      );
    });

    testWidgets('a failed health read offers a retry', (tester) async {
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = const Left(ProblemError(code: 'transport.down'));
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-config-provider-health-failed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ai-config-provider-health-retry')),
        findsOneWidget,
      );
    });

    testWidgets('a local provider stays usable without a stored key', (
      tester,
    ) async {
      // `ProbeCapability::LocalTags` (Ollama) needs no Vault binding at all, so
      // the server answers a MEASURED `usable` with `credential_configured:
      // false`. Letting the credential branch win would render "kein Schlüssel
      // hinterlegt" over a healthy account (review of #942 W5).
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(
          credentialConfigured: false,
          status: AccountProbeStatus.usable,
        ),
      );
      await pumpScreen(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-status')),
            )
            .data,
        l10nEn().aiConfigProviderHealthUsable,
      );
      expect(
        find.text(l10nEn().aiConfigProviderHealthUnconfigured),
        findsNothing,
      );
    });

    testWidgets('a measured unknown verdict offers no retry', (tester) async {
      // Retry is for a FAILED READ (docs/design/screens/ai-config.md): a read
      // that ANSWERED `unknown` is the server's verdict, not a transport problem
      // of this screen, so there is nothing new to fetch.
      await setupContainer(discoveryValue: Right([_config()]));
      repo.healthResult = Right(
        _healthView(status: AccountProbeStatus.unknown),
      );
      await pumpScreen(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-config-provider-health-status')),
            )
            .data,
        l10nEn().aiConfigProviderHealthUnknown,
      );
      expect(
        find.byKey(const Key('ai-config-provider-health-retry')),
        findsNothing,
      );
    });

    testWidgets('the decision card asks with the canonical wire key', (
      tester,
    ) async {
      // The stored config seeds the draft with the DART enum name
      // (`opencodeGo`); the health route takes the wire spelling
      // (`opencode-go`) and answers anything else with a `422` — which would
      // render a healthy provider as unreadable.
      await setupContainer(
        discoveryValue: Right([
          _config(decisionProvider: LlmProvider.opencodeGo),
        ]),
      );
      await pumpScreen(tester);

      expect(repo.healthCalls, contains('opencode-go'));
      expect(
        repo.healthCalls,
        isNot(contains('opencodeGo')),
        reason: 'the Dart enum name is not a wire key: ${repo.healthCalls}',
      );
      // One card per provider, not two for the same one under two spellings.
      expect(
        find.byKey(const Key('ai-config-provider-health')),
        findsNWidgets(2),
      );
    });

    testWidgets('a distinct decision provider gets its own card', (
      tester,
    ) async {
      await setupContainer(
        discoveryValue: Right([
          _config(decisionProvider: LlmProvider.neuralwatt),
        ]),
      );
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-config-provider-health')),
        findsNWidgets(2),
      );
      expect(repo.healthCalls, containsAll(<String>['openai', 'neuralwatt']));
    });
  });

  // --- aiConfigErrorCopy: the screen's whole error surface --------------------
  //
  // The 2026-11-21 report: a precise `422 ai-config.decision-model-unknown` was
  // rendered as "Die Konfigurationsänderung ist fehlgeschlagen (ai-config.…)"
  // because the copy switch had no arm for it. The user could not tell what to
  // change, retried the save six times, and each attempt left another orphaned
  // Vault credential behind. These tests walk the backend's whole `ai-config.*`
  // registry, so a missing arm fails HERE instead of in a user's face.
  group('aiConfigErrorCopy covers every ai-config.* wire code', () {
    /// The codes `backend/crates/core/src/error_registry.rs` can put on a
    /// response (`grep 'code: "ai-config.'`). The client cannot read the Rust
    /// registry, so this list IS the contract: a new backend code needs an arm
    /// in `aiConfigErrorCopy` AND a line here.
    const serverCodes = <String>[
      'ai-config.already-revoked',
      'ai-config.decision-incomplete',
      'ai-config.decision-model-empty',
      'ai-config.decision-model-unknown',
      'ai-config.decision-provider-unsupported',
      'ai-config.decision-vault-key-empty',
      'ai-config.empty-model',
      'ai-config.empty-prompt',
      'ai-config.empty-provider',
      'ai-config.empty-vault-key',
      'ai-config.forbidden',
      'ai-config.not-found',
      'ai-config.provider-mismatch',
      'ai-config.reasoning-effort-unsupported',
      'ai-config.vault-key-forbidden',
      'ai-config.version-mismatch',
    ];

    // Both delivery locales: a copy arm that exists only in English still
    // renders the generic German text on the user's phone.
    for (final locale in <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsDe(),
    ]) {
      test('${locale.localeName}: no code falls back to the generic text', () {
        for (final code in serverCodes) {
          expect(
            aiConfigErrorCopy(locale, ProblemError(code: code)),
            isNot(locale.aiConfigErrorGeneric(code)),
            reason:
                '$code has no arm in aiConfigErrorCopy — it renders as '
                '"${locale.aiConfigErrorGeneric(code)}", which names no fix',
          );
        }
      });

      test(
        '${locale.localeName}: every explanation is prose, not the code',
        () {
          for (final code in serverCodes) {
            expect(
              aiConfigErrorCopy(locale, ProblemError(code: code)),
              isNot(contains(code)),
              reason: '$code must be explained, not echoed',
            );
          }
        },
      );
    }

    test('the decision-model rejection names the fix — the exact 422 a stale '
        'decision pick produces', () {
      final l10n = AppLocalizationsEn();
      expect(
        aiConfigErrorCopy(
          l10n,
          const ProblemError(
            code: 'ai-config.decision-model-unknown',
            status: 422,
          ),
        ),
        l10n.aiConfigErrorDecisionModelUnknown,
      );
      // The sentence has to carry the action, not just the failure.
      expect(
        l10n.aiConfigErrorDecisionModelUnknown,
        contains('decision model'),
      );
      expect(
        AppLocalizationsDe().aiConfigErrorDecisionModelUnknown,
        contains('Decision-Modell'),
      );
    });

    test('a code the server adds LATER still renders something — the fallback '
        'stays a safety net, never the plan', () {
      final l10n = AppLocalizationsEn();
      expect(
        aiConfigErrorCopy(
          l10n,
          const ProblemError(code: 'ai-config.brand-new'),
        ),
        l10n.aiConfigErrorGeneric('ai-config.brand-new'),
      );
    });
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

    // Issue #809: the unreachable state inside the screen (the Settings
    // entry's third state is backed by the same copy). A golden pins the
    // card, its Retry and the absence of the first-run form.
    testWidgets('backend-unreachable golden light android', (tester) async {
      await setupContainer(
        discoveryValue: const Left(
          ProblemError(code: 'transport.connectionError'),
        ),
      );
      await pumpGolden(
        tester,
        golden: 'ai_config_backend_unreachable_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('backend-unreachable golden dark android', (tester) async {
      await setupContainer(
        discoveryValue: const Left(
          ProblemError(code: 'transport.connectionError'),
        ),
      );
      await pumpGolden(
        tester,
        golden: 'ai_config_backend_unreachable_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
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
