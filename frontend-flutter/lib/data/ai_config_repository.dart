// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';

/// Bounded retry budget for the credential rollback (`DELETE
/// /v1/settings/{id}`) — the vault destruction is best-effort server-side,
/// so a failed rollback is retried before the orphaned-credential notice
/// surfaces (design §2.1 step 6).
const int kMaxRollbackAttempts = 3;

/// Read/write repository for the AI-import **configuration** boundary
/// (`flutter-ai-config` task 1.1).
///
/// Wraps the generated [BreakdownApi] calls — never throws, always
/// [Result]-typed. All routes are `/v1`-prefixed. The LLM API-key secret
/// exists ONLY inside the [submitCredential] request payload (D6): the
/// repository never logs it, never caches it, and the only value it
/// persists downstream is the opaque `vault_key_id` resolved through
/// [resolveVaultKeyId].
///
/// Contract facts (design §1, checked against `backend/openapi.yaml`):
/// * `POST /v1/settings/credentials` returns the **Settings aggregate**
///   `IdVersionResponse` — not the `vault_key_id`.
/// * The `vault_key_id` for `CreateAiConfigRequest` is resolved in a second
///   step via `GET /v1/settings/{id}` → [SettingsView].
/// * Config CRUD: `POST /v1/ai-import/config` (201,
///   `IdVersionResponse`), list-first discovery `GET
///   /v1/ai-import/config` (caller's configs, newest-first), `GET/PATCH
///   /v1/ai-import/config/{id}` (version echo on update), `POST
///   .../revoke`.
/// * Rollback: `DELETE /v1/settings/{id}` with [VersionRequest]
///   (`revokeSettings`); bounded retry, orphaned-credential surfacing.
class AiConfigRepository extends BaseRepository {
  const AiConfigRepository(super.api);

  // --- Discovery ------------------------------------------------------------

  /// `GET /v1/ai-import/providers` — the curated provider catalog
  /// (backend PR #360). Pickers read the routes; no hardcoded model or
  /// provider ids exist client-side (D7).
  Future<Result<List<AiProviderInfo>>> listProviders() => runList(
    () => api.getHandlersApi().listAiProviders(),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );

  /// `GET /v1/ai-import/providers/{provider}/models` — the per-provider
  /// curated model set. A 422 (unknown provider) surfaces as the
  /// `provider.unavailable` narrative in the UI (honest degradation).
  Future<Result<List<ModelInfo>>> listModels(String providerKey) => runList(
    () => api.getHandlersApi().listAiModels(provider: providerKey),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );

  // --- Credentials (the secret transits exactly once) ------------------------

  /// `POST /v1/settings/credentials` — submits the LLM API key to the
  /// server-held vault.
  ///
  /// **D6 secret discipline:** the [secret] lives only inside the
  /// serialized request body. The repository never writes it to any
  /// persistent store, cache, or log sink — asserted in unit tests by
  /// store-write interception on both the success and failure path. The
  /// response is the **Settings aggregate** id + version (`IdVersionResponse`),
  /// NOT the vault key id — resolve that with [resolveVaultKeyId].
  Future<Result<IdVersionResponse>> submitCredential({
    required String provider,
    required String secret,
  }) => run(
    () => api.getHandlersApi().createCredential(
      createCredentialRequest: CreateCredentialRequest(
        (b) => b
          ..provider = provider
          ..secret = secret,
      ),
    ),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );

  /// `GET /v1/settings/{id}` → [SettingsView] — the credential hand-off
  /// read: its `vault_key_id` is the opaque id the config create carries.
  /// The view contains no secret material (write-only vault).
  Future<Result<SettingsView>> getSettings(String id) =>
      run(() => api.getHandlersApi().getSettings(id: id));

  /// `DELETE /v1/settings/{id}` with [VersionRequest] (`revokeSettings`) —
  /// destroys the vault-backed credential (rollback path, design §2.1
  /// step 6). Returns the destroyed aggregate version.
  Future<Result<int>> destroyCredential(String id, int version) => run(
    () => api.getHandlersApi().revokeSettings(
      id: id,
      versionRequest: VersionRequest((b) => b..version = version),
    ),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );

