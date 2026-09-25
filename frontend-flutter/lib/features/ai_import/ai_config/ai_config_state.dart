// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The AI-import configuration screen state (`flutter-ai-config` task 2.1).
///
/// Rendered states (spec `Vault-Backed AI Configuration Screens`):
/// * **not configured yet** — the list-first discovery found no config
///   (empty list or the remembered id 404'd) → the provider picker + the
///   masked key field.
/// * **configured** — an active config was discovered; edit/revoke paths.
/// * **denied** — a 403 credential-role denial (D4: session-only
///   pre-gate; the narrative renders, no capability surface exists).
/// * **conflict** — a 409 version conflict on edit ("changed elsewhere —
///   refresh"; no automatic version-bump re-dispatch).
/// * **state unknown** — an ambiguous create timeout that the bounded
///   reconciliation could not resolve; both actions (keep / clean up) are
///   offered; the credential is never destroyed automatically.
class AiConfigScreenState {
  const AiConfigScreenState({
    required this.config,
    required this.providers,
    required this.models,
    required this.selectedProviderKey,
    this.selectedAssistantModelId,
    this.selectedImageModelId,
    this.scriptPrompt = '',
    this.schedulePrompt = '',
    this.commandError,
    this.unresolved,
    this.discoveryError,
    this.promptDefaults,
  });

  /// The discovered active config, or `null` for the first-run state.
  /// List-first discovery (D2): `GET /v1/ai-import/config` is
  /// authoritative; the remembered id is only a fast-path/fallback.
  final AiConfigView? config;

  /// The provider catalog (`GET /v1/ai-import/providers`).
  final AsyncValue<List<AiProviderInfo>> providers;

  /// The selected provider's model set (`GET /v1/ai-import/providers/
  /// {key}/models`); a 422 surfaces as the degraded "provider
  /// unavailable" copy (honest degradation — never empty pickers
  /// masquerading as "no providers exist").
  final AsyncValue<List<ModelInfo>> models;

  /// The currently selected provider key (picker state, null on first run).
  final String? selectedProviderKey;
  final String? selectedAssistantModelId;
  final String? selectedImageModelId;

  /// Per-document-kind prompt drafts (script/schedule).
  final String scriptPrompt;
  final String schedulePrompt;

  /// The last command failure, keyed on the stable problem `code` — the
  /// screen never renders the server `detail` (AGENTS.md §5).
  final ProblemError? commandError;

  /// The "configuration state unknown — verify" outcome of an ambiguous
  /// create timeout after bounded reconciliation (design §2.1 step 7).
  /// Carries the created-but-unconfirmed credential hand-off; the UI
  /// offers keep (re-check) and clean-up (rollback) actions.
  final AiConfigUnresolved? unresolved;

  /// The list-first discovery failure (`GET /v1/ai-import/config`).
  /// When set (with `config == null`) the screen renders the retry
  /// state — NEVER the first-run form, whose save button would create a
  /// second credential for an account that may already have one (honest
  /// degradation — a failed discovery is not "no config exists").
  final ProblemError? discoveryError;

  /// `GET /v1/ai-import/defaults` wire read (issue #471): the prefill
  /// source for the first-run prompt fields. A failure degrades to empty
  /// editable fields — never a blocking error state; the success hint is
  /// purely informational.
  final AsyncValue<AiImportDefaults>? promptDefaults;

  bool get isFirstRun => config == null && discoveryError == null;

