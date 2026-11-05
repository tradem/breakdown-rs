// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../data/ai_import_handoff_store.dart';
import '../../../design/components/xml_prompt_editor.dart';
import '../../../design/spacing.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../clippy/clippy_trigger.dart';
import '../cost_format.dart';
import '../clippy/karl_kleiderbuegel_overlay.dart';
import 'ai_config_controller.dart';
import 'ai_config_state.dart';
import '../../../design/components/breakdown_app_bar.dart';

/// The AI-import configuration screen (`flutter-ai-config` task 2.1).
///
/// A `ConsumerStatefulWidget` whose STATE is presentation-only: the two masked
/// key fields' controllers plus the in-flight flag. Every edit is dispatched
/// through [AiConfigController]; all domain branching lives there (AGENTS.md
/// §9). The widgets own the controllers because the sticky action bar must be
/// able to read the typed secrets when it dispatches — they are still never
/// provider state and never persisted (D6).
///
/// Saved-vs-draft discipline (the reported "my Decision Model change was never
/// stored" defect): the form holds DRAFTS, so a save is only real once the
/// primary action runs. The screen therefore keeps that action permanently
/// visible in a bottom action bar (Material 3 persistent primary action for
/// long forms), marks unsaved changes, offers an explicit discard, and guards
/// back-navigation with a Material "discard changes?" dialog instead of
/// silently dropping the draft.
///
/// AUTHZ-GATE exception (D4, documented): no client-side capability
/// pre-gate exists here — the backend's credential-role policy is not a
/// season capability surface. The 403 denial renders the localized
/// "administrator role required" narrative ([aiConfigErrorCopy]); the
/// call itself is denied server-side. This is the ONLY documented
/// exception in the client; uploads/apply remain pre-gated (task 5.1).
class AiConfigScreen extends ConsumerStatefulWidget {
  const AiConfigScreen({super.key});

  @override
  ConsumerState<AiConfigScreen> createState() => _AiConfigScreenState();
}

