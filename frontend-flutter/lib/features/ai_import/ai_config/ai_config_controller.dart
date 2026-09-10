// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

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
/// no hardcoded ids. A 404 (AI import disabled) or a transport failure
/// degrades honestly in the screen.
@riverpod
Future<Result<List<AiProviderInfo>>> aiProviders(Ref ref) =>
    ref.watch(aiConfigRepositoryProvider).listProviders();

/// The selected provider's model set. A 422 (unknown provider) surfaces
/// as `Err` — the "provider unavailable" degradation.
@riverpod
Future<Result<List<ModelInfo>>> aiProviderModels(Ref ref, String key) =>
    ref.watch(aiConfigRepositoryProvider).listModels(key);

/// The ephemeral form-draft data (immutable snapshot). Kept in its own
/// [Notifier] so it survives controller rebuilds (the reference pattern:
/// `SeasonOverlays`); the masked key is deliberately NOT here — the
/// secret is a submit-time parameter only (D6).
class AiConfigDraftData {
  AiConfigDraftData({
    this.selectedProviderKey,
    this.selectedAssistantModelId,
    this.selectedImageModelId,
    this.imageModelTouched = false,
    this.scriptPrompt = '',
    this.schedulePrompt = '',
    this.unresolved,
  });

  String? selectedProviderKey;
  String? selectedAssistantModelId;
  String? selectedImageModelId;

  /// True once the user picked (or cleared) the image model, so an
  /// explicit `null` is honoured instead of falling back to the config —
  /// without it the optional image model could never be cleared.
  bool imageModelTouched;
  String scriptPrompt;
  String schedulePrompt;
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
      imageModelTouched: state.imageModelTouched,
      scriptPrompt: state.scriptPrompt,
      schedulePrompt: state.schedulePrompt,
      unresolved: state.unresolved,
    );
    fn(next);
    state = next;
  }
}

final aiConfigDraftsProvider =
    NotifierProvider<AiConfigDrafts, AiConfigDraftData>(AiConfigDrafts.new);

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

    final selectedProviderKey =
        drafts.selectedProviderKey ?? config?.provider.name;
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
    return AiConfigScreenState(
      config: config,
      discoveryError: discoveryError,
      providers: providersState,
      models: models,
      selectedProviderKey: selectedProviderKey,
      selectedAssistantModelId:
          drafts.selectedAssistantModelId ?? config?.assistantModel,
      selectedImageModelId: drafts.imageModelTouched
          ? drafts.selectedImageModelId
          : (config?.imageModel ?? drafts.selectedImageModelId),
      scriptPrompt: drafts.scriptPrompt,
      schedulePrompt: drafts.schedulePrompt,
      unresolved: drafts.unresolved,
    );
  }

  /// Selects a provider and loads its model set.
  void selectProvider(String key) {
    _draftsNotifier.mutate((d) {
      d.selectedProviderKey = key;
      d.selectedAssistantModelId = null;
      d.selectedImageModelId = null;
    });
    state = state.copyWith(clearCommandError: true);
  }

  void selectAssistantModel(String id) {
    _draftsNotifier.mutate((d) => d.selectedAssistantModelId = id);
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

  void setScriptPrompt(String value) {
    _draftsNotifier.mutate((d) => d.scriptPrompt = value);
  }

  void setSchedulePrompt(String value) {
    _draftsNotifier.mutate((d) => d.schedulePrompt = value);
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
  Future<Result<IdVersionResponse>> create({required String secret}) async {
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

    // Step 3: the config create carrying ONLY the opaque vault key id.
    final created = await repo.createConfig(
      CreateAiConfigRequest(
        (b) => b
          ..provider = provider
          ..assistantModel = assistantModelId
          ..vaultKeyId = credential.vaultKeyId
          ..imageModel = s.selectedImageModelId
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
          unawaited(_reconcileFreshCreate(credential, s));
          return Left<ProblemError, IdVersionResponse>(error);
        }
        // Step 6: bounded rollback of the just-created credential.
        unawaited(_rollbackCredential(credential, scheduler));
        if (ref.mounted) state = state.copyWith(commandError: error);
        return Left<ProblemError, IdVersionResponse>(error);
      },
      (idVersion) async {
        // Success: remember the config id (fast-path for the next launch;
        // the list route stays authoritative, D2) and refresh discovery.
        await _rememberConfigId(idVersion.id);
        if (!ref.mounted) {
          return Right<ProblemError, IdVersionResponse>(idVersion);
        }
        ref.invalidate(aiConfigDiscoveryProvider);
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
  /// key id before any cleanup.
  Future<void> _reconcileFreshCreate(
    CredentialHandoff credential,
    AiConfigScreenState snapshot,
  ) async {
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
        if (!ref.mounted) return;
        ref.invalidate(aiConfigDiscoveryProvider);
        ref.invalidate(aiImportHandoffProvider);
        state = state.copyWith(clearCommandError: true);
      case ConfigNotCommitted():
        // Definitively not committed — run the step-6 rollback.
        await _rollbackCredential(credential, scheduler);
      case ConfigUnknown(:final error):
        // Unresolved — the "configuration state unknown — verify" state
        // with both actions offered; the credential is never destroyed
        // while it may be referenced by a committed config.
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
    required String? assistantModelId,
    required String? imageModelId,
    required String scriptPrompt,
    required String schedulePrompt,
  }) async {
    final config = state.config;
    if (config == null) {
      return const Left(ProblemError(code: 'ai_config.not-found'));
    }
    final repo = ref.read(aiConfigRepositoryProvider);
    final res = await repo.updateConfig(
      config.id,
      UpdateAiConfigRequest(
        (b) => b
          ..provider = config.provider
          ..assistantModel = assistantModelId ?? config.assistantModel
          ..vaultKeyId = config.vaultKeyId
          ..version = config.version
          ..imageModel = imageModelId
          ..prompts.replace({
            if (scriptPrompt.isNotEmpty) 'script': scriptPrompt,
            if (schedulePrompt.isNotEmpty) 'schedule': schedulePrompt,
          }),
      ),
    );
    return res.match(
      (err) {
        if (ref.mounted) state = state.copyWith(commandError: err);
        return Left<ProblemError, int>(err);
      },
      (version) async {
        ref.invalidate(aiConfigDiscoveryProvider);
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
bool isAmbiguousTimeoutError(ProblemError error) => switch (error.code) {
  'transport.connectionTimeout' ||
  'transport.sendTimeout' ||
  'transport.receiveTimeout' => true,
  _ => false,
};
