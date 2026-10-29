// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/auth_providers.dart';
import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_config_repository.dart';
import '../../../data/ai_import_handoff_store.dart';
import '../../../data/ai_import_providers.dart';
import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import 'ai_config_state.dart';
import 'decision_round_trip.dart';

part 'ai_config_controller.g.dart';

/// List-first config discovery (D2): `GET /v1/ai-import/config` (the
/// caller's configs, newest-first) is authoritative. Tests override this
/// seam.
@riverpod
Future<Result<List<AiConfigView>>> aiConfigDiscovery(Ref ref) =>
    ref.watch(aiConfigRepositoryProvider).listConfigs();

/// The remembered hand-off state for the authenticated subject (task 1.3).
@riverpod
Future<AiImportHandoffState> aiImportHandoff(Ref ref) async {
  final session = await ref.watch(authSessionControllerProvider.future);
  final sub = session?.sub ?? '';
  final res = await ref.watch(aiImportHandoffStoreProvider).read(sub);
  return res.getRight().toNullable() ?? AiImportHandoffState.empty;
}

/// Provider/model discovery (D7): the curated catalog from the routes —
/// no hardcoded ids. Every [AiProviderInfo] carries the backend-decided
/// `decisionCapable` capability (issue #736), so the Decision provider
/// picker reads the decision-capable set from THIS route rather than
/// mirroring it as a client-side allowlist. A 404 (AI import disabled) or
/// a transport failure degrades honestly in the screen.
@riverpod
Future<Result<List<AiProviderInfo>>> aiProviders(Ref ref) =>
    ref.watch(aiConfigRepositoryProvider).listProviders();

/// The selected provider's model set. A 422 (unknown provider) surfaces
/// as `Err` — the "provider unavailable" degradation.
@riverpod
Future<Result<List<ModelInfo>>> aiProviderModels(Ref ref, String key) =>
    ref.watch(aiConfigRepositoryProvider).listModels(key);

/// The selected DECISION provider's curated model set (issue #731):
/// `GET /v1/ai-import/providers/{key}/decision-models` — a distinct route
/// and catalog from [aiProviderModels] (the provider's decision ids such as
/// `clef-flash`/`clef`, never its extraction list). Same 422 → "provider
/// unavailable" degradation as the assistant picker.
@riverpod
Future<Result<List<ModelInfo>>> aiDecisionProviderModels(Ref ref, String key) =>
    ref.watch(aiConfigRepositoryProvider).listDecisionModels(key);

/// The selected provider's curated IMAGE-generation model set (issue #732):
/// `GET /v1/ai-import/providers/{key}/image-models` — a distinct route and
/// catalog from [aiProviderModels] (e.g. `gemini-*-image`/`gpt-image-*`,
/// empty for text-only providers). Same 422 → "provider unavailable"
/// degradation as the assistant picker.
@riverpod
Future<Result<List<ModelInfo>>> aiImageProviderModels(Ref ref, String key) =>
    ref.watch(aiConfigRepositoryProvider).listImageModels(key);

/// `GET /v1/ai-import/defaults` (issue #471): the deployment's single-source
/// prompt defaults (script/schedule). Feeds the first-run prompt prefill; a
/// failure degrades to empty editable fields — never a blocking error state.
@riverpod
Future<Result<AiImportDefaults>> aiImportDefaults(Ref ref) =>
    ref.watch(aiConfigRepositoryProvider).fetchDefaults();

/// The ephemeral form-draft data (immutable snapshot). Kept in its own
/// [Notifier] so it survives controller rebuilds (the reference pattern:
/// `SeasonOverlays`); the masked key is deliberately NOT here — the
/// secret is a submit-time parameter only (D6).
class AiConfigDraftData {
  AiConfigDraftData({
    this.selectedProviderKey,
    this.selectedAssistantModelId,
    this.selectedImageModelId,
    this.assistantModelTouched = false,
    this.imageModelTouched = false,
    this.selectedDecisionProviderKey,
    this.selectedDecisionModelId,
    this.decisionProviderTouched = false,
    this.decisionModelTouched = false,
    this.useSameDecisionKey = true,
    this.useSameDecisionKeyTouched = false,
    this.costDisplayPreference,
    this.scriptPrompt = '',
    this.schedulePrompt = '',
    this.scriptPromptTouched = false,
    this.schedulePromptTouched = false,
    this.unresolved,
  });

  String? selectedProviderKey;
  String? selectedAssistantModelId;
  String? selectedImageModelId;

  /// The drafted optional Decision / Scoring Model configuration
  /// (issue #723). [selectedDecisionProviderKey] is `null` = disabled.
  String? selectedDecisionProviderKey;
  String? selectedDecisionModelId;

  /// True once the user picked (or disabled) the decision provider, so the
  /// configured view's value is not restored after an explicit change.
  bool decisionProviderTouched;

  /// True once the user picked the decision model, so the configured
  /// view's value is not restored after an explicit change.
  bool decisionModelTouched;

  /// The drafted "Use same API key as extraction" toggle (issue #723).
  bool useSameDecisionKey;

  /// True once the user flipped the toggle. Until then the value is
  /// DERIVED from the stored config on every build (CodeRabbit review):
  /// a stored split-billing binding (decision key ≠ extraction key) must
  /// not silently rebind to the extraction key just because the draft
  /// default is `true` — an unrelated prompt edit would move billing.
  bool useSameDecisionKeyTouched;

  /// True once the user picked a provider, so the old assistant model is
  /// not restored from the configured view after a provider change.
  bool assistantModelTouched;

  /// True once the user picked (or cleared) the image model, so an
  /// explicit `null` is honoured instead of falling back to the config —
  /// without it the optional image model could never be cleared.
  bool imageModelTouched;
  String scriptPrompt;
  String schedulePrompt;

  /// Per-field touched flags (CodeRabbit review, PR #489): once the user
  /// edits a prompt field, THAT field's draft text is authoritative and the
  /// first-run defaults prefill (issue #471) must NOT fall through for it —
  /// so clearing a field stays a real "remove prompt" intent instead of
  /// silently resurrecting the default. The OTHER field keeps its prefill
  /// until the user touches it too (editing the script prompt must not
  /// wipe the prefilled schedule prompt).
  bool scriptPromptTouched;
  bool schedulePromptTouched;

  /// The drafted preferred primary cost display metric (issue #675).
  /// `null` = untouched — the configured view's value (or the `token`
  /// default) applies.
  CostDisplayPreference? costDisplayPreference;
  AiConfigUnresolved? unresolved;
}

/// Ephemeral draft store: mutations go through [mutate] so watchers (the
/// controller's build) rebuild on every draft change.
class AiConfigDrafts extends Notifier<AiConfigDraftData> {
  @override
  AiConfigDraftData build() => AiConfigDraftData();