class _AiConfigScreenState extends ConsumerState<AiConfigScreen> {
  /// Masked replacement secrets (D6): read at dispatch time only.
  final _replacementKeyController = TextEditingController();
  final _decisionKeyController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _replacementKeyController.dispose();
    _decisionKeyController.dispose();
    super.dispose();
  }

  /// Whether the replacement extraction-key field is rendered: the provider
  /// was switched and no credential for the new provider is retained.
  bool _showsReplacementKey(
    AiConfigScreenState state,
    AiImportHandoffState? handoff,
  ) {
    final config = state.config;
    final selectedProviderKey = state.selectedProviderKey;
    if (config == null || selectedProviderKey == null) return false;
    if (selectedProviderKey == config.provider.name) return false;
    return handoff?.credentials.containsKey(selectedProviderKey) != true;
  }

  /// Whether the separate DECISION key field is rendered (issue #723): a
  /// decision provider is picked, same-key reuse does not apply, no decision
  /// credential is remembered, and the stored binding is being replaced.
  bool _showsDecisionKey(
    AiConfigScreenState state,
    AiImportHandoffState? handoff,
  ) {
    final config = state.config;
    final decisionKey = state.selectedDecisionProviderKey;
    if (config == null || decisionKey == null) return false;
    if (decisionKey == state.selectedProviderKey && state.useSameDecisionKey) {
      return false;
    }
    if (handoff?.decisionCredentialFor(decisionKey) != null) return false;
    return config.decisionProvider?.name != decisionKey;
  }

  /// Dispatches the PATCH (edit path). The primary action lives in the sticky
  /// bar, so it is reachable without scrolling to the end of the form — the
  /// missing affordance behind the unsaved Decision Model change.
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(aiConfigControllerProvider.notifier);
      final state = ref.read(aiConfigControllerProvider);
      final handoff = ref.read(aiImportHandoffProvider).value;
      final edited = await controller.edit(
        providerKey: state.selectedProviderKey,
        assistantModelId: state.selectedAssistantModelId,
        imageModelId: state.selectedImageModelId,
        costDisplayPreference: state.costDisplayPreference,
        scriptPrompt: state.scriptPrompt,
        schedulePrompt: state.schedulePrompt,
        replacementSecret: _showsReplacementKey(state, handoff)
            ? _replacementKeyController.text
            : null,
        // Decision Model slot (issue #723): always resolved and sent —
        // including the explicit "disabled" pick, which the tri-state PATCH
        // clears.
        decisionProviderKey: state.selectedDecisionProviderKey,
        decisionModelId: state.selectedDecisionModelId,
        useSameDecisionKey: state.useSameDecisionKey,
        decisionReplacementSecret: _showsDecisionKey(state, handoff)
            ? _decisionKeyController.text
            : null,
      );
      // Explicitly consumed: Err renders the code-keyed banner (controller
      // state); Ok refreshes the discovery list. A committed save retires the
      // typed secrets — the hand-off store remembers their references.
      edited.match<void>((_) {}, (_) {
        _replacementKeyController.clear();
        _decisionKeyController.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Revoke with confirm (the UI owns the confirm dialog); the command carries
  /// the current version (optimistic lock).
  Future<void> _revoke() async {
    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('ai-config-revoke-confirm'),
        title: Text(l10n.aiConfigRevokeTitle),
        content: Text(l10n.aiConfigRevokeBody),
        actions: [
          TextButton(
            key: const Key('ai-config-revoke-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('ai-config-revoke-confirm-yes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.aiConfigRevokeButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final revoked = await ref
          .read(aiConfigControllerProvider.notifier)
          .revoke();
      // Explicitly consumed: the failure surfaces via the code-keyed
      // banner (controller state); success flips the discovery list.
      revoked.match<void>((_) {}, (_) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Discards the draft and re-seeds the form from the stored view (no
  /// command). Also clears the typed secrets, which are part of the draft.
  void _discardChanges() {
    ref.read(aiConfigControllerProvider.notifier).discardDrafts();
    _replacementKeyController.clear();
    _decisionKeyController.clear();
  }

  /// The Material "discard changes?" dialog shown when the user leaves the
  /// screen with unsaved edits. Returns true when the draft may be dropped.
  Future<bool> _confirmDiscard() async {
    final l10n = l10nOf(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('ai-config-unsaved-dialog'),
        title: Text(l10n.aiConfigUnsavedTitle),
        content: Text(l10n.aiConfigUnsavedBody),
        actions: [
          TextButton(
            key: const Key('ai-config-unsaved-keep-editing'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.aiConfigUnsavedKeepEditing),
          ),
          TextButton(
            key: const Key('ai-config-unsaved-discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.aiConfigUnsavedDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    final handoff = ref.watch(aiImportHandoffProvider).value;
    final dirty = state.hasUnsavedChanges;
    final canSave =
        state.selectedAssistantModelId != null &&
        (state.selectedDecisionProviderKey == null ||
            state.selectedDecisionModelId != null);

    // Karl Kleiderbügel flow state (issue #516): first-run (no config) is
    // the classic Clippy trigger; command errors console; otherwise
    // idle. Derived ONLY from this screen's own watched state.
    final clippyState = state.commandError != null
        ? ClippyFlowState.error
        : state.isFirstRun
        ? ClippyFlowState.noConfig
        : ClippyFlowState.idle;

    return PopScope(
      // Leaving with unsaved drafts is the failure mode this screen must not
      // hide: the form holds DRAFTS, so back-navigation without a save is a
      // silent discard of (e.g.) the picked Decision Model. Material's answer
      // for a long form is an explicit "discard changes?" decision, not a
      // dropped draft (this is what made a saved-looking configuration never
      // reach the backend).
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, Object? result) async {
        if (didPop) return;
        final mayLeave = await _confirmDiscard();
        if (!mayLeave || !context.mounted) return;
        _discardChanges();
        Navigator.of(context).pop(result);
      },
      child: Scaffold(
        appBar: BreakdownAppBar(title: l10nOf(context).aiConfigTitle),
        // Material 3 persistent primary action: the save affordance of a long
        // form stays visible instead of scrolling with the content, and it
        // states whether there is anything to save.
        bottomNavigationBar: state.config == null
            ? null
            : _ConfigActionBar(
                dirty: dirty,
                busy: _busy,
                canSave: canSave,
                onSave: _save,
                onDiscard: _discardChanges,
              ),
        body: KarlKleiderbuegelOverlay(
          flowState: clippyState,
          child: ListView(
            key: const Key('ai-config-screen'),
            padding: const EdgeInsets.all(16),
            children: [
              // Admin-facing AI-literacy helper (EU AI Act Art. 4, issue
              // #538): persistent ABOVE the forms in BOTH the first-run and
              // configured states — what the configuration controls, whose
              // data the configured provider processes, and the duty to
              // configure honestly. Catalog copy only (inline-copy gate).
              _LiteracyCard(),
              if (state.unresolved != null)
                _UnresolvedCard(
                  unresolved: state.unresolved!,
                  onRecheck: controller.recheckUnresolved,
                  onCleanup: controller.cleanupUnresolved,
                ),
              if (state.commandError != null)
                _Banner(
                  key: const Key('ai-config-error-banner'),
                  text: aiConfigErrorCopy(l10nOf(context), state.commandError!),
                  onDismiss: controller.dismissCommandError,
                ),
              if (state.discoveryError != null && state.config == null)
                if (isAiImportDisabled(state.discoveryError!))
                  // Feature disabled on this instance (wire code
                  // `ai-import.disabled`, issue #422): NOT a load failure —
                  // retrying cannot fix a server configuration flag. Dedicated
                  // honest state WITHOUT a retry affordance.
                  Card(
                    key: const Key('ai-config-disabled'),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space12),
                      child: Text(
                        aiConfigErrorCopy(
                          l10nOf(context),
                          state.discoveryError!,
                        ),
                      ),
                    ),
                  )
                else if (isAiConfigAuthzDenied(state.discoveryError!))
                  // Scoped credential-role denial (issue #470 wire arms —
                  // surfaced centrally via the Settings entry, issue #643):
                  // a 403 is a DENIAL, not a load failure — the "administrator
                  // role required" narrative ([aiConfigErrorCopy]) WITHOUT a
                  // retry affordance (retrying cannot flip a role).
                  Card(
                    key: const Key('ai-config-discovery-forbidden'),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space12),
                      child: Text(
                        aiConfigErrorCopy(
                          l10nOf(context),
                          state.discoveryError!,
                        ),
                      ),
                    ),
                  )
                else if (isBackendUnreachable(state.discoveryError!))
                  // No answer at all (issue #809): the backend is not
                  // reachable yet — the normal state right after an API
                  // restart or a dev data reset. Dedicated, localized state
                  // with a Retry: a failed read is NOT "no configuration
                  // exists" (and must never read like a permission
                  // problem). Same wording the Settings entry renders, so
                  // the entry and the screen cannot disagree.
                  Card(
                    key: const Key('ai-config-backend-unreachable'),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            key: const Key(
                              'ai-config-backend-unreachable-title',
                            ),
                            l10nOf(context).aiConfigBackendUnreachableTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSpacing.space4),
                          Text(l10nOf(context).aiConfigBackendUnreachableBody),
                          const SizedBox(height: AppSpacing.space8),
                          OutlinedButton(
                            key: const Key(
                              'ai-config-backend-unreachable-retry',
                            ),
                            onPressed: controller.refresh,
                            child: Text(l10nOf(context).commonRetry),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Failed discovery is NOT "no config exists": rendering the
                  // first-run form here would let the user create a SECOND
                  // credential. The honest state is a retry affordance.
                  Card(
                    key: const Key('ai-config-discovery-error'),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10nOf(context).aiConfigDiscoveryError(
                              state.discoveryError!.code,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            key: const Key('ai-config-discovery-retry'),
                            onPressed: controller.refresh,
                            child: Text(l10nOf(context).commonRetry),
                          ),
                        ],
                      ),
                    ),
                  )
              else if (state.isFirstRun)
                _FirstRunForm(state: state)
              else
                _ConfiguredForm(
                  state: state,
                  replacementKeyController: _replacementKeyController,
                  decisionKeyController: _decisionKeyController,
                  showReplacementKey: _showsReplacementKey(state, handoff),
                  showDecisionKey: _showsDecisionKey(state, handoff),
                  busy: _busy,
                  onRevoke: _revoke,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Literacy helper ---------------------------------------------------------

/// The persistent AI-literacy helper card (spec `flutter-ai-config` delta
/// "Admin AI-literacy helper text", issue #538): `tertiaryContainer`
/// surface so it reads as explanatory framing, not as a form error.
class _LiteracyCard extends StatelessWidget {
  const _LiteracyCard();

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('ai-config-literacy'),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.space8),
              Expanded(
                child: Text(
                  key: const Key('ai-config-literacy-title'),
                  l10nOf(context).aiConfigLiteracyTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            key: const Key('ai-config-literacy-body'),
            l10nOf(context).aiConfigLiteracyBody,
          ),
        ],
      ),
    ),
  );
}

// --- First-run form ----------------------------------------------------------

/// The first-run flow: provider picker → model pickers → masked key →
/// prompts → create. The masked key lives ONLY in this widget's
/// [TextEditingController] (D6 — no provider state, no storage).
class _FirstRunForm extends ConsumerStatefulWidget {
  const _FirstRunForm({required this.state});

  final AiConfigScreenState state;

  @override
  ConsumerState<_FirstRunForm> createState() => _FirstRunFormState();
}

class _FirstRunFormState extends ConsumerState<_FirstRunForm> {
  final _keyController = TextEditingController();
  final _decisionKeyController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _keyController.dispose();
    _decisionKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final secret = _keyController.text;
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('ai-config-key-missing'),
          content: Text(l10nOf(context).aiConfigKeyMissing),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // The secret is read from the field at submit time and handed to
      // the controller as a parameter — it never enters provider state.
      final created = await ref
          .read(aiConfigControllerProvider.notifier)
          .create(
            secret: secret,
            // The split-billing decision key (issue #723): only read when
            // the separate-key field is rendered; null otherwise.
            decisionSecret: _showsDecisionKeyField
                ? _decisionKeyController.text
                : null,
          );
      // Explicitly consumed: Err is already surfaced by the screen's
      // code-keyed banner (controller state); Ok is already visible as
      // the configured view — neither branch needs a local reaction.
      created.match<void>((_) {}, (_) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether the separate decision API-key field is rendered (issue #723):
  /// a decision provider is picked, the same-key toggle does NOT apply
  /// (different provider, or the toggle is off), and no decision
  /// credential is remembered for that provider.
  bool get _showsDecisionKeyField {
    final state = ref.read(aiConfigControllerProvider);
    final decisionKey = state.selectedDecisionProviderKey;
    if (decisionKey == null) return false;
    if (decisionKey == state.selectedProviderKey && state.useSameDecisionKey) {
      return false;
    }
    final handoff = ref.read(aiImportHandoffProvider).value;
    return handoff?.decisionCredentialFor(decisionKey) == null;
  }

  /// Non-blocking provenance hint (issue #471): shown only when the prompt
  /// defaults have actually loaded (the fields are prefilled — editable). A
  /// failed defaults fetch degrades to empty fields WITHOUT this hint — no
  /// error card, the user simply types by hand.
  Widget _prefillCaption(AsyncValue<AiImportDefaults>? promptDefaults) {
    if (promptDefaults case AsyncData(:final value)) {
      if (value.script.isNotEmpty && value.schedule.isNotEmpty) {
        return Text(
          l10nOf(context).aiConfigPrefillHint,
          key: const Key('ai-prefill-hint'),
          style: const TextStyle(fontSize: 12),
        );
      }
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiConfigControllerProvider);
    return Column(
      key: const Key('ai-config-first-run'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10nOf(context).aiConfigNotConfigured,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(l10nOf(context).aiConfigFirstRunBody),
        const SizedBox(height: 16),
        const _ProviderPicker(),
        const SizedBox(height: 16),
        const _ModelPickers(),
        const SizedBox(height: 16),
        const _DecisionSection(),
        const SizedBox(height: 16),
        const _CostDisplayPreferenceSelector(),
        const SizedBox(height: 16),
        TextField(
          key: const Key('ai-api-key-field'),
          controller: _keyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const <String>[],
          decoration: InputDecoration(
            labelText: l10nOf(context).aiConfigApiKeyLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _DecisionKeyField(
          controller: _decisionKeyController,
          visible: _showsDecisionKeyField,
        ),
        const SizedBox(height: 16),
        _PromptFields(
          scriptKey: 'ai-script-prompt',
          scheduleKey: 'ai-schedule-prompt',
        ),
        const SizedBox(height: 4),
        _prefillCaption(state.promptDefaults),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('ai-config-create'),
          onPressed: _busy
              ? null
              : (state.selectedProviderKey != null &&
                        state.selectedAssistantModelId != null &&
                        (state.selectedDecisionProviderKey == null ||
                            state.selectedDecisionModelId != null)
                    ? _submit
                    : null),
          child: Text(l10nOf(context).aiConfigSaveConfiguration),
        ),
      ],
    );
  }
}

/// Provider picker (D7): reads the discovery routes; every degraded state
/// is honest (loading spinner, error retry, empty list copy) — never an
/// empty picker masquerading as "no providers exist".
class _ProviderPicker extends ConsumerWidget {
  const _ProviderPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    return switch (state.providers) {
      AsyncData(:final value) =>
        value.isEmpty
            ? Text(
                key: const Key('ai-providers-empty'),
                l10nOf(context).aiConfigNoProviders,
              )
            : DropdownButtonFormField<String>(
                key: const Key('ai-provider-picker'),
                initialValue: state.selectedProviderKey,
                decoration: InputDecoration(
                  labelText: l10nOf(context).aiConfigProviderLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final info in value)
                    DropdownMenuItem<String>(
                      value: info.key,
                      child: Text(info.key),
                    ),
                ],
                onChanged: (key) {
                  if (key != null) controller.selectProvider(key);
                },
              ),
      AsyncError(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: const Key('ai-providers-degraded'),
            error is ProblemError && isAiImportDisabled(error)
                ? aiConfigErrorCopy(l10nOf(context), error)
                : error is ProblemError && error.status == 404
                ? aiConfigErrorCopy(l10nOf(context), error)
                : l10nOf(context).aiConfigProvidersUnavailable,
          ),
          // The disabled state is a server configuration, not a transient
          // failure (issue #422): no retry affordance — retrying cannot
          // flip the backend's feature flag.
          if (!(error is ProblemError && isAiImportDisabled(error)))
            TextButton(
              key: const Key('ai-providers-retry'),
              onPressed: controller.refresh,
              child: Text(l10nOf(context).commonRetry),
            ),
        ],
      ),
      _ => const SizedBox(
        key: Key('ai-providers-loading'),
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }
}

/// Assistant/image model pickers fed by the selected provider's model
/// route. A 422 (unknown provider) renders the "provider unavailable"
/// copy and the flow cannot proceed (honest degradation).
class _ModelPickers extends ConsumerWidget {
  const _ModelPickers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    if (state.selectedProviderKey == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The ASSISTANT catalog's honest states (loading / degraded).
        // Rendered INDEPENDENTLY of the image picker below (CodeRabbit
        // review, PR #734): an assistant-catalog failure must not hide the
        // image picker — a user editing an existing configuration can
        // still change or clear its image model while the assistant
        // catalog is degraded.
        switch (state.models) {
          AsyncData(:final value) => DropdownButtonFormField<String>(
            key: const Key('ai-assistant-model-picker'),
            initialValue: state.selectedAssistantModelId,
            // Two-line items (model name + pricing signal, issue #675):
            // the default 48 px item height would overflow the column.
            itemHeight: 72,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10nOf(context).aiConfigAssistantModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              if (state.selectedAssistantModelId != null &&
                  !value.any(
                    (model) => model.id == state.selectedAssistantModelId,
                  ))
                DropdownMenuItem<String>(
                  value: state.selectedAssistantModelId,
                  child: Text(state.selectedAssistantModelId!),
                ),
              for (final model in value)
                DropdownMenuItem<String>(
                  value: model.id,
                  child: Column(
                    key: Key('ai-assistant-model-item-${model.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(model.displayName ?? model.id),
                      _modelPriceCaption(model, l10nOf(context)),
                    ],
                  ),
                ),
            ],
            // The CLOSED field shows the one-line model name; the two-line
            // column (name + pricing signal) is menu-only (the closed
            // display is height-constrained to the input's inner box).
            selectedItemBuilder: (context) => [
              if (state.selectedAssistantModelId != null &&
                  !value.any(
                    (model) => model.id == state.selectedAssistantModelId,
                  ))
                Text(state.selectedAssistantModelId!),
              for (final model in value) Text(model.displayName ?? model.id),
            ],
            onChanged: (id) {
              if (id != null) controller.selectAssistantModel(id);
            },
          ),
          AsyncError(:final error) => Text(
            key: const Key('ai-models-degraded'),
            error is ProblemError && error.status == 422
                ? l10nOf(context).aiConfigProviderUnavailable
                : l10nOf(context).aiConfigModelCatalogUnavailable,
          ),
          _ => const SizedBox(
            key: Key('ai-models-loading'),
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        },
        const SizedBox(height: 12),
        // The IMAGE-generation catalog (issue #732): its own route and
        // picker — NOT the assistant list — and independent of the
        // assistant catalog's loading/error state.
        _ImageModelPicker(state: state, controller: controller),
      ],
    );
  }
}

/// The image-generation model picker fed by the selected provider's
/// dedicated image-models route (issue #732) — a distinct catalog from the
/// assistant list. An EMPTY catalog (a text-only provider) collapses the
/// picker to just "— none —" with a greyed-out
/// field and a hint — honest degradation, never the LLM list (the pre-#732
/// bug). Same honest loading/degraded states as the assistant picker.
class _ImageModelPicker extends ConsumerWidget {
  const _ImageModelPicker({required this.state, required this.controller});

  final AiConfigScreenState state;
  final AiConfigController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = state.imageModels;
    return switch (value) {
      AsyncData(value: final models) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            key: const Key('ai-image-model-picker'),
            initialValue: state.selectedImageModelId,
            // Two-line items (model name + pricing signal, issue #675).
            itemHeight: 72,
            isExpanded: true,
            // Greyed out when the provider offers no image models — but
            // still clearable if a stale configured value lingers (the
            // "— none —" entry stays selectable). A null `onChanged`
            // disables the dropdown (greyed out) — `DropdownButtonFormField`
            // has no separate `enabled` flag.
            onChanged: (models.isNotEmpty || state.selectedImageModelId != null)
                ? (id) => controller.selectImageModel(id)
                : null,
            decoration: InputDecoration(
              labelText: l10nOf(context).aiConfigImageModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10nOf(context).aiConfigNoModel),
              ),
              if (state.selectedImageModelId != null &&
                  !models.any(
                    (model) => model.id == state.selectedImageModelId,
                  ))
                DropdownMenuItem<String?>(
                  value: state.selectedImageModelId,
                  child: Text(state.selectedImageModelId!),
                ),
              for (final model in models)
                DropdownMenuItem<String?>(
                  value: model.id,
                  child: Column(
                    key: Key('ai-image-model-item-${model.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(model.displayName ?? model.id),
                      _modelPriceCaption(model, l10nOf(context)),
                    ],
                  ),
                ),
            ],
            // Menu-only two-line items — see the assistant picker above.
            selectedItemBuilder: (context) => [
              Text(l10nOf(context).aiConfigNoModel),
              if (state.selectedImageModelId != null &&
                  !models.any(
                    (model) => model.id == state.selectedImageModelId,
                  ))
                Text(state.selectedImageModelId!),
              for (final model in models) Text(model.displayName ?? model.id),
            ],
          ),
          if (models.isEmpty)
            Text(
              key: const Key('ai-image-models-none'),
              l10nOf(context).aiConfigNoImageModels,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      AsyncError(:final error) => Text(
        key: const Key('ai-image-models-degraded'),
        error is ProblemError && error.status == 422
            ? l10nOf(context).aiConfigProviderUnavailable
            : l10nOf(context).aiConfigModelCatalogUnavailable,
      ),
      _ => const SizedBox(
        key: Key('ai-image-models-loading'),
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }
}

/// The pricing signal caption under/next to one model in a picker
/// (issue #675): formatted input/output token rates per 1M tokens (plus
/// the energy rate when the provider offers one), or the localized
/// "Unknown" copy when `pricing == null` — NEVER a fabricated `$0.00`.
/// Image-generation models carry their rates in the IMAGE-specific
/// fields (`imageNanoPerUnit` flat-per-image, `imageOutputNanoPerMillion`
/// per 1M image-output tokens) with zero token rates — the applicable
/// image rate is rendered instead (CodeRabbit review, PR #734), never a
/// misleading `$0 → $0` token caption.
Widget _modelPriceCaption(ModelInfo model, AppLocalizations l10n) {
  final style = TextStyle(fontSize: 12, color: Colors.grey.shade600);
  final pricing = model.pricing;
  if (pricing == null) {
    return Text(
      l10n.commonUnknown,
      key: Key('ai-model-price-unknown-${model.id}'),
      style: style,
    );
  }
  final currency = pricing.currency;
  final imageUnitRate = pricing.imageNanoPerUnit;
  final imageOutputRate = pricing.imageOutputNanoPerMillion;
  final String rate;
  if (imageUnitRate != null) {
    rate = l10n.aiModelImageUnitRate(
      formatNanoCurrency(imageUnitRate, currency),
    );
  } else if (imageOutputRate != null) {
    rate = l10n.aiModelImageOutputRate(
      formatNanoCurrency(imageOutputRate, currency),
    );
  } else {
    rate = l10n.aiModelPriceInOut(
      formatNanoCurrency(pricing.inputNanoPerMillion, currency),
      formatNanoCurrency(pricing.outputNanoPerMillion, currency),
    );
  }
  final energyRate = pricing.energyNanoPerKwh;
  return Text(
    energyRate == null
        ? rate
        : '$rate · ${l10n.aiModelEnergyRate(formatNanoCurrency(energyRate, currency))}',
    key: Key('ai-model-price-${model.id}'),
    style: style,
  );
}

/// The preferred-primary-cost selector (issue #675): `token` vs `energy`.
/// A SegmentedButton — the default (`token`) is preselected on first run
/// and echoes the configured value otherwise; the selection is drafted
/// in the controller and carried by create/PATCH.
class _CostDisplayPreferenceSelector extends ConsumerWidget {
  const _CostDisplayPreferenceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    final l10n = l10nOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aiConfigCostDisplayLabel),
        const SizedBox(height: 8),
        SegmentedButton<CostDisplayPreference>(
          key: const Key('ai-cost-display-picker'),
          segments: [
            ButtonSegment(
              value: CostDisplayPreference.token,
              label: Text(
                l10n.aiConfigCostDisplayToken,
                key: const Key('ai-cost-display-token'),
              ),
            ),
            ButtonSegment(
              value: CostDisplayPreference.energy,
              label: Text(
                l10n.aiConfigCostDisplayEnergy,
                key: const Key('ai-cost-display-energy'),
              ),
            ),
          ],
          selected: {state.costDisplayPreference},
          onSelectionChanged: (selection) {
            final preference = selection.first;
            controller.selectCostDisplayPreference(preference);
          },
        ),
      ],
    );
  }
}

/// The optional Decision / Scoring Model section (issue #723): provider
/// picker (the route's decision-capable providers + the explicit "disabled"
/// entry), model picker from that provider's curated catalog, and the
/// "Use same API key as extraction" toggle shown when the decision
/// provider matches the extraction provider.
///
/// The decision-capable set is NOT mirrored client-side (issue #736): every
/// `GET /ai-import/providers` row carries the backend-decided
/// `decisionCapable` flag, so a provider the backend adds or drops is
/// advertised here immediately instead of drifting against a hardcoded
/// allowlist.
class _DecisionSection extends ConsumerWidget {
  const _DecisionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    final l10n = l10nOf(context);
    final decisionKey = state.selectedDecisionProviderKey;
    final sameProvider =
        decisionKey != null && decisionKey == state.selectedProviderKey;
    // The discovered providers (empty while loading / degraded) and the
    // subset the backend reports as decision-capable — the picker's only
    // source for its provider entries. `decisionCapable` is nullable on the
    // wire, so a backend that predates the flag (an old server behind a new
    // client) reads as NOT capable instead of failing the whole provider list
    // (CodeRabbit review).
    final discovered = switch (state.providers) {
      AsyncData(:final value) => value,
      _ => const <AiProviderInfo>[],
    };
    bool isDecisionCapable(AiProviderInfo info) =>
        info.decisionCapable ?? false;
    final capableKeys = {
      for (final info in discovered)
        if (isDecisionCapable(info)) info.key,
    };
    final handoff = ref.watch(aiImportHandoffProvider);
    final rememberedDecision = decisionKey == null
        ? null
        : handoff.value?.decisionCredentialFor(decisionKey);
    return Column(
      key: const Key('ai-decision-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiConfigDecisionSectionTitle,
          key: const Key('ai-decision-section-title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.aiConfigDecisionHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const Key('ai-decision-provider-picker'),
          initialValue: decisionKey,
          decoration: InputDecoration(
            labelText: l10n.aiConfigDecisionProviderLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              key: const Key('ai-decision-provider-disabled'),
              child: Text(l10n.aiConfigDecisionDisabled),
            ),
            ...[
              for (final info in discovered)
                if (isDecisionCapable(info))
                  DropdownMenuItem<String?>(
                    value: info.key,
                    key: Key('ai-decision-provider-${info.key}'),
                    child: Text(info.key),
                  ),
            ],
            // A stored decision provider the route no longer reports as
            // decision-capable (a backend capability change, or the
            // provider list still loading) must still render — without this
            // item the Dropdown asserts on the unknown initialValue
            // (CodeRabbit review coverage). Guarded by [capableKeys] so the
            // fallback can never duplicate a rendered entry.
            if (decisionKey != null && !capableKeys.contains(decisionKey))
              DropdownMenuItem<String?>(
                value: decisionKey,
                key: Key('ai-decision-provider-$decisionKey'),
                child: Text(decisionKey),
              ),
          ],
          onChanged: (key) => controller.selectDecisionProvider(key),
        ),
        if (decisionKey != null) ...[
          const SizedBox(height: 12),
          _DecisionModelPicker(state: state, controller: controller),
          if (sameProvider)
            CheckboxListTile(
              key: const Key('ai-decision-same-key-toggle'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: state.useSameDecisionKey,
              onChanged: (checked) =>
                  controller.setUseSameDecisionKey(checked ?? true),
              title: Text(l10n.aiConfigDecisionSameKey),
            ),
          if (!sameProvider && rememberedDecision != null)
            Text(
              key: Key('ai-decision-key-remembered-$decisionKey'),
              l10n.aiConfigDecisionKeyRemembered(decisionKey),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}

/// The decision model picker fed by the selected decision provider's
/// model route (issue #723). Same honest degradation as the extraction
/// pickers (loading / "provider unavailable"), which issue #731 fix point 4
/// demands EXPLICITLY: a 422 (unknown provider) on the decision-models route
/// renders the "Provider unavailable" copy, every other failure the generic
/// catalog copy — byte-identical semantics to the assistant and image
/// pickers, so the three catalogs cannot drift apart again.
class _DecisionModelPicker extends ConsumerWidget {
  const _DecisionModelPicker({required this.state, required this.controller});

  final AiConfigScreenState state;
  final AiConfigController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = state.decisionModels;
    return switch (value) {
      AsyncData(value: final models) => DropdownButtonFormField<String>(
        key: const Key('ai-decision-model-picker'),
        initialValue: state.selectedDecisionModelId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10nOf(context).aiConfigDecisionModelLabel,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (state.selectedDecisionModelId != null &&
              !models.any((model) => model.id == state.selectedDecisionModelId))
            DropdownMenuItem<String>(
              value: state.selectedDecisionModelId,
              child: Text(state.selectedDecisionModelId!),
            ),
          for (final model in models)
            DropdownMenuItem<String>(
              value: model.id,
              key: Key('ai-decision-model-item-${model.id}'),
              child: Text(model.displayName ?? model.id),
            ),
        ],
        onChanged: (id) {
          if (id != null) controller.selectDecisionModel(id);
        },
      ),
      AsyncError(:final error) => Text(
        key: const Key('ai-decision-models-degraded'),
        // 422 = the provider key is unknown/not decision-capable → the
        // honest "provider unavailable" copy (issue #731 fix point 4); any
        // other failure is a catalog/transport problem. Mirrors the
        // assistant (`ai-models-degraded`) and image
        // (`ai-image-models-degraded`) pickers exactly.
        error is ProblemError && error.status == 422
            ? l10nOf(context).aiConfigProviderUnavailable
            : l10nOf(context).aiConfigModelCatalogUnavailable,
      ),
      _ => const SizedBox(
        key: Key('ai-decision-models-loading'),
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }
}

/// The masked separate decision API-key field (issue #723). Rendered only
/// when the decision credential cannot be reused (different provider, or
/// the same-key toggle is off) and none is remembered — the secret is a
/// submit-time parameter only (D6).
class _DecisionKeyField extends StatelessWidget {
  const _DecisionKeyField({required this.controller, required this.visible});

  final TextEditingController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return TextField(
      key: const Key('ai-decision-api-key-field'),
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const <String>[],
      decoration: InputDecoration(
        labelText: l10nOf(context).aiConfigDecisionApiKeyLabel,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Per-document-kind prompt drafts (script/schedule), backed by the
/// controller's draft store. The editor source text is the same value sent
/// to create/update — syntax spans are presentation-only.
///
/// Each field also reports whether the SERVER has a stored override for that
/// kind, because a stored prompt does NOT follow the deployment default (the
/// observed failure mode was a config silently ignoring a hardened default).
/// The reset writes the current deployment text from
/// `GET /v1/ai-import/defaults` into the draft; saving it stores that text
/// explicitly. Clearing the field instead removes the override entirely, and
/// the server then falls back to its default on every run.
class _PromptFields extends ConsumerWidget {
  const _PromptFields({required this.scriptKey, required this.scheduleKey});

  final String scriptKey;
  final String scheduleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    // `null` = a server that predates the field: no indication is claimed
    // rather than asserting "no override" from missing information.
    final stored = state.config?.storedPromptKinds;
    final scriptDefault = state.promptDefaultFor(DocumentKind.script);
    final scheduleDefault = state.promptDefaultFor(DocumentKind.schedule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XmlPromptEditor(
          key: Key(scriptKey),
          text: state.scriptPrompt,
          label: l10nOf(context).aiConfigScriptPromptLabel,
          onChanged: controller.setScriptPrompt,
        ),
        _PromptOverrideRow(
          kind: DocumentKind.script,
          storedKinds: stored,
          hasDefault: scriptDefault != null,
          onReset: () => controller.setScriptPrompt(scriptDefault ?? ''),
        ),
        const SizedBox(height: AppSpacing.space12),
        XmlPromptEditor(
          key: Key(scheduleKey),
          text: state.schedulePrompt,
          label: l10nOf(context).aiConfigSchedulePromptLabel,
          onChanged: controller.setSchedulePrompt,
        ),
        _PromptOverrideRow(
          kind: DocumentKind.schedule,
          storedKinds: stored,
          hasDefault: scheduleDefault != null,
          onReset: () => controller.setSchedulePrompt(scheduleDefault ?? ''),
        ),
      ],
    );
  }
}

/// The stored-override indication + reset for one prompt kind.
class _PromptOverrideRow extends StatelessWidget {
  const _PromptOverrideRow({
    required this.kind,
    required this.storedKinds,
    required this.hasDefault,
    required this.onReset,
  });

  final DocumentKind kind;

  /// The server's stored-override kinds, or null when the server does not
  /// report them (an older binary).
  final BuiltList<DocumentKind>? storedKinds;
  final bool hasDefault;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (storedKinds == null) return const SizedBox.shrink();
    final l10n = l10nOf(context);
    if (!storedKinds!.contains(kind)) {
      // No override: the deployment default is what every run uses.
      return Text(
        key: Key('ai-prompt-default-in-effect-${kind.name}'),
        l10n.aiConfigDefaultPromptNote,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            key: Key('ai-prompt-stored-note-${kind.name}'),
            l10n.aiConfigStoredPromptNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          // Without the fetched default there is nothing honest to reset TO,
          // so the action is disabled rather than writing an empty prompt.
          key: Key('ai-prompt-reset-${kind.name}'),
          onPressed: hasDefault ? onReset : null,
          child: Text(l10n.aiConfigResetPrompt),
        ),
      ],
    );
  }
}

// --- Configured form ---------------------------------------------------------

/// The configured state: summary, provider replacement picker, model editing,
/// prompt edit (version echo carried by the controller), and revoke-with-confirm.
///
/// The primary save action does NOT live here: it sits in the screen's sticky
/// [_ConfigActionBar] so it is reachable without scrolling (the unsaved Decision
/// Model change this screen used to lose). This widget therefore only renders
/// the fields and forwards the typed secrets through the shared controllers.
class _ConfiguredForm extends StatelessWidget {
  const _ConfiguredForm({
    required this.state,
    required this.replacementKeyController,
    required this.decisionKeyController,
    required this.showReplacementKey,
    required this.showDecisionKey,
    required this.busy,
    required this.onRevoke,
  });

  final AiConfigScreenState state;
  final TextEditingController replacementKeyController;
  final TextEditingController decisionKeyController;
  final bool showReplacementKey;
  final bool showDecisionKey;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final config = state.config!;
    return Column(
      key: const Key('ai-config-configured'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10nOf(context).aiConfigActiveTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('ai-config-active-summary'),
          leading: const Icon(Icons.psychology_alt_outlined),
          title: Text(config.assistantModel),
          subtitle: Text(
            '${l10nOf(context).aiConfigProviderPrefix(config.provider.name)}'
            '${config.imageModel == null ? '' : l10nOf(context).aiConfigImageSuffix(config.imageModel!)}',
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        const _ProviderPicker(),
        if (showReplacementKey) ...[
          const SizedBox(height: AppSpacing.space12),
          TextField(
            key: const Key('ai-config-replacement-api-key-field'),
            controller: replacementKeyController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[],
            decoration: InputDecoration(
              labelText: l10nOf(context).aiConfigApiKeyLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space12),
        const _ModelPickers(),
        const SizedBox(height: AppSpacing.space8),
        const _DecisionSection(),
        const SizedBox(height: AppSpacing.space8),
        _DecisionKeyField(
          controller: decisionKeyController,
          visible: showDecisionKey,
        ),
        const SizedBox(height: AppSpacing.space8),
        const _CostDisplayPreferenceSelector(),
        const SizedBox(height: AppSpacing.space8),
        const _PromptFields(
          scriptKey: 'ai-edit-script-prompt',
          scheduleKey: 'ai-edit-schedule-prompt',
        ),
        const SizedBox(height: AppSpacing.space12),
        OutlinedButton(
          key: const Key('ai-config-revoke'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: busy ? null : onRevoke,
          child: Text(l10nOf(context).aiConfigRevokeButton),
        ),
      ],
    );
  }
}

// --- Sticky action bar -------------------------------------------------------

/// The configured state's Material 3 persistent primary action.
///
/// It exists because the save affordance used to live at the very end of a
/// long, scrolling form: a Decision Model picked in the middle of that form was
/// never persisted whenever the user left without scrolling to (and pressing)
/// the button — the app then looked configured while the aggregate had no such
/// state. A persistent action bar is Material's pattern for exactly this case:
/// the primary action stays reachable, and its neighbourhood states whether
/// there is anything to save ([dirty]) so forgetting the save is visible.
///
/// The primary action stays ENABLED while the form is unchanged: the enable
/// rule mirrors the create form's ("a complete selection may be submitted"),
/// and disabling it on an unchanged form would make the disabled state the
/// single signal for two different conditions — an incomplete selection and
/// "nothing edited" — which is what the explicit [dirty] indicator is for.
class _ConfigActionBar extends StatelessWidget {
  const _ConfigActionBar({
    required this.dirty,
    required this.busy,
    required this.canSave,
    required this.onSave,
    required this.onDiscard,
  });

  final bool dirty;
  final bool busy;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    return Material(
      key: const Key('ai-config-action-bar'),
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space16,
            vertical: AppSpacing.space8,
          ),
          // A `Row` does not constrain its non-flexible children, so the two
          // action labels could neither shrink nor wrap: at a large text scale
          // on a narrow screen they ran past the bar and pushed the primary
          // action off-screen. A `Wrap` bounds every child by the bar width, so
          // a long label wraps INSIDE its button and the actions flow onto a
          // second line instead — the save action stays reachable at any text
          // scale (CodeRabbit review, PR #807).
          child: Wrap(
            // Dirty: indicator left, actions right on one run (and space-free
            // wrapping when the width is tight). Clean: the single primary
            // action keeps its trailing position.
            alignment: dirty ? WrapAlignment.spaceBetween : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.space8,
            runSpacing: AppSpacing.space4,
            children: [
              if (dirty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note,
                      key: const Key('ai-config-unsaved-indicator'),
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    // Flexible: the label wraps inside the remaining width
                    // instead of overflowing the indicator's own row.
                    Flexible(
                      child: Text(
                        l10n.aiConfigUnsavedChanges,
                        key: const Key('ai-config-unsaved-label'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              if (dirty)
                TextButton(
                  key: const Key('ai-config-discard-changes'),
                  onPressed: busy ? null : onDiscard,
                  child: Text(l10n.aiConfigDiscardChanges),
                ),
              FilledButton(
                key: const Key('ai-config-edit-save'),
                onPressed: busy || !canSave ? null : onSave,
                child: Text(l10n.aiConfigSaveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared pieces -----------------------------------------------------------

/// The "configuration state unknown — verify" card (design §2.1 step 7):
/// both actions offered; the credential is never destroyed implicitly.
class _UnresolvedCard extends StatelessWidget {
  const _UnresolvedCard({
    required this.unresolved,
    required this.onRecheck,
    required this.onCleanup,
  });

  final AiConfigUnresolved unresolved;
  final Future<void> Function() onRecheck;
  final Future<void> Function() onCleanup;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('ai-config-unresolved'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10nOf(context).aiConfigUnresolvedTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(l10nOf(context).aiConfigUnresolvedBody),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                key: const Key('ai-config-unresolved-recheck'),
                onPressed: onRecheck,
                child: Text(l10nOf(context).aiConfigRecheck),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('ai-config-unresolved-cleanup'),
                onPressed: onCleanup,
                child: Text(l10nOf(context).aiConfigCleanup),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close, color: scheme.onErrorContainer),
              ),
          ],
        ),
      ),
    );
  }
}
