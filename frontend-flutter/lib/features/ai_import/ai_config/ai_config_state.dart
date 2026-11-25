// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
    this.selectedDecisionProviderKey,
    this.selectedDecisionModelId,
    this.useSameDecisionKey = true,
    this.costDisplayPreference = CostDisplayPreference.token,
    this.reasoningEffort = ReasoningEffortChoice.auto,
    this.zdrAttested = false,
    this.decisionModels = const AsyncValue<List<ModelInfo>>.loading(),
    this.imageModels = const AsyncValue<List<ModelInfo>>.loading(),
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

  /// The optional Decision / Scoring Model configuration (issue #723).
  /// [selectedDecisionProviderKey] is `null` when scoring is disabled
  /// ("None / deaktiviert" — the honest default) or not yet picked.
  final String? selectedDecisionProviderKey;
  final String? selectedDecisionModelId;

  /// The "Use same API key as extraction" toggle (issue #723). Only shown
  /// when [selectedDecisionProviderKey] equals the extraction provider
  /// key; `true` (the default) reuses the extraction `vault_key_id`.
  final bool useSameDecisionKey;

  /// The preferred primary cost display metric (issue #675): the draft
  /// pick, else the configured value, else the `token` default. Rendered
  /// by the cost-display selector and used as the PATCH payload value.
  final CostDisplayPreference costDisplayPreference;

  /// The drafted `reasoning_effort` (2026-11-20 output-budget investigation).
  /// A VALUE, not a nullable tri-state: the generated client omits `null`
  /// fields, so a nullable setting could be set but never reset from the app.
  /// `auto` = "let the system decide" (curated profile, else provider default)
  /// and is always choosable — even on a pair that declares no parameter at all,
  /// which is exactly what every pre-field configuration did.
  final ReasoningEffortChoice reasoningEffort;

  /// The operator's zero-data-retention attestation for the selected provider
  /// account (issue #968, ADR-041 `D2`). Some EU providers carry the ZDR
  /// guarantee only as an ACCOUNT-level switch the backend cannot observe
  /// (Nebius Token Factory: "ZDR Mode" in the organization settings), so the
  /// backend keeps its vision egress gate fail-closed until the operator
  /// attests the setting here. The attestation can lift ONLY the ZDR flag —
  /// the no-training and EU-residency guarantees always come from the
  /// provider declaration.
  ///
  /// Rendered as a switch next to the provider picker; a VALUE rather than a
  /// nullable tri-state so an attestation can be revoked from the app.
  final bool zdrAttested;

  /// The selected DECISION provider's model set (`GET /v1/ai-import/
  /// providers/{key}/models`, issue #723). Same honest degradation as
  /// [models].
  final AsyncValue<List<ModelInfo>> decisionModels;

  /// The selected provider's curated IMAGE-generation model set
  /// (`GET /v1/ai-import/providers/{key}/image-models`, issue #732).
  /// Distinct catalog from [models] — a text-only provider serves an
  /// EMPTY list (the picker collapses to "— none —", never the LLM list).
  /// Same honest degradation as [models].
  final AsyncValue<List<ModelInfo>> imageModels;

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

  /// The deployment default prompt text for [kind] from
  /// `GET /v1/ai-import/defaults`, or null when the defaults fetch failed or
  /// has not resolved yet — the reset affordance is disabled rather than
  /// writing an invented value (spec `ai-import`: no silent discard).
  String? promptDefaultFor(DocumentKind kind) {
    // The controller already unwraps the `Result` into this AsyncValue, so the
    // data payload is the DTO itself.
    return switch (promptDefaults) {
      AsyncData(:final value) =>
        kind == DocumentKind.script ? value.script : value.schedule,
      _ => null,
    };
  }

  bool get isFirstRun => config == null && discoveryError == null;

  /// True when the rendered form differs from the STORED configuration view.
  ///
  /// This screen keeps every edit in ephemeral drafts (see
  /// [AiConfigDraftData]) and persists nothing until the user presses save, so
  /// an unnoticed navigation away silently discarded the edit — the reported
  /// "the Decision Model I picked was never saved" class of loss. The flag
  /// drives the screen's unsaved-changes surface: the sticky action bar's
  /// indicator and the back-navigation guard that offers "discard" vs "keep
  /// editing" instead of dropping the draft.
  ///
  /// The comparison runs against the SEEDED baseline, not the raw stored
  /// values: a prefilled (untouched) prompt field must not read as a user
  /// edit, and the same-key toggle is compared against the value derived from
  /// the stored binding for the same reason.
  bool get hasUnsavedChanges {
    final stored = config;
    if (stored == null) return false;
    if (selectedProviderKey != stored.provider.name) return true;
    if (selectedAssistantModelId != stored.assistantModel) return true;
    if (selectedImageModelId != stored.imageModel) return true;
    if (costDisplayPreference !=
        (stored.costDisplayPreference ?? CostDisplayPreference.token)) {
      return true;
    }
    if (reasoningEffort !=
        (stored.reasoningEffort ?? ReasoningEffortChoice.auto)) {
      return true;
    }
    if (zdrAttested != (stored.zdrAttested ?? false)) return true;
    if (scriptPrompt != _seededPrompt(DocumentKind.script)) return true;
    if (schedulePrompt != _seededPrompt(DocumentKind.schedule)) return true;
    if (selectedDecisionProviderKey != stored.decisionProvider?.name) {
      return true;
    }
    if (selectedDecisionModelId != stored.decisionModel) return true;
    if (useSameDecisionKey != storedDecisionUsesSameKey(stored)) return true;
    return false;
  }

  /// The prompt text the form is SEEDED with for [kind] — mirror of the
  /// controller's `promptSeed`: a non-empty stored prompt wins, otherwise the
  /// deployment default (or an empty field when the defaults fetch failed).
  String _seededPrompt(DocumentKind kind) {
    final stored =
        config?.prompts[kind == DocumentKind.script ? 'script' : 'schedule'];
    if (stored != null && stored.isNotEmpty) return stored;
    return promptDefaultFor(kind) ?? '';
  }

  AiConfigScreenState copyWith({
    AiConfigView? config,
    bool clearConfig = false,
    AsyncValue<List<AiProviderInfo>>? providers,
    AsyncValue<List<ModelInfo>>? models,
    String? selectedProviderKey,
    bool clearSelectedProvider = false,
    String? selectedAssistantModelId,
    String? selectedImageModelId,
    String? selectedDecisionProviderKey,
    bool clearSelectedDecisionProvider = false,
    String? selectedDecisionModelId,
    bool clearSelectedDecisionModel = false,
    bool? useSameDecisionKey,
    CostDisplayPreference? costDisplayPreference,
    ReasoningEffortChoice? reasoningEffort,
    bool? zdrAttested,
    AsyncValue<List<ModelInfo>>? decisionModels,
    AsyncValue<List<ModelInfo>>? imageModels,
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
    selectedDecisionProviderKey: clearSelectedDecisionProvider
        ? null
        : (selectedDecisionProviderKey ?? this.selectedDecisionProviderKey),
    selectedDecisionModelId: clearSelectedDecisionModel
        ? null
        : (selectedDecisionModelId ?? this.selectedDecisionModelId),
    useSameDecisionKey: useSameDecisionKey ?? this.useSameDecisionKey,
    costDisplayPreference: costDisplayPreference ?? this.costDisplayPreference,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    zdrAttested: zdrAttested ?? this.zdrAttested,
    decisionModels: decisionModels ?? this.decisionModels,
    imageModels: imageModels ?? this.imageModels,
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

/// Whether the STORED config's Decision binding is the same-key form: no
/// decision key at all (nothing split), or the stored decision key IS the
/// stored extraction key. Until the user flips the toggle, this is the value
/// the screen derives the "Use same API key as extraction" switch from — and
/// therefore also the baseline [AiConfigScreenState.hasUnsavedChanges]
/// compares against (a stored split-billing binding must not read as a dirty
/// toggle).
bool storedDecisionUsesSameKey(AiConfigView? config) =>
    config == null ||
    config.decisionVaultKeyId == null ||
    config.decisionVaultKeyId == config.vaultKeyId;

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
    required this.zdrAttested,
    required this.zdrGeneration,
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

  /// The zero-data-retention attestation this dispatch submitted (issue #968
  /// review). The re-check must carry it: without it the reconciliation cannot
  /// tell the submitted value from a later edit, and a surviving draft would
  /// mask a revocation.
  final bool zdrAttested;

  /// The attestation draft's edit generation at the ORIGINAL dispatch
  /// (issue #968 review): the re-check must settle that generation, not the
  /// one the draft carries by the time it runs, so a flip made in between is
  /// never mistaken for the create's own.
  final int zdrGeneration;
  final ProblemError error;
}

/// Client-detected problem code for the EXACT pre-tap credential gate
/// (issue #816).
///
/// No server problem carries this code: `GET /v1/me/capabilities` answered a
/// RESOLVED denial, so the AI-config discovery dispatch was suppressed instead
/// of provoking a 403 the client already knew was coming. It deliberately rides
/// the same narrative as a real `ai-config.forbidden` — one behaviour, two
/// sources — so the screen renders identically whether the denial came from the
/// wire or from the capability mirror (same pattern as
/// `ai_import.scope_missing` / `ai_config.decision_key_missing`).
const String kAiConfigCapabilityDeniedCode = 'ai_config.capability_denied';

/// Localized client-side copy for a config command failure, keyed on the
/// stable problem `code` (never the server `detail`). Unknown codes fall
/// back to a code-carrying generic.
///
/// **Every `ai-config.*` code the backend registry can emit has an arm here.**
/// The 2026-11-21 report made the cost of a missing arm concrete: a provider
/// switch whose Decision Model the new provider does not curate came back as a
/// precise `422 ai-config.decision-model-unknown` ("Das Entscheidungsmodell ist
/// für diesen Anbieter nicht freigegeben.") and the screen rendered the generic
/// "Die Konfigurationsänderung ist fehlgeschlagen (ai-config.…)" — the user
/// retried six times, one orphaned Vault credential each. The fallback arm stays
/// for codes the server adds later, but a code that HAS copy must never reach it
/// (`ai_config_screen_test.dart` pins the whole registry list).
///
/// The 403 arms match the scoped wire codes the backend emits for the
/// credential-role gates (issue #470): `ai-config.forbidden` (AI-config
/// management/discovery) and `settings.forbidden` (settings credentials) —
/// NOT the generic `domain.forbidden`. A real credential-role denial must
/// land on the "administrator role required" narrative, never the fallback.
String aiConfigErrorCopy(
  AppLocalizations l10n,
  ProblemError error,
) => switch (error.code) {
  'ai-config.forbidden' ||
  'settings.forbidden' ||
  // Client-detected pre-tap denial (issue #816): same narrative, because
  // it is the same fact — the caller lacks the credential role.
  kAiConfigCapabilityDeniedCode => l10n.aiConfigErrorAdmin,
  // 409 `ai-config.version-mismatch` — the scoped optimistic-lock code
  // the backend emits on a stale config edit/revoke (issue #481),
  // preserving the typed expected/current extensions. Same narrative as
  // the client-wide version-conflict copy.
  'ai-config.version-mismatch' => l10n.aiConfigErrorChanged,
  // 409 `ai-config.provider-mismatch` — the API edge refuses to persist a
  // vault key that is not an active credential of the requested provider
  // (issue #528). Distinct from `provider.unavailable` (the model catalog
  // of a provider could not be read): here the STORED key belongs to a
  // different provider, so the copy asks for the matching provider or a
  // new key instead of pretending the provider is down.
  'ai-config.provider-mismatch' => l10n.aiConfigErrorProviderMismatch,
  // 422 `ai-config.reasoning-effort-unsupported` (2026-11-20
  // investigation): the pair does not DECLARE the parameter, or not this
  // level. The picker only offers declared levels, so this arm is the
  // honest answer to catalogue drift or a second client — not a path the
  // UI walks on purpose.
  'ai-config.reasoning-effort-unsupported' =>
    l10n.aiConfigReasoningEffortUnsupported,
  // 422 `ai-config.decision-model-unknown` — the model exists but is not
  // curated for THAT provider. The reachable-by-accident case: the provider
  // picker reset the model, a stale catalogue or a second client put one
  // back, or the decision provider changed while its model did not. The
  // copy names the fix (pick another decision model), which is the whole
  // difference to the generic fallback.
  'ai-config.decision-model-unknown' => l10n.aiConfigErrorDecisionModelUnknown,
  // 422 `ai-config.decision-provider-unsupported` — the provider cannot
  // score at all (not in the backend's decision-capable set).
  'ai-config.decision-provider-unsupported' =>
    l10n.aiConfigErrorDecisionProviderUnsupported,
  // 422 `ai-config.decision-incomplete` / `-model-empty` /
  // `-vault-key-empty` — a partially set Decision triple. The aggregate
  // validates the triple as a whole, so the fix is one sentence, not three.
  'ai-config.decision-incomplete' ||
  'ai-config.decision-model-empty' ||
  'ai-config.decision-vault-key-empty' => l10n.aiConfigErrorDecisionIncomplete,
  // 422 `ai-config.empty-provider` / `-model` / `-prompt` / `-vault-key` —
  // the aggregate's field validation. The form prevents all four, so this
  // arm is for a second client or a replay, not a path the UI walks.
  'ai-config.empty-provider' ||
  'ai-config.empty-model' ||
  'ai-config.empty-prompt' ||
  'ai-config.empty-vault-key' => l10n.aiConfigErrorIncomplete,
  // 404 `ai-config.not-found` — the row is gone (revoked elsewhere, or a
  // dev data reset). Nothing to retry but the read.
  'ai-config.not-found' => l10n.aiConfigErrorNotFound,
  // 409 `ai-config.already-revoked` — a second revoke of the same config.
  'ai-config.already-revoked' => l10n.aiConfigErrorAlreadyRevoked,
  // 403 `ai-config.vault-key-forbidden` (issue #552) — an opaque key that
  // resolves to a binding the caller does not own. Distinct from
  // `provider-mismatch`: the provider CAN be right, the account is not.
  'ai-config.vault-key-forbidden' => l10n.aiConfigErrorVaultKeyForbidden,
  'ai_config.orphaned_credential' => l10n.aiConfigErrorOrphaned,
  // 409-armed client-side guard (issue #723): the decision model is
  // configured but no decision API key is available (none remembered,
  // none entered) — the client refuses BEFORE dispatching a config
  // create/PATCH the backend would reject with an unusable binding.
  'ai_config.decision_key_missing' => l10n.aiConfigDecisionKeyMissing,
  // Client-detected (issue #769): the save was acknowledged but the
  // read-back of `GET /v1/ai-import/config/{id}` did not contain the
  // submitted Decision Model triple. No server problem carries this code —
  // it exists because a 2xx alone must not be reported as "configured".
  'ai_config.decision_not_persisted' => l10n.aiConfigDecisionNotPersisted,
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

/// True when the backend denied the call on the credential-role gate (issue
/// #470's scoped 403 arms: `ai-config.forbidden` for AI-config
/// management/discovery, `settings.forbidden` for settings credentials).
/// A scoped authorization denial is NOT a retryable load error — retrying
/// cannot flip a role — so the UI renders the "administrator role
/// required" narrative ([aiConfigErrorCopy]) WITHOUT a retry affordance.
bool isAiConfigAuthzDenied(ProblemError error) =>
    error.code == 'ai-config.forbidden' ||
    error.code == 'settings.forbidden' ||
    // Issue #816: the client-detected mirror of the same predicate.
    error.code == kAiConfigCapabilityDeniedCode;

/// True when [error] says the backend produced NO answer at all (issue #809):
/// a transport-level failure — connection refused/DNS (`connectionError`), a
/// connect/send/receive timeout, or an unclassified transport failure
/// (`unknown`). Those stable codes come from `problemErrorFromDio`.
///
/// This is deliberately NOT `transport.*` as a whole: `transport.badResponse`
/// means the backend DID answer with something unusable, which is a different
/// fact (the generic discovery-error card is honest for it). The distinction
/// matters because a failed read must never be rendered as "no configuration
/// exists", and an unreachable backend must never look like a permission
/// problem.
bool isBackendUnreachable(ProblemError error) => switch (error.code) {
  'transport.connectionError' ||
  'transport.connectionTimeout' ||
  'transport.sendTimeout' ||
  'transport.receiveTimeout' ||
  'transport.unknown' => true,
  _ => false,
};