  /// Applies [fn] to a shallow copy and publishes it.
  void mutate(void Function(AiConfigDraftData d) fn) {
    final next = AiConfigDraftData(
      selectedProviderKey: state.selectedProviderKey,
      selectedAssistantModelId: state.selectedAssistantModelId,
      selectedImageModelId: state.selectedImageModelId,
      assistantModelTouched: state.assistantModelTouched,
      imageModelTouched: state.imageModelTouched,
      selectedDecisionProviderKey: state.selectedDecisionProviderKey,
      selectedDecisionModelId: state.selectedDecisionModelId,
      decisionProviderTouched: state.decisionProviderTouched,
      decisionModelTouched: state.decisionModelTouched,
      useSameDecisionKey: state.useSameDecisionKey,
      useSameDecisionKeyTouched: state.useSameDecisionKeyTouched,
      costDisplayPreference: state.costDisplayPreference,
      scriptPrompt: state.scriptPrompt,
      schedulePrompt: state.schedulePrompt,
      scriptPromptTouched: state.scriptPromptTouched,
      schedulePromptTouched: state.schedulePromptTouched,
      unresolved: state.unresolved,
    );
    fn(next);
    state = next;
  }
}

final aiConfigDraftsProvider =
    NotifierProvider<AiConfigDrafts, AiConfigDraftData>(AiConfigDrafts.new);

/// The bounded read-back's verdict (issue #769): [error] is `null` exactly
/// when the stored view confirmed the submitted Decision Model triple;
/// [stored] is the last view the server DID serve, so a caller reporting a
/// mismatch can replace its stale cached configuration with the authoritative
/// one instead of re-sending the pre-dispatch version (a guaranteed 409).
typedef DecisionRoundTripVerdict = ({
  ProblemError? error,
  AiConfigView? stored,
});

/// The AI-import configuration controller (`flutter-ai-config` task 2.1).
///
/// AUTHZ-GATE exception (D4, documented): the backend gates AI config and
/// credential endpoints on a credential-role policy that is NOT exposed as
/// a season capability, so no client-side capability pre-gate can mirror
/// it. The only client-side gate here is the authenticated session
/// (session-only); a 403 renders the localized "administrator role
/// required" narrative — the call itself is denied server-side.
@Riverpod(keepAlive: false)
class AiConfigController extends _$AiConfigController {
  AiConfigDrafts get _draftsNotifier =>
      ref.read(aiConfigDraftsProvider.notifier);

  @override
  AiConfigScreenState build() {
    final discovery = ref.watch(aiConfigDiscoveryProvider);
    final providers = ref.watch(aiProvidersProvider);
    final promptDefaults = ref.watch(aiImportDefaultsProvider);
    final drafts = ref.watch(aiConfigDraftsProvider);

    // List-first with remembered-id fallback (D2): the discovery list is
    // authoritative; an empty list (or one of only revoked configs) is the
    // first-run state. The remembered id only fast-paths a get-by-id when
    // the list route itself failed (fire-and-forget below — build() stays
    // sync; the read lands via copyWith).
    AiConfigView? config;
    ProblemError? discoveryError;
    switch (discovery) {
      case AsyncData(:final value):
        value.match((err) => discoveryError = err, (configs) {
          final active = configs.where((c) => !c.revoked).toList();
          config = active.isEmpty ? null : active.first;
        });
      case AsyncError(:final error):
        discoveryError = error is ProblemError
            ? error
            : ProblemError(code: 'unknown', detail: '$error');
      case _:
        discoveryError = null;
    }
    if (config == null && discoveryError != null) {
      unawaited(_loadRememberedConfigFallback());
    }

    // "Resolved first-run" — only a discovery that has GENUINELY resolved to
    // "no active config" may feed the prefill/preselect (issue #471).
    // Loading is NOT first-run (an active config may still appear), and a
    // failed discovery is never the first-run state either (its save button
    // would create a second credential).
    final firstRunResolved =
        discovery is AsyncData && config == null && discoveryError == null;

    // First-run provider suggestion: the first curated provider in display
    // order (backend `AiProviderInfo` list order — issue #471). Strictly a
    // fallback: an explicit draft pick wins, a config beats both.
    final suggestedProviderKey = firstRunResolved
        ? switch (providers) {
            AsyncData(:final value) => value.match(
              (_) => null,
              (rows) => rows.isEmpty ? null : rows.first.key,
            ),
            _ => null,
          }
        : null;

    final selectedProviderKey =
        drafts.selectedProviderKey ??
        suggestedProviderKey ??
        config?.provider.name;

    final models = switch (selectedProviderKey == null
        ? const AsyncValue<Result<List<ModelInfo>>>.loading()
        : ref.watch(aiProviderModelsProvider(selectedProviderKey))) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<List<ModelInfo>>.error(err, StackTrace.current),
        (models) => AsyncValue<List<ModelInfo>>.data(models),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<ModelInfo>>.error(error, stackTrace),
      _ => const AsyncValue<List<ModelInfo>>.loading(),
    };

