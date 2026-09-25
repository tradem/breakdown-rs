// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../design/components/xml_prompt_editor.dart';
import '../../../design/spacing.dart';
import '../../../l10n/app_localizations_provider.dart';
import 'ai_config_controller.dart';
import 'ai_config_state.dart';

/// The AI-import configuration screen (`flutter-ai-config` task 2.1).
///
/// A `ConsumerWidget`: it renders and dispatches only (AGENTS.md §9) —
/// all domain branching lives in [AiConfigController] state. The two
/// text-field forms are `ConsumerStatefulWidget`s on purpose (same carve
/// out as the Create-Season sheet): ephemeral text-editing state is
/// widget state, not domain state.
///
/// AUTHZ-GATE exception (D4, documented): no client-side capability
/// pre-gate exists here — the backend's credential-role policy is not a
/// season capability surface. The 403 denial renders the localized
/// "administrator role required" narrative ([aiConfigErrorCopy]); the
/// call itself is denied server-side. This is the ONLY documented
/// exception in the client; uploads/apply remain pre-gated (task 5.1).
class AiConfigScreen extends ConsumerWidget {
  const AiConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiConfigTitle)),
      body: ListView(
        key: const Key('ai-config-screen'),
        padding: const EdgeInsets.all(16),
        children: [
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
                    aiConfigErrorCopy(l10nOf(context), state.discoveryError!),
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
                        l10nOf(context)
                            .aiConfigDiscoveryError(state.discoveryError!.code),
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
            _ConfiguredForm(state: state),
        ],
      ),
    );
  }
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
  bool _busy = false;

  @override
  void dispose() {
    _keyController.dispose();
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
          .create(secret: secret);
      // Explicitly consumed: Err is already surfaced by the screen's
      // code-keyed banner (controller state); Ok is already visible as
      // the configured view — neither branch needs a local reaction.
      created.match<void>((_) {}, (_) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                        state.selectedAssistantModelId != null
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
  const _ProviderPicker({this.enabled = true});

  /// Configured edits keep the existing provider because the vault key is
  /// provider-bound; new configurations can still choose one.
  final bool enabled;

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
                onChanged: enabled
                    ? (key) {
                        if (key != null) controller.selectProvider(key);
                      }
                    : null,
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
    return switch (state.models) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('ai-assistant-model-picker'),
            initialValue: state.selectedAssistantModelId,
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
                  child: Text(model.displayName ?? model.id),
                ),
            ],
            onChanged: (id) {
              if (id != null) controller.selectAssistantModel(id);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('ai-image-model-picker'),
            initialValue: state.selectedImageModelId,
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
                  !value.any((model) => model.id == state.selectedImageModelId))
                DropdownMenuItem<String?>(
                  value: state.selectedImageModelId,
                  child: Text(state.selectedImageModelId!),
                ),
              for (final model in value)
                DropdownMenuItem<String?>(
                  value: model.id,
                  child: Text(model.displayName ?? model.id),
                ),
            ],
            onChanged: (id) => controller.selectImageModel(id),
          ),
        ],
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
    };
  }
}

/// Per-document-kind prompt drafts (script/schedule), backed by the
/// controller's draft store. The editor source text is the same value sent
/// to create/update — syntax spans are presentation-only.
class _PromptFields extends ConsumerWidget {
  const _PromptFields({required this.scriptKey, required this.scheduleKey});

  final String scriptKey;
  final String scheduleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiConfigControllerProvider);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XmlPromptEditor(
          key: Key(scriptKey),
          text: state.scriptPrompt,
          label: l10nOf(context).aiConfigScriptPromptLabel,
          onChanged: controller.setScriptPrompt,
        ),
        const SizedBox(height: AppSpacing.space12),
        XmlPromptEditor(
          key: Key(scheduleKey),
          text: state.schedulePrompt,
          label: l10nOf(context).aiConfigSchedulePromptLabel,
          onChanged: controller.setSchedulePrompt,
        ),
      ],
    );
  }
}

// --- Configured form ---------------------------------------------------------

/// The configured state: summary, vault-bound provider display, model editing,
/// prompt edit (version echo carried by the controller), and revoke-with-confirm.
class _ConfiguredForm extends ConsumerStatefulWidget {
  const _ConfiguredForm({required this.state});

  final AiConfigScreenState state;

  @override
  ConsumerState<_ConfiguredForm> createState() => _ConfiguredFormState();
}

class _ConfiguredFormState extends ConsumerState<_ConfiguredForm> {
  bool _busy = false;

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
    if (confirmed != true) return;
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiConfigControllerProvider);
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
        const _ProviderPicker(enabled: false),
        const SizedBox(height: AppSpacing.space12),
        const _ModelPickers(),
        const SizedBox(height: AppSpacing.space8),
        const _PromptFields(
          scriptKey: 'ai-edit-script-prompt',
          scheduleKey: 'ai-edit-schedule-prompt',
        ),
        const SizedBox(height: AppSpacing.space12),
        FilledButton(
          key: const Key('ai-config-edit-save'),
          onPressed: _busy || state.selectedAssistantModelId == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final controller = ref.read(
                      aiConfigControllerProvider.notifier,
                    );
                    final state = ref.read(aiConfigControllerProvider);
                    final edited = await controller.edit(
                      providerKey: state.selectedProviderKey,
                      assistantModelId: state.selectedAssistantModelId,
                      imageModelId: state.selectedImageModelId,
                      scriptPrompt: state.scriptPrompt,
                      schedulePrompt: state.schedulePrompt,
                    );
                    // Explicitly consumed: Err renders the
                    // changed-elsewhere copy (controller state); Ok
                    // refreshes the discovery list.
                    edited.match<void>((_) {}, (_) {});
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(l10nOf(context).aiConfigSaveChanges),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('ai-config-revoke'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy ? null : _revoke,
          child: Text(l10nOf(context).aiConfigRevokeButton),
        ),
      ],
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