  AiConfigScreenState copyWith({
    AiConfigView? config,
    bool clearConfig = false,
    AsyncValue<List<AiProviderInfo>>? providers,
    AsyncValue<List<ModelInfo>>? models,
    String? selectedProviderKey,
    bool clearSelectedProvider = false,
    String? selectedAssistantModelId,
    String? selectedImageModelId,
    String? scriptPrompt,
    String? schedulePrompt,
    ProblemError? commandError,
    bool clearCommandError = false,
    AiConfigUnresolved? unresolved,
    bool clearUnresolved = false,
    ProblemError? discoveryError,
    bool clearDiscoveryError = false,
    AsyncValue<AiImportDefaults>? promptDefaults,
  }) => AiConfigScreenState(
    config: clearConfig ? null : (config ?? this.config),
    providers: providers ?? this.providers,
    models: models ?? this.models,
    selectedProviderKey: clearSelectedProvider
        ? null
        : (selectedProviderKey ?? this.selectedProviderKey),
    selectedAssistantModelId:
        selectedAssistantModelId ?? this.selectedAssistantModelId,
    selectedImageModelId: selectedImageModelId ?? this.selectedImageModelId,
    scriptPrompt: scriptPrompt ?? this.scriptPrompt,
    schedulePrompt: schedulePrompt ?? this.schedulePrompt,
    commandError: clearCommandError
        ? null
        : (commandError ?? this.commandError),
    unresolved: clearUnresolved ? null : (unresolved ?? this.unresolved),
    discoveryError: clearDiscoveryError
        ? null
        : (discoveryError ?? this.discoveryError),
    promptDefaults: promptDefaults ?? this.promptDefaults,
  );
}

/// The unresolved create outcome: the credential hand-off (Settings
/// aggregate) exists but the config commit is unconfirmed. The UI offers
/// both follow-ups; neither destroys the credential implicitly.
class AiConfigUnresolved {
  const AiConfigUnresolved({
    required this.settingsId,
    required this.settingsVersion,
    required this.vaultKeyId,
    required this.providerKey,
    required this.assistantModelId,
    required this.imageModelId,
    required this.scriptPrompt,
    required this.schedulePrompt,
    required this.error,
  });

  final String settingsId;
  final int settingsVersion;
  final String vaultKeyId;
  final String providerKey;
  final String assistantModelId;
  final String? imageModelId;
  final String scriptPrompt;
  final String schedulePrompt;
  final ProblemError error;
}

/// Localized client-side copy for a config command failure, keyed on the
/// stable problem `code` (never the server `detail`). Unknown codes fall
/// back to a code-carrying generic.
///
/// The 403 arms match the scoped wire codes the backend emits for the
/// credential-role gates (issue #470): `ai-config.forbidden` (AI-config
/// management/discovery) and `settings.forbidden` (settings credentials) —
/// NOT the generic `domain.forbidden`. A real credential-role denial must
/// land on the "administrator role required" narrative, never the fallback.
String aiConfigErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'ai-config.forbidden' || 'settings.forbidden' => l10n.aiConfigErrorAdmin,
      // 409 `ai-config.version-mismatch` — the scoped optimistic-lock code
      // the backend emits on a stale config edit/revoke (issue #481),
      // preserving the typed expected/current extensions. Same narrative as
      // the client-wide version-conflict copy.
      'ai-config.version-mismatch' => l10n.aiConfigErrorChanged,
      'ai_config.orphaned_credential' => l10n.aiConfigErrorOrphaned,
      'provider.unavailable' => l10n.aiConfigErrorProvider,
      // Wire code of the backend's `ai-import.disabled` problem (issue
      // #422). The disabled state is a server configuration, NOT a
      // transient failure — the UI renders it without a retry affordance.
      'ai-import.disabled' => l10n.aiConfigErrorDisabled,
      _ when error.code.startsWith('transport.') => l10n.aiConfigErrorNetwork,
      _ => l10n.aiConfigErrorGeneric(error.code),
    };

/// True when the backend refused the call because the AI import feature is
/// disabled on this instance (wire code `ai-import.disabled`, status 404,
/// issue #422). Distinct from a genuine `domain.not-found`: retrying cannot
/// fix a feature flag, so the UI must not offer a retry affordance.
bool isAiImportDisabled(ProblemError error) =>
    error.code == 'ai-import.disabled';