    // The DECISION provider's model catalog (issue #723): the dedicated
    // decision-models route (issue #731) — NOT the extraction catalog.
    // Only fetched once a decision provider is picked; the picker renders
    // the honest loading/degraded states otherwise.
    final decisionProviderKeyDraft = drafts.decisionProviderTouched
        ? drafts.selectedDecisionProviderKey
        : (drafts.selectedDecisionProviderKey ??
              config?.decisionProvider?.name);
    final decisionModels = switch (decisionProviderKeyDraft == null
        ? const AsyncValue<Result<List<ModelInfo>>>.loading()
        : ref.watch(
            aiDecisionProviderModelsProvider(decisionProviderKeyDraft),
          )) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<List<ModelInfo>>.error(err, StackTrace.current),
        (models) => AsyncValue<List<ModelInfo>>.data(models),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<ModelInfo>>.error(error, stackTrace),
      _ => const AsyncValue<List<ModelInfo>>.loading(),
    };

    // The selected provider's IMAGE-generation catalog (issue #732): the
    // dedicated image-models route — NOT the extraction catalog. Empty for
    // text-only providers (the picker collapses to "— none —").
    final imageModels = switch (selectedProviderKey == null
        ? const AsyncValue<Result<List<ModelInfo>>>.loading()
        : ref.watch(aiImageProviderModelsProvider(selectedProviderKey))) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<List<ModelInfo>>.error(err, StackTrace.current),
        (models) => AsyncValue<List<ModelInfo>>.data(models),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<ModelInfo>>.error(error, stackTrace),
      _ => const AsyncValue<List<ModelInfo>>.loading(),
    };

    // First-run decision-model suggestion (issue #723): the selected
    // decision provider's `recommended` model (e.g. `clef-flash`), falling
    // back to the first model. Strictly a fallback behind an explicit
    // draft pick and the configured model.
    String? suggestedDecisionModelId;
    if (decisionProviderKeyDraft != null) {
      if (decisionModels case AsyncData(:final value)) {
        if (value.isNotEmpty) {
          suggestedDecisionModelId = value
              .firstWhere(
                (m) => m.recommended ?? false,
                orElse: () => value.first,
              )
              .id;
        }
      }
    }

    // First-run assistant-model suggestion: the selected provider's
    // `recommended` model, falling back to the first model for backends that
    // predate the flag. Strictly a fallback behind an explicit draft pick
    // and the configured model. Read reactively: it appears once the
    // selected provider's model set resolves.
    String? suggestedAssistantModelId;
    if (firstRunResolved && selectedProviderKey != null) {
      if (models case AsyncData(:final value)) {
        if (value.isNotEmpty) {
          suggestedAssistantModelId = value
              .firstWhere(
                (m) => m.recommended ?? false,
                orElse: () => value.first,
              )
              .id;
        }
      }
    }

    final providersState = switch (providers) {
      AsyncData(:final value) => value.match(
        (err) =>
            AsyncValue<List<AiProviderInfo>>.error(err, StackTrace.current),
        (rows) => AsyncValue<List<AiProviderInfo>>.data(rows),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<AiProviderInfo>>.error(error, stackTrace),
      _ => const AsyncValue<List<AiProviderInfo>>.loading(),
    };

    final promptDefaultsState = switch (promptDefaults) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<AiImportDefaults>.error(err, StackTrace.current),
        (defaults) => AsyncValue<AiImportDefaults>.data(defaults),
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<AiImportDefaults>.error(error, stackTrace),
      _ => const AsyncValue<AiImportDefaults>.loading(),
    };

    // Prompt defaults from `GET /v1/ai-import/defaults` are the fallback
    // for both first-run and configured forms (issue #520). A failed fetch
    // degrades to empty fields, never a blocking state. Non-empty stored
    // prompts still win; an empty stored prompt falls through to the
    // deployment default. The field remains editable and its touched flag
    // makes the user's exact text (including a deliberate clear) authoritative.
    final scriptDefault = switch (promptDefaults) {
      AsyncData(:final value) => value.match((_) => null, (dto) => dto.script),
      _ => null,
    };
    final scheduleDefault = switch (promptDefaults) {
      AsyncData(:final value) => value.match(
        (_) => null,
        (dto) => dto.schedule,
      ),
      _ => null,
    };

    String promptSeed(String kind, String? defaultValue) {
      final stored = config?.prompts[kind];
      return stored != null && stored.isNotEmpty
          ? stored
          : (defaultValue ?? '');
    }

    return AiConfigScreenState(
      config: config,
      discoveryError: discoveryError,
      providers: providersState,
      models: models,
      promptDefaults: promptDefaultsState,
      selectedProviderKey: selectedProviderKey,
      selectedAssistantModelId: drafts.assistantModelTouched
          ? drafts.selectedAssistantModelId
          : (drafts.selectedAssistantModelId ??
                suggestedAssistantModelId ??
                config?.assistantModel),
      selectedImageModelId: drafts.imageModelTouched
          ? drafts.selectedImageModelId
          : (config?.imageModel ?? drafts.selectedImageModelId),
      // Decision Model seeds (issue #723): an explicit draft pick (or an
      // explicit disable) wins, then the configured view, then the honest
      // "disabled" default. The model follows the same touched discipline
      // as the assistant model.
      selectedDecisionProviderKey: decisionProviderKeyDraft,
      selectedDecisionModelId: drafts.decisionModelTouched
          ? drafts.selectedDecisionModelId
          : (drafts.selectedDecisionModelId ??
                config?.decisionModel ??
                suggestedDecisionModelId),
      // The same-key toggle is derived from the STORED binding until the
      // user touches it (CodeRabbit review): same-key is true exactly when
      // there is no stored decision key, or the stored decision key IS the
      // stored extraction key. A stored split-billing binding keeps the
      // toggle off — an unrelated edit must never rebind the decision key
      // to the extraction credential.
      useSameDecisionKey: drafts.useSameDecisionKeyTouched
          ? drafts.useSameDecisionKey
          : _storedDecisionUsesSameKey(config),
      decisionModels: decisionModels,
      imageModels: imageModels,
      // Preferred primary cost display (issue #675): an explicit draft pick
      // wins, then the configured value, then the `token` default.
      costDisplayPreference:
          drafts.costDisplayPreference ??
          config?.costDisplayPreference ??
          CostDisplayPreference.token,
      scriptPrompt: drafts.scriptPromptTouched
          ? drafts.scriptPrompt
          : promptSeed('script', scriptDefault),
      schedulePrompt: drafts.schedulePromptTouched
          ? drafts.schedulePrompt
          : promptSeed('schedule', scheduleDefault),
      unresolved: drafts.unresolved,
    );
  }

  /// Selects a provider and loads its model set.
  void selectProvider(String key) {
    _draftsNotifier.mutate((d) {
      d.selectedProviderKey = key;
      d.selectedAssistantModelId = null;
      d.assistantModelTouched = true;
      d.selectedImageModelId = null;
      // The old provider's image model is invalid for the new catalog. Mark
      // the clear as intentional so build() does not restore it from config.
      d.imageModelTouched = true;
    });
    state = state.copyWith(clearCommandError: true);
  }

  void selectAssistantModel(String id) {
    _draftsNotifier.mutate((d) {
      d.selectedAssistantModelId = id;
      d.assistantModelTouched = true;
    });
    state = state.copyWith(clearCommandError: true);
  }

  void selectImageModel(String? id) {
    _draftsNotifier.mutate((d) {
      d.selectedImageModelId = id;
      // An explicit pick (or "— none —") is a REAL user intent: without
      // the touched flag a `null` would fall back to the configured
      // model and the image model could never be cleared (review #8).
      d.imageModelTouched = true;
    });
  }

  /// Selects the Decision Model provider (issue #723); `null` = disabled
  /// ("None / deaktiviert") — an explicit user intent, hence touched.
  void selectDecisionProvider(String? key) {
    _draftsNotifier.mutate((d) {
      d.selectedDecisionProviderKey = key;
      d.decisionProviderTouched = true;
      // The old provider's decision model is invalid for the new catalog.
      d.selectedDecisionModelId = null;
      d.decisionModelTouched = true;
    });
    state = state.copyWith(clearCommandError: true);
  }

  void selectDecisionModel(String? id) {
    _draftsNotifier.mutate((d) {
      d.selectedDecisionModelId = id;
      d.decisionModelTouched = true;
    });
    state = state.copyWith(clearCommandError: true);
  }

  /// The "Use same API key as extraction" toggle (issue #723). Marks the
  /// toggle touched so the derived-from-config value stops applying
  /// (CodeRabbit review: the user's flip wins over the stored binding).
  void setUseSameDecisionKey(bool value) {
    _draftsNotifier.mutate((d) {
      d.useSameDecisionKey = value;
      d.useSameDecisionKeyTouched = true;
    });
    state = state.copyWith(clearCommandError: true);
  }

  /// Selects the preferred primary cost display metric (issue #675).
  void selectCostDisplayPreference(CostDisplayPreference preference) {
    _draftsNotifier.mutate((d) => d.costDisplayPreference = preference);
    state = state.copyWith(clearCommandError: true);
  }

  void setScriptPrompt(String value) {
    _draftsNotifier.mutate((d) {
      d.scriptPrompt = value;
      d.scriptPromptTouched = true;
    });
  }

  void setSchedulePrompt(String value) {
    _draftsNotifier.mutate((d) {
      d.schedulePrompt = value;
      d.schedulePromptTouched = true;
    });
  }

  void dismissCommandError() => state = state.copyWith(clearCommandError: true);

  /// Resolves the authenticated session for the session-only gate; a
  /// restore failure is treated as no-session (deny) — the request would
  /// be refused server-side anyway.
  Future<bool> _hasSession() async {
    try {
      final session = await ref.read(authSessionControllerProvider.future);
      return (session?.sub ?? '').isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Resolves the selected provider's [LlmProvider] from the fetched
  /// catalog (never hardcoded — D7).
  LlmProvider? _resolveProvider(String? key) {
    if (key == null) return null;
    final providers = state.providers.value ?? const <AiProviderInfo>[];
    for (final info in providers) {
      if (info.key == key) return info.provider;
    }
    return null;
  }

  /// The full create flow (design §2.1 steps 1–7, task 2.1):
  ///
  /// 1. submit the masked key (`POST /v1/settings/credentials`);
  /// 2. resolve the opaque `vault_key_id` (`GET /v1/settings/{id}`);
  /// 3. `POST /v1/ai-import/config` with that id;
  /// 4. on create failure → bounded rollback of the credential (step 6);
  /// 5. on ambiguous timeout → reconcile BEFORE any cleanup (step 7):
  ///    committed → continue; not committed → rollback; unresolved →
  ///    the "configuration state unknown" state (the credential is never
  ///    destroyed while it may be referenced).
  ///
  /// The [secret] is a submit-time parameter only — it lives in this call
  /// frame and the serialized request payload, never in provider state,
  /// secure storage, cache, or logs (D6).
  Future<Result<IdVersionResponse>> create({
    required String secret,
    String? decisionSecret,
  }) async {
    final s = state;
    final providerKey = s.selectedProviderKey;
    final assistantModelId = s.selectedAssistantModelId;
    final provider = _resolveProvider(providerKey);
    if (providerKey == null || assistantModelId == null || provider == null) {
      const error = ProblemError(code: 'ai_config.incomplete_selection');
      state = state.copyWith(commandError: error);
      return const Left(error);
    }
    if (!await _hasSession()) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required',
        status: 403,
      );
      state = state.copyWith(commandError: error);
      return const Left(error);
    }

    final repo = ref.read(aiConfigRepositoryProvider);
    final scheduler = ref.read(reconciliationSchedulerProvider);

    // Steps 1–2: the credential hand-off. A failure AFTER the successful
    // submission carries the created aggregate identity — the caller
    // (here) decides to roll back rather than leave an unreachable vault
    // credential (design §2.1 step 6).
    final outcome = await submitCredentialWithHandoff(
      repo,
      provider: providerKey,
      secret: secret,
    );
    final CredentialHandoff credential;
    switch (outcome) {
      case HandoffSucceeded(:final handoff):
        credential = handoff;
      case HandoffFailed(:final error, :final created):
        if (created != null) {
          unawaited(
            _rollbackCredentialById(created.id, created.version, scheduler),
          );
        }
        if (ref.mounted) state = state.copyWith(commandError: error);
        return Left(error);
    }

    // Decision Model credential resolution (issue #723): the optional
    // scoring slot shares the extraction credential when the providers
    // match and the same-key toggle is on; otherwise it reuses a
    // remembered decision credential or binds a NEW one (split billing).
    // A decision hand-off failure rolls back BOTH just-created
    // credentials — the config was never created, so neither key may
    // stay orphaned in the vault.
    final decisionProviderKey = s.selectedDecisionProviderKey;
    final decisionModelId = s.selectedDecisionModelId;
    LlmProvider? decisionProvider;
    String? decisionVaultKeyId;
    CredentialHandoff? createdDecisionCredential;
    if (decisionProviderKey != null) {
      decisionProvider = _resolveProvider(decisionProviderKey);
      if (decisionProvider == null || decisionModelId == null) {
        // The extraction credential is ALREADY submitted — the config was
        // never created, so roll it back instead of leaving it orphaned in
        // the vault (CodeRabbit review).
        const error = ProblemError(code: 'ai_config.incomplete_selection');
        unawaited(_rollbackCredential(credential, scheduler));
        state = state.copyWith(commandError: error);
        return const Left(error);
      }
      if (decisionProviderKey == providerKey && s.useSameDecisionKey) {
        // Same provider + same-key toggle: the extraction credential IS
        // the decision credential (the backend permits the shared key
        // exactly within the same provider).
        decisionVaultKeyId = credential.vaultKeyId;
      } else {
        final handoffState = await ref.read(aiImportHandoffProvider.future);
        final remembered = handoffState.decisionCredentialFor(
          decisionProviderKey,
        );
        if (remembered != null) {
          decisionVaultKeyId = remembered.vaultKeyId;
        } else {
          if (decisionSecret == null || decisionSecret.isEmpty) {
            // Same orphan risk: the extraction credential exists, the
            // config does not — roll it back (CodeRabbit review).
            const error = ProblemError(code: 'ai_config.decision_key_missing');
            unawaited(_rollbackCredential(credential, scheduler));
            state = state.copyWith(commandError: error);
            return const Left(error);
          }
          final outcome = await submitCredentialWithHandoff(
            repo,
            provider: decisionProviderKey,
            secret: decisionSecret,
          );
          switch (outcome) {
            case HandoffSucceeded(:final handoff):
              createdDecisionCredential = handoff;
              decisionVaultKeyId = handoff.vaultKeyId;
            case HandoffFailed(:final error, :final created):
              unawaited(_rollbackCredential(credential, scheduler));
              if (created != null) {
                unawaited(
                  _rollbackCredentialById(
                    created.id,
                    created.version,
                    scheduler,
                  ),
                );
              }
              if (ref.mounted) state = state.copyWith(commandError: error);
              return Left(error);
          }
        }
      }
    }

    // Step 3: the config create carrying ONLY the opaque vault key id.
    final created = await repo.createConfig(
      CreateAiConfigRequest(
        (b) => b
          ..provider = provider
          ..assistantModel = assistantModelId
          ..vaultKeyId = credential.vaultKeyId
          ..imageModel = s.selectedImageModelId
          ..costDisplayPreference = s.costDisplayPreference
          ..decisionProvider = decisionProvider
          ..decisionModel = decisionModelId
          ..decisionVaultKeyId = decisionVaultKeyId
          ..prompts.replace({
            if (s.scriptPrompt.isNotEmpty) 'script': s.scriptPrompt,
            if (s.schedulePrompt.isNotEmpty) 'schedule': s.schedulePrompt,
          }),
      ),
    );

    return created.match(
      (error) {
        // Step 5 failure handling.
        if (isAmbiguousTimeoutError(error)) {
          // Step 7: reconcile BEFORE any credential cleanup.
          unawaited(
            _reconcileFreshCreate(
              credential,
              s,
              decisionProviderKey: decisionProviderKey,
              decisionCredential: createdDecisionCredential,
            ),
          );
          return Left<ProblemError, IdVersionResponse>(error);
        }
        // Step 6: bounded rollback of the just-created credentialS — the
        // config was never committed, so neither key may stay orphaned.
        unawaited(_rollbackCredential(credential, scheduler));
        if (createdDecisionCredential != null) {
          unawaited(
            _rollbackCredentialById(
              createdDecisionCredential.settingsId,
              createdDecisionCredential.settingsVersion,
              scheduler,
            ),
          );
        }
        if (ref.mounted) state = state.copyWith(commandError: error);
        return Left<ProblemError, IdVersionResponse>(error);
      },
      (idVersion) async {
        // Success: remember the config id (fast-path for the next launch;
        // the list route stays authoritative, D2) and refresh discovery.
        await _rememberConfigId(idVersion.id);
        await _rememberCredential(
          providerKey,
          ProviderCredentialReference(
            settingsId: credential.settingsId,
            settingsVersion: credential.settingsVersion,
            vaultKeyId: credential.vaultKeyId,
          ),
        );
        // The separately-bound decision credential (issue #723) is
        // remembered under its decision-scoped slot — switching back to
        // split billing never requires re-entry.
        if (createdDecisionCredential != null && decisionProviderKey != null) {
          await _rememberCredential(
            decisionCredentialKey(decisionProviderKey),
            ProviderCredentialReference(
              settingsId: createdDecisionCredential.settingsId,
              settingsVersion: createdDecisionCredential.settingsVersion,
              vaultKeyId: createdDecisionCredential.vaultKeyId,
            ),
          );
        }
        // Round-trip verification (issue #769): the created config exists
        // either way, so its id is remembered — hiding it would invite a
        // second create on retry. What must NOT happen is reporting the
        // submitted Decision Model as stored when the read-back disagrees: the
        // error surfaces and the draft is preserved.
        final verdict = await _verifyDecisionRoundTrip(
          idVersion.id,
          DecisionTriple(
            providerKey: decisionProvider?.name,
            modelId: decisionProviderKey == null ? null : decisionModelId,
            vaultKeyId: decisionVaultKeyId,
          ),
        );
        if (verdict.error != null) {
          // The authoritative view becomes the rendered configuration — the
          // created config is real even when its Decision Model did not land.
          // Deliberately NOT invalidating discovery here: this controller
          // watches it, so the invalidate would rebuild (and drop) the very
          // error that must stay visible — the silent "looks saved" class of
          // failure this issue closes. Discovery re-resolves when the screen
          // is reopened (autoDispose).
          if (ref.mounted) {
            state = state.copyWith(
              config: verdict.stored,
              commandError: verdict.error,
            );
          }
          // Safe to refresh without losing the verdict: neither provider is
          // watched by this controller (only the discovery provider above is,
          // which is why that one is left alone). The created config does
          // exist, so AI naming must see it.
          ref.invalidate(configuredAiNamingProvider);
          ref.invalidate(aiImportHandoffProvider);
          return Left<ProblemError, IdVersionResponse>(verdict.error!);
        }
        if (!ref.mounted) {
          return Right<ProblemError, IdVersionResponse>(idVersion);
        }
        ref.invalidate(aiConfigDiscoveryProvider);
        ref.invalidate(configuredAiNamingProvider);
        ref.invalidate(aiImportHandoffProvider);
        state = state.copyWith(clearCommandError: true);
        return Right<ProblemError, IdVersionResponse>(idVersion);
      },
    );
  }

  Future<void> _rememberConfigId(String configId) async {
    final session = await ref.read(authSessionControllerProvider.future);
    final sub = session?.sub ?? '';
    final res = await ref
        .read(aiImportHandoffStoreProvider)
        .saveConfigId(sub, configId);
    // A hand-off write failure must not fail the create (the list route is
    // authoritative); it surfaces only if the fallback path is ever hit.
    res.getLeft().toNullable();
  }

  /// Verifies that the Decision Model triple this dispatch submitted actually
  /// reached the read model (issue #769). [DecisionRoundTripVerdict.error] is
  /// `null` only when the authoritative view confirms the submission.
  ///
  /// A successful `POST`/`PATCH` acknowledgement is not evidence of
  /// persistence — that assumption is exactly what let the reported
  /// configuration vanish unnoticed, with the UI claiming a state the backend
  /// did not have. A read-back that cannot be READ is reported as its own
  /// error rather than as success, for the same reason: "unconfirmed" must
  /// never be rendered as "saved". The existing `transport.*` copy explains
  /// it, and the config version guard turns a redundant retry into an honest
  /// 409 instead of a silent overwrite.
  ///
  /// The read-back is BOUNDED-RETRY, not a single read: a committed write
  /// reaches the read model asynchronously (projector lag), so one lagging
  /// read would report a configuration that was in fact stored as
  /// `ai_config.decision_not_persisted` — the very false negative this
  /// verification exists to prevent. The first read runs immediately, later
  /// attempts back off through [ReconciliationScheduler], and the budget is
  /// [kMaxReconcileAttempts] (AGENTS.md §4: reconcile the eventual projection
  /// with a bounded-retry refetch). Only an exhausted budget is a verdict.
  ///
  /// [DecisionRoundTripVerdict.stored] is the last view the server DID serve:
  /// the dispatch committed even when the Decision Model did not land, so that
  /// view carries the post-dispatch aggregate version and lets the caller
  /// replace its stale cached config.
  ///
  /// [ProblemError.detail] here is a CLIENT-side diagnostic (never rendered —
  /// the screen localizes its copy from `code`, AGENTS.md §5).
  Future<DecisionRoundTripVerdict> _verifyDecisionRoundTrip(
    String configId,
    DecisionTriple submitted,
  ) async {
    final repo = ref.read(aiConfigRepositoryProvider);
    final scheduler = ref.read(reconciliationSchedulerProvider);
    ProblemError? lastError;
    AiConfigView? lastStored;
    for (var attempt = 0; attempt < kMaxReconcileAttempts; attempt++) {
      if (attempt > 0) await scheduler.tick(attempt);
      final res = await repo.getConfig(configId);
      final stored = res.getRight().toNullable();
      if (stored == null) {
        // A read that failed is not a verdict either — keep the transport
        // error as the fallback verdict and try again.
        lastError = res.getLeft().toNullable();
        continue;
      }
      lastStored = stored;
      final mismatch = verifyDecisionRoundTrip(
        configId: configId,
        submitted: submitted,
        stored: stored,
      );
      if (mismatch == null) return (error: null, stored: stored);
      lastError = ProblemError(
        code: decisionNotPersistedCode,
        detail: '$mismatch',
      );
    }
    return (error: lastError, stored: lastStored);
  }

  Future<void> _rememberCredential(
    String providerKey,
    ProviderCredentialReference credential,
  ) async {
    final session = await ref.read(authSessionControllerProvider.future);
    final sub = session?.sub ?? '';
    final res = await ref
        .read(aiImportHandoffStoreProvider)
        .rememberCredential(sub, providerKey, credential);
    // Credential retention is deliberately best effort: a storage failure must
    // not turn a committed config update into a failed command. The secret is
    // never stored here; only opaque references are.
    res.getLeft().toNullable();
    if (ref.mounted) ref.invalidate(aiImportHandoffProvider);
  }

  /// The bounded rollback against explicit aggregate identity (the
  /// hand-off-failure path carries `IdVersionResponse`, not a
  /// [CredentialHandoff]). Never silently dropped — on exhaustion the
  /// orphaned-credential error surfaces as the command error.
  Future<void> _rollbackCredentialById(
    String settingsId,
    int version,
    ReconciliationScheduler scheduler,
  ) async {
    final repo = ref.read(aiConfigRepositoryProvider);
    final res = await repo.rollbackCredential(
      settingsId,
      version,
      tick: (attempt) => scheduler.tick(attempt),
    );
    final err = res.getLeft().toNullable();
    if (err != null && ref.mounted) {
      state = state.copyWith(commandError: err);
    }
  }

  /// Step 6: the bounded rollback. Never silently dropped — on exhaustion
  /// the orphaned-credential error surfaces as the command error.
  Future<void> _rollbackCredential(
    CredentialHandoff credential,
    ReconciliationScheduler scheduler,
  ) => _rollbackCredentialById(
    credential.settingsId,
    credential.settingsVersion,
    scheduler,
  );

  /// Step 7 (fresh-create variant): reconcile by the credential's vault
  /// key id before any cleanup. [decisionCredential] (issue #723) is the
  /// optional separately-bound decision credential created in the same
  /// dispatch: committed → remembered under the decision-scoped slot;
  /// definitively not committed → rolled back with the extraction
  /// credential; unknown → kept (never destroyed while it may be
  /// referenced) and retained in the hand-off store for reuse.
  Future<void> _reconcileFreshCreate(
    CredentialHandoff credential,
    AiConfigScreenState snapshot, {
    String? decisionProviderKey,
    CredentialHandoff? decisionCredential,
  }) async {
    final repo = ref.read(aiConfigRepositoryProvider);
    final scheduler = ref.read(reconciliationSchedulerProvider);
    final outcome = await reconcileConfigByVaultKey(
      repo,
      vaultKeyId: credential.vaultKeyId,
      tick: (attempt) => scheduler.tick(attempt),
    );
    if (!ref.mounted) return;
    switch (outcome) {
      case ConfigCommitted(:final view):
        // Committed — keep the credential, continue to the config screen.
        await _rememberConfigId(view.id);
        final providerKey = snapshot.selectedProviderKey;
        if (providerKey != null) {
          await _rememberCredential(
            providerKey,
            ProviderCredentialReference(
              settingsId: credential.settingsId,
              settingsVersion: credential.settingsVersion,
              vaultKeyId: credential.vaultKeyId,
            ),
          );
        }
        if (decisionProviderKey != null && decisionCredential != null) {
          await _rememberCredential(
            decisionCredentialKey(decisionProviderKey),
            ProviderCredentialReference(
              settingsId: decisionCredential.settingsId,
              settingsVersion: decisionCredential.settingsVersion,
              vaultKeyId: decisionCredential.vaultKeyId,
            ),
          );
        }
        if (!ref.mounted) return;
        ref.invalidate(aiConfigDiscoveryProvider);
        ref.invalidate(configuredAiNamingProvider);
        ref.invalidate(aiImportHandoffProvider);
        state = state.copyWith(clearCommandError: true);
      case ConfigNotCommitted():
        // Definitively not committed — run the step-6 rollback.
        await _rollbackCredential(credential, scheduler);
        if (decisionCredential != null) {
          await _rollbackCredentialById(
            decisionCredential.settingsId,
            decisionCredential.settingsVersion,
            scheduler,
          );
        }
      case ConfigUnknown(:final error):
        // Unresolved — the "configuration state unknown — verify" state
        // with both actions offered; the credential is never destroyed
        // while it may be referenced by a committed config. The separate
        // decision credential (issue #723) is likewise KEPT and retained
        // in the hand-off store, so a re-check or re-entry never needs
        // the key again.
        if (decisionProviderKey != null && decisionCredential != null) {
          await _rememberCredential(
            decisionCredentialKey(decisionProviderKey),
            ProviderCredentialReference(
              settingsId: decisionCredential.settingsId,
              settingsVersion: decisionCredential.settingsVersion,
              vaultKeyId: decisionCredential.vaultKeyId,
            ),
          );
        }
        _draftsNotifier.mutate(
          (d) => d.unresolved = AiConfigUnresolved(
            settingsId: credential.settingsId,
            settingsVersion: credential.settingsVersion,
            vaultKeyId: credential.vaultKeyId,
            providerKey: snapshot.selectedProviderKey ?? '',
            assistantModelId: snapshot.selectedAssistantModelId ?? '',
            imageModelId: snapshot.selectedImageModelId,
            scriptPrompt: snapshot.scriptPrompt,
            schedulePrompt: snapshot.schedulePrompt,
            error: error,
          ),
        );
        ref.invalidateSelf();
    }
  }

  /// Re-checks the unresolved create (the "keep" action): re-runs the
  /// reconciliation; a commit resolves the state.
  Future<void> recheckUnresolved() async {
    final unresolved = state.unresolved;
    if (unresolved == null) return;
    _draftsNotifier.mutate((d) => d.unresolved = null);
    ref.invalidateSelf();
    await _reconcileFreshCreate(
      CredentialHandoff(
        settingsId: unresolved.settingsId,
        settingsVersion: unresolved.settingsVersion,
        vaultKeyId: unresolved.vaultKeyId,
      ),
      AiConfigScreenState(
        config: null,
        providers: const AsyncValue<List<AiProviderInfo>>.data([]),
        models: const AsyncValue<List<ModelInfo>>.data([]),
        selectedProviderKey: unresolved.providerKey,
        selectedAssistantModelId: unresolved.assistantModelId,
        selectedImageModelId: unresolved.imageModelId,
        scriptPrompt: unresolved.scriptPrompt,
        schedulePrompt: unresolved.schedulePrompt,
      ),
    );
  }

  /// The "clean up" action of the unresolved state: the user explicitly
  /// confirms the credential was NOT referenced — destroy it (bounded
  /// rollback, orphaned-credential surfacing).
  Future<void> cleanupUnresolved() async {
    final unresolved = state.unresolved;
    if (unresolved == null) return;
    _draftsNotifier.mutate((d) => d.unresolved = null);
    ref.invalidateSelf();
    await _rollbackCredential(
      CredentialHandoff(
        settingsId: unresolved.settingsId,
        settingsVersion: unresolved.settingsVersion,
        vaultKeyId: unresolved.vaultKeyId,
      ),
      ref.read(reconciliationSchedulerProvider),
    );
  }

  /// Edit path: PATCH carries the version echoed from the fetched
  /// `AiConfigView`; a 409 renders "changed elsewhere — refresh" with NO
  /// automatic version-bump re-dispatch (spec `flutter-ai-config`).
  Future<Result<int>> edit({
    required String? providerKey,
    required String? assistantModelId,
    required String? imageModelId,
    required CostDisplayPreference costDisplayPreference,
    required String scriptPrompt,
    required String schedulePrompt,
    String? replacementSecret,
    required String? decisionProviderKey,
    required String? decisionModelId,
    bool useSameDecisionKey = true,
    String? decisionReplacementSecret,
  }) async {
    final config = state.config;
    if (config == null) {
      return const Left(ProblemError(code: 'ai_config.not-found'));
    }
    final provider =
        _resolveProvider(providerKey) ??
        (providerKey == config.provider.name ? config.provider : null);
    if (provider == null || assistantModelId == null) {
      const error = ProblemError(code: 'ai_config.incomplete_selection');
      state = state.copyWith(commandError: error);
      return const Left(error);
    }
    final selectedProviderKey = providerKey!;

    // Provider replacement is a two-phase hand-off. Reuse a retained
    // provider credential when available; otherwise create one and keep it
    // even if the subsequent PATCH fails so retrying never requires re-entry.
    var vaultKeyId = config.vaultKeyId;
    CredentialHandoff? createdCredential;
    if (selectedProviderKey != config.provider.name) {
      final handoff = await ref.read(aiImportHandoffProvider.future);
      final retained = handoff.credentials[selectedProviderKey];
      if (retained != null) {
        vaultKeyId = retained.vaultKeyId;
      } else {
        if (replacementSecret == null || replacementSecret.isEmpty) {
          const error = ProblemError(code: 'ai_config.key_missing');
          state = state.copyWith(commandError: error);
          return const Left(error);
        }
        final outcome = await submitCredentialWithHandoff(
          ref.read(aiConfigRepositoryProvider),
          provider: selectedProviderKey,
          secret: replacementSecret,
        );
        switch (outcome) {
          case HandoffSucceeded(:final handoff):
            createdCredential = handoff;
            vaultKeyId = handoff.vaultKeyId;
          case HandoffFailed(:final error):
            if (ref.mounted) state = state.copyWith(commandError: error);
            return Left(error);
        }
      }
    }

    final repo = ref.read(aiConfigRepositoryProvider);

    // A replacement extraction credential created above must be RETAINED
    // even when a later Decision check fails early (same discipline as the
    // PATCH-failure path): otherwise the user must re-enter the key and
    // the credential stays orphaned in the vault (CodeRabbit review).
    Future<void> retainReplacementCredential() async {
      final created = createdCredential;
      if (created == null) return;
      await _rememberCredential(
        selectedProviderKey,
        ProviderCredentialReference(
          settingsId: created.settingsId,
          settingsVersion: created.settingsVersion,
          vaultKeyId: created.vaultKeyId,
        ),
      );
    }

    // Decision Model resolution (issue #723). `decisionProviderKey == null`
    // is the explicit "disabled" pick: the patched tri-state serializer
    // sends explicit JSON nulls, so the stored Decision Model is CLEARED
    // (omitted would keep it — the tri-state semantics demand the null).
    // Otherwise the effective decision credential resolves in this order:
    // same-key reuse (same provider + toggle on) → unchanged stored
    // binding → remembered decision credential → newly-bound key (retained
    // even when the PATCH fails, same discipline as the extraction
    // replacement).
    LlmProvider? decisionProvider;
    String? decisionVaultKeyId;
    CredentialHandoff? createdDecisionCredential;
    if (decisionProviderKey != null) {
      decisionProvider =
          _resolveProvider(decisionProviderKey) ??
          (config.decisionProvider?.name == decisionProviderKey
              ? config.decisionProvider
              : null);
      if (decisionProvider == null || decisionModelId == null) {
        const error = ProblemError(code: 'ai_config.incomplete_selection');
        await retainReplacementCredential();
        state = state.copyWith(commandError: error);
        return const Left(error);
      }
      if (decisionProviderKey == selectedProviderKey && useSameDecisionKey) {
        // Same-key reuse: the decision credential IS the extraction key
        // this PATCH carries (the backend permits sharing exactly within
        // the same provider).
        decisionVaultKeyId = vaultKeyId;
      } else {
        final handoffState = await ref.read(aiImportHandoffProvider.future);
        final remembered = handoffState.decisionCredentialFor(
          decisionProviderKey,
        );
        final storedUnchanged =
            config.decisionVaultKeyId != null &&
            config.decisionProvider == decisionProvider;
        // The UNCHANGED stored binding wins over a remembered key
        // (CodeRabbit review): resending the stored key is a no-op the edge
        // does not re-validate, whereas applying the remembered key would
        // silently REPLACE the stored binding without user action. The
        // screen's showDecisionKey logic already excludes this case — the
        // controller order must match.
        if (storedUnchanged) {
          decisionVaultKeyId = config.decisionVaultKeyId;
        } else if (remembered != null) {
          decisionVaultKeyId = remembered.vaultKeyId;
        } else if (decisionReplacementSecret != null &&
            decisionReplacementSecret.isNotEmpty) {
          final outcome = await submitCredentialWithHandoff(
            repo,
            provider: decisionProviderKey,
            secret: decisionReplacementSecret,
          );
          switch (outcome) {
            case HandoffSucceeded(:final handoff):
              createdDecisionCredential = handoff;
              decisionVaultKeyId = handoff.vaultKeyId;
            case HandoffFailed(:final error):
              await retainReplacementCredential();
              if (ref.mounted) state = state.copyWith(commandError: error);
              return Left(error);
          }
        } else {
          const error = ProblemError(code: 'ai_config.decision_key_missing');
          await retainReplacementCredential();
          state = state.copyWith(commandError: error);
          return const Left(error);
        }
      }
    }

    final res = await repo.updateConfig(
      config.id,
      UpdateAiConfigRequest(
        (b) => b
          ..provider = provider
          ..assistantModel = assistantModelId
          ..vaultKeyId = vaultKeyId
          ..version = config.version
          ..imageModel = imageModelId
          ..costDisplayPreference = costDisplayPreference
          ..decisionProvider = decisionProvider
          ..decisionModel = decisionProviderKey == null ? null : decisionModelId
          ..decisionVaultKeyId = decisionVaultKeyId
          ..prompts.replace({
            if (scriptPrompt.isNotEmpty) 'script': scriptPrompt,
            if (schedulePrompt.isNotEmpty) 'schedule': schedulePrompt,
          }),
      ),
    );
    return res.match(
      (err) async {
        // A replacement credential is retained even when the config PATCH
        // fails. This makes retrying safe and avoids asking for the same API
        // key again on the next attempt.
        if (createdCredential != null) {
          await _rememberCredential(
            selectedProviderKey,
            ProviderCredentialReference(
              settingsId: createdCredential.settingsId,
              settingsVersion: createdCredential.settingsVersion,
              vaultKeyId: createdCredential.vaultKeyId,
            ),
          );
        }
        if (createdDecisionCredential != null) {
          await _rememberCredential(
            decisionCredentialKey(decisionProviderKey!),
            ProviderCredentialReference(
              settingsId: createdDecisionCredential.settingsId,
              settingsVersion: createdDecisionCredential.settingsVersion,
              vaultKeyId: createdDecisionCredential.vaultKeyId,
            ),
          );
        }
        // A timeout may have committed. Reconcile before deciding whether a
        // newly-created credential is committed; either way it is retained.
        if (isAmbiguousTimeoutError(err) &&
            selectedProviderKey != config.provider.name) {
          final reconciled = await repo.getConfig(config.id);
          final view = reconciled.getRight().toNullable();
          if (view != null &&
              !view.revoked &&
              view.provider.name == provider.name &&
              view.vaultKeyId == vaultKeyId) {
            ref.invalidate(aiConfigDiscoveryProvider);
            ref.invalidate(configuredAiNamingProvider);
            if (ref.mounted) state = state.copyWith(clearCommandError: true);
            return Right<ProblemError, int>(view.version);
          }
        }
        if (ref.mounted) state = state.copyWith(commandError: err);
        return Left<ProblemError, int>(err);
      },
      (version) async {
        if (createdCredential != null) {
          await _rememberCredential(
            selectedProviderKey,
            ProviderCredentialReference(
              settingsId: createdCredential.settingsId,
              settingsVersion: createdCredential.settingsVersion,
              vaultKeyId: createdCredential.vaultKeyId,
            ),
          );
        }
        if (createdDecisionCredential != null) {
          await _rememberCredential(
            decisionCredentialKey(decisionProviderKey!),
            ProviderCredentialReference(
              settingsId: createdDecisionCredential.settingsId,
              settingsVersion: createdDecisionCredential.settingsVersion,
              vaultKeyId: createdDecisionCredential.vaultKeyId,
            ),
          );
        }
        // Round-trip verification (issue #769): a 2xx PATCH acknowledgement is
        // not evidence that the Decision Model triple was persisted. Compare
        // the SUBMITTED triple against the authoritative view before reporting
        // success; on a mismatch the draft is preserved and NOTHING is
        // refreshed as success, so the screen never presents the submitted
        // configuration as the active one.
        final verdict = await _verifyDecisionRoundTrip(
          config.id,
          DecisionTriple(
            providerKey: decisionProvider?.name,
            modelId: decisionProviderKey == null ? null : decisionModelId,
            vaultKeyId: decisionVaultKeyId,
          ),
        );
        if (verdict.error != null) {
          // CodeRabbit review (issue #769): the PATCH DID commit (only its
          // read-back disagrees), so the aggregate version moved past
          // `state.config.version`. Leaving the stale view in place would make
          // the retry a guaranteed 409 and keep the screen rendering the
          // pre-PATCH configuration, so the authoritative read replaces it.
          // Discovery is deliberately NOT invalidated: this controller watches
          // it, and the rebuild would drop the error — which is the silent
          // "looks saved" class this issue closes. The drafts live in
          // `aiConfigDraftsProvider`, so the user's input survives regardless.
          if (ref.mounted) {
            state = state.copyWith(
              config: verdict.stored,
              commandError: verdict.error,
            );
          }
          return Left<ProblemError, int>(verdict.error!);
        }
        ref.invalidate(aiConfigDiscoveryProvider);
        ref.invalidate(configuredAiNamingProvider);
        if (!ref.mounted) {
          return Right<ProblemError, int>(version);
        }
        state = state.copyWith(clearCommandError: true);
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Revoke with confirm (the UI owns the confirm dialog); the command
  /// carries the current version (optimistic lock).
  Future<Result<int>> revoke() async {
    final config = state.config;
    if (config == null) {
      return const Left(ProblemError(code: 'ai_config.not-found'));
    }
    final repo = ref.read(aiConfigRepositoryProvider);
    final res = await repo.revokeConfig(config.id, config.version);
    return res.match(
      (err) {
        if (ref.mounted) state = state.copyWith(commandError: err);
        return Left<ProblemError, int>(err);
      },
      (version) async {
        ref.invalidate(aiConfigDiscoveryProvider);
        ref.invalidate(configuredAiNamingProvider);
        if (!ref.mounted) {
          return Right<ProblemError, int>(version);
        }
        state = state.copyWith(clearCommandError: true);
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Pull-to-refresh: re-run list-first discovery.
  Future<void> refresh() async {
    ref.invalidate(aiConfigDiscoveryProvider);
    ref.invalidate(configuredAiNamingProvider);
    ref.invalidate(aiProvidersProvider);
  }

  /// The remembered-id fallback read (build() stays sync; this runs
  /// fire-and-forget when the list fetch failed but an id is stored).
  /// The hand-off provider is a FUTURE provider: a bare `ref.read(...).value`
  /// starts the fetch and returns `AsyncLoading` — the fallback would
  /// never run. Await the future instead, and dedupe concurrent/repeated
  /// restarts (each build while the discovery error persists would
  /// otherwise re-fire the fetch).
  Future<void> _loadRememberedConfigFallback() =>
      _rememberedFallbackRun ??= _runRememberedConfigFallback();

  Future<void> _runRememberedConfigFallback() async {
    String? remembered;
    try {
      final handoff = await ref.read(aiImportHandoffProvider.future);
      remembered = handoff.configId;
    } on Object {
      // The hand-off read failed — no remembered id, no fallback (the
      // list route stays the authority; the retry affordance covers it).
      return;
    }
    if (remembered == null) return;
    final res = await ref
        .read(aiConfigRepositoryProvider)
        .getConfig(remembered);
    final view = res.getRight().toNullable();
    if (view != null && !view.revoked && ref.mounted) {
      state = state.copyWith(config: view);
    }
  }
}

/// Dedupes the fire-and-forget remembered-id fallback across controller
/// rebuilds: one launch-scoped attempt, never a re-fire per rebuild.
Future<void>? _rememberedFallbackRun;

/// True when [error] is an ambiguous-timeout transport failure (the
/// dispatch may or may not have committed server-side). Shared with the
/// workflow repository's reconciliation (same stable codes).
/// True when the stored config's Decision binding is the same-key form:
/// no decision key at all (nothing split), or the stored decision key IS
/// the stored extraction key (CodeRabbit review — derived same-key seed).
bool _storedDecisionUsesSameKey(AiConfigView? config) =>
    config == null ||
    config.decisionVaultKeyId == null ||
    config.decisionVaultKeyId == config.vaultKeyId;

bool isAmbiguousTimeoutError(ProblemError error) => switch (error.code) {
  'transport.connectionTimeout' ||
  'transport.sendTimeout' ||
  'transport.receiveTimeout' => true,
  _ => false,
};