  /// Bounded-retry rollback of a credential Settings aggregate (design
  /// §2.1 step 6). Server-side vault destruction is best-effort, so a
  /// failed delete is retried up to [kMaxRollbackAttempts] times with
  /// [tick] between attempts (injectable seam — tests stay deterministic).
  ///
  /// On exhaustion the error surfaces as
  /// `ai_config.orphaned_credential` (the UI renders the localized
  /// "orphaned credential" notice with a retry affordance — never
  /// silently dropped).
  Future<Result<void>> rollbackCredential(
    String settingsId,
    int version, {
    Future<void> Function(int attempt)? tick,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < kMaxRollbackAttempts; attempt++) {
      final tickFn = tick;
      if (tickFn != null) await tickFn(attempt);
      final destroyed = await destroyCredential(settingsId, version);
      if (destroyed.isRight()) return const Right(null);
      // The LAST attempt's error is preserved for surfacing; earlier
      // attempts are dropped (bounded retry, single surfaced cause).
      final failure = destroyed.getLeft().toNullable();
      if (failure != null) lastError = failure;
    }
    final failure = lastError;
    return Left(
      failure is ProblemError
          ? ProblemError(
              code: 'ai_config.orphaned_credential',
              title: failure.title,
              detail: failure.detail,
              status: failure.status,
            )
          : const ProblemError(code: 'ai_config.orphaned_credential'),
    );
  }

  // --- Config CRUD -----------------------------------------------------------

  /// `POST /v1/ai-import/config` → 201 `IdVersionResponse`. Carries the
  /// opaque `vault_key_id` resolved via [resolveVaultKeyId] — never the
  /// API-key secret (D6).
  Future<Result<IdVersionResponse>> createConfig(
    CreateAiConfigRequest request,
  ) => run(
    () => api.getHandlersApi().createAiConfig(createAiConfigRequest: request),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );

  /// `GET /v1/ai-import/config` — the caller's configs, newest-first
  /// (backend issue #337, PR #357). **List-first discovery** (D2): the
  /// authoritative source; the remembered id in secure storage is only a
  /// fast-path/fallback.
  Future<Result<List<AiConfigView>>> listConfigs() =>
      fetchAllPages<AiConfigView>(
        ({required int limit, required int offset}) =>
            api.getHandlersApi().listAiConfigs(limit: limit, offset: offset),
        dtoInvalidCode: 'ai_config.dto_invalid',
      );

  /// `GET /v1/ai-import/config/{id}` → [AiConfigView] (public view —
  /// opaque `vault_key_id`, NO secret material; owner-checked server-side).
  Future<Result<AiConfigView>> getConfig(String id) =>
      run(() => api.getHandlersApi().getAiConfig(id: id));

  /// `PATCH /v1/ai-import/config/{id}` — the request carries the `version`
  /// echoed from the fetched [AiConfigView]; a 409 surfaces as
  /// `ai_config.conflict` copy ("changed elsewhere — refresh") with no
  /// automatic version-bump re-dispatch (spec `flutter-ai-config`).
  /// Returns the new aggregate version.
  Future<Result<int>> updateConfig(String id, UpdateAiConfigRequest request) =>
      run(
        () => api.getHandlersApi().updateAiConfig(
          id: id,
          updateAiConfigRequest: request,
        ),
        dtoInvalidCode: 'ai_config.dto_invalid',
      );

  /// `POST /v1/ai-import/config/{id}/revoke` with the current version
  /// (optimistic lock). Returns the revoked aggregate version.
  Future<Result<int>> revokeConfig(String id, int version) => run(
    () => api.getHandlersApi().revokeAiConfig(
      id: id,
      revokeAiConfigRequest: RevokeAiConfigRequest((b) => b..version = version),
    ),
    dtoInvalidCode: 'ai_config.dto_invalid',
  );
}

/// The reconciled outcome of an ambiguous config-create timeout (design
/// §2.1 step 7).
sealed class ConfigCreateReconciliation {
  const ConfigCreateReconciliation();
}

/// The config committed — keep the credential, continue to the config
/// screen.
class ConfigCommitted extends ConfigCreateReconciliation {
  const ConfigCommitted(this.view);

  final AiConfigView view;
}

/// Definitively not committed (the config list/get both 404'd) — run the
/// step-6 rollback.
class ConfigNotCommitted extends ConfigCreateReconciliation {
  const ConfigNotCommitted();
}

/// Unresolved after the bounded reconciliation attempts — the UI surfaces
/// the "configuration state unknown — verify" state with both actions
/// offered; the credential is never destroyed while it may be referenced.
class ConfigUnknown extends ConfigCreateReconciliation {
  const ConfigUnknown(this.error);

  final ProblemError error;
}

/// Reconciles an ambiguous config-create timeout (design §2.1 step 7,
/// task 1.2): re-reads the config reality BEFORE any credential cleanup —
/// the credential is never destroyed while it may be referenced by a
/// committed config.
///
/// [configId] is the create request's remembered id (the id the client
/// would have received). [attempts] bounds the reconciliation reads with
/// [tick] between them (injectable seam — no wall-clock gating).
///
/// * A list hit (or remembered-id get hit) → [ConfigCommitted].
/// * A definitive 404 on the config get AND an empty list →
///   [ConfigNotCommitted].
/// * Any transport/unresolved error after the bounded attempts →
///   [ConfigUnknown].
Future<ConfigCreateReconciliation> reconcileConfigCreate(
  AiConfigRepository repo, {
  required String configId,
  int attempts = 3,
  Future<void> Function(int attempt)? tick,
}) async {
  ProblemError? lastError;
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tick?.call(attempt);
    final fetched = await repo.getConfig(configId);
    final view = fetched.getRight().toNullable();
    if (view != null) return ConfigCommitted(view);
    lastError = fetched.getLeft().toNullable();
    // A definitive 404 (server-rendered, not a transport failure) also
    // cross-checks the list route: an empty list confirms "not committed".
    if (lastError?.status == 404) {
      final listed = await repo.listConfigs();
      final configs = listed.getRight().toNullable();
      if (configs != null && configs.every((c) => c.id != configId)) {
        return const ConfigNotCommitted();
      }
      if (configs == null) {
        lastError = listed.getLeft().toNullable();
      }
    }
  }
  return ConfigUnknown(
    lastError ?? const ProblemError(code: 'ai_config.state_unknown'),
  );
}

/// Reconciles an ambiguous FRESH config-create timeout (design §2.1 step
/// 7, fresh-create variant): the create response never arrived, so there
/// is no config id to read — the list route is the only reality probe.
/// A config carrying this credential's `vault_key_id` proves the create
/// committed (keep the credential); a readable list without a match proves
/// it did not (the caller runs the step-6 rollback); anything else stays
/// unknown and the credential is never destroyed while it may be
/// referenced.
Future<ConfigCreateReconciliation> reconcileConfigByVaultKey(
  AiConfigRepository repo, {
  required String vaultKeyId,
  int attempts = 3,
  Future<void> Function(int attempt)? tick,
}) async {
  ProblemError? lastError;
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tick?.call(attempt);
    final listed = await repo.listConfigs();
    final configs = listed.getRight().toNullable();
    if (configs != null) {
      final matches = configs
          .where((c) => c.vaultKeyId == vaultKeyId && !c.revoked)
          .toList();
      return matches.isEmpty
          ? const ConfigNotCommitted()
          : ConfigCommitted(matches.first);
    }
    lastError = listed.getLeft().toNullable();
  }
  return ConfigUnknown(
    lastError ?? const ProblemError(code: 'ai_config.state_unknown'),
  );
}

/// The credential hand-off result (design §2.1 steps 3–4): the Settings
/// aggregate id + version (for the rollback path) and the opaque
/// `vault_key_id` the config create carries.
class CredentialHandoff {
  const CredentialHandoff({
    required this.settingsId,
    required this.settingsVersion,
    required this.vaultKeyId,
  });

  final String settingsId;
  final int settingsVersion;
  final String vaultKeyId;
}

/// Submits the LLM API key and resolves the opaque `vault_key_id` in the
/// exact two-step hand-off (design §2.1 steps 3–4, task 1.1):
/// `POST /v1/settings/credentials` → `GET /v1/settings/{id}`.
///
/// The [secret] lives only in the first request's payload (D6); the
/// returned hand-off carries no secret material. Every failure — including
/// a failed hand-off read AFTER a successful submission — surfaces as
/// `Left`; the caller decides whether to roll back the created Settings
/// aggregate ([AiConfigRepository.rollbackCredential]) — the repository
/// never destroys a credential on its own.
Future<Result<CredentialHandoff>> submitCredentialWithHandoff(
  AiConfigRepository repo, {
  required String provider,
  required String secret,
}) async {
  final submitted = await repo.submitCredential(
    provider: provider,
    secret: secret,
  );
  final idVersion = submitted.getRight().toNullable();
  if (idVersion == null) return Left(submitted.getLeft().toNullable()!);
  final view = await repo.getSettings(idVersion.id);
  final settings = view.getRight().toNullable();
  if (settings == null) return Left(view.getLeft().toNullable()!);
  final vaultKeyId = settings.vaultKeyId;
  if (vaultKeyId.isEmpty) {
    // A committed Settings aggregate with no vault key id is a DTO
    // shape violation — the hand-off is unusable, surface it (no
    // silent retry loop, no destroyed credential).
    return const Left(ProblemError(code: 'ai_config.vault_key_missing'));
  }
  return Right(
    CredentialHandoff(
      settingsId: idVersion.id,
      settingsVersion: idVersion.version,
      vaultKeyId: vaultKeyId,
    ),
  );
}
