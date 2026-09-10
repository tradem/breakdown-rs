// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
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
      appBar: AppBar(title: const Text('AI import configuration')),
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
              text: aiConfigErrorCopy(state.commandError!),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.discoveryError != null && state.config == null)
            // Failed discovery is NOT "no config exists": rendering the
            // first-run form here would let the user create a SECOND
            // credential. The honest state is a retry affordance.
            Card(
              key: const Key('ai-config-discovery-error'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The configuration could not be loaded '
                      '(${state.discoveryError!.code}).',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('ai-config-discovery-retry'),
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
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
        const SnackBar(
          key: Key('ai-config-key-missing'),
          content: Text('Enter the API key first.'),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiConfigControllerProvider);
    return Column(
      key: const Key('ai-config-first-run'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Not configured yet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pick a provider, choose the assistant model and submit your API '
          'key. The key is sent to the server vault and never stored on '
          'this device.',
        ),
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
          decoration: const InputDecoration(
            labelText: 'API key (sent to the server vault)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _PromptFields(
          scriptKey: 'ai-script-prompt',
          scheduleKey: 'ai-schedule-prompt',
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('ai-config-create'),
          onPressed: _busy
              ? null
              : (state.selectedProviderKey != null &&
                        state.selectedAssistantModelId != null
                    ? _submit
                    : null),
          child: const Text('Save configuration'),
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
            ? const Text(
                key: Key('ai-providers-empty'),
                'No AI providers are offered on this backend.',
              )
            : DropdownButtonFormField<String>(
                key: const Key('ai-provider-picker'),
                initialValue: state.selectedProviderKey,
                decoration: const InputDecoration(
                  labelText: 'Provider',
                  border: OutlineInputBorder(),
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
            error is ProblemError && error.status == 404
                ? aiConfigErrorCopy(error)
                : 'Providers could not be loaded.',
          ),
          TextButton(
            key: const Key('ai-providers-retry'),
            onPressed: controller.refresh,
            child: const Text('Retry'),
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
            decoration: const InputDecoration(
              labelText: 'Assistant model',
              border: OutlineInputBorder(),
            ),
            items: [
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
            decoration: const InputDecoration(
              labelText: 'Image model (optional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— none —'),
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
            ? 'Provider unavailable — the model catalog cannot be read.'
            : 'The model catalog could not be loaded.',
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
/// controller's draft store.
class _PromptFields extends ConsumerStatefulWidget {
  const _PromptFields({required this.scriptKey, required this.scheduleKey});

  final String scriptKey;
  final String scheduleKey;

  @override
  ConsumerState<_PromptFields> createState() => _PromptFieldsState();
}

class _PromptFieldsState extends ConsumerState<_PromptFields> {
  TextEditingController? _script;
  TextEditingController? _schedule;
  String? _seededScript;
  String? _seededSchedule;

  @override
  void dispose() {
    _script?.dispose();
    _schedule?.dispose();
    super.dispose();
  }

  /// (Re)creates the controllers when the seeded drafts change EXTERNALLY
  /// (the configured form pre-fills from the fetched view; the first-run
  /// form starts empty). A rebuild driven by the user's own keystrokes
  /// MUST keep the controllers: recreating mid-composition resets the
  /// caret and breaks IME input. Reseed only when the state value differs
  /// from BOTH the seed marker and the controller's current text (an
  /// external change the user did not type).
  void _sync(AiConfigScreenState state) {
    if (_script == null ||
        (_seededScript != state.scriptPrompt &&
            _script!.text != state.scriptPrompt)) {
      _script?.dispose();
      _script = TextEditingController(text: state.scriptPrompt);
      _seededScript = state.scriptPrompt;
    }
    if (_schedule == null ||
        (_seededSchedule != state.schedulePrompt &&
            _schedule!.text != state.schedulePrompt)) {
      _schedule?.dispose();
      _schedule = TextEditingController(text: state.schedulePrompt);
      _seededSchedule = state.schedulePrompt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiConfigControllerProvider);
    _sync(state);
    final controller = ref.read(aiConfigControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: Key(widget.scriptKey),
          controller: _script,
          onChanged: controller.setScriptPrompt,
          decoration: const InputDecoration(
            labelText: 'Script prompt',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        TextField(
          key: Key(widget.scheduleKey),
          controller: _schedule,
          onChanged: controller.setSchedulePrompt,
          decoration: const InputDecoration(
            labelText: 'Schedule prompt',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
      ],
    );
  }
}

// --- Configured form ---------------------------------------------------------

/// The configured state: summary, prompt edit (version echo carried by
/// the controller), and revoke-with-confirm.
class _ConfiguredForm extends ConsumerStatefulWidget {
  const _ConfiguredForm({required this.state});

  final AiConfigScreenState state;

  @override
  ConsumerState<_ConfiguredForm> createState() => _ConfiguredFormState();
}

class _ConfiguredFormState extends ConsumerState<_ConfiguredForm> {
  bool _busy = false;

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('ai-config-revoke-confirm'),
        title: const Text('Revoke configuration?'),
        content: const Text(
          'The AI import configuration is revoked. The server-held API '
          'key is destroyed. Imports you already applied are kept.',
        ),
        actions: [
          TextButton(
            key: const Key('ai-config-revoke-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('ai-config-revoke-confirm-yes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
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
    final config = ref.watch(aiConfigControllerProvider).config!;
    return Column(
      key: const Key('ai-config-configured'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active configuration',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('ai-config-active-summary'),
          leading: const Icon(Icons.psychology_alt_outlined),
          title: Text(config.assistantModel),
          subtitle: Text(
            'Provider: ${config.provider.name}'
            '${config.imageModel == null ? '' : ' · Image: ${config.imageModel}'}',
          ),
        ),
        const SizedBox(height: 8),
        const _PromptFields(
          scriptKey: 'ai-edit-script-prompt',
          scheduleKey: 'ai-edit-schedule-prompt',
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('ai-config-edit-save'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final controller = ref.read(
                      aiConfigControllerProvider.notifier,
                    );
                    final state = ref.read(aiConfigControllerProvider);
                    final edited = await controller.edit(
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
          child: const Text('Save changes'),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('ai-config-revoke'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy ? null : _revoke,
          child: const Text('Revoke configuration'),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuration state unknown — verify',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'The setup may or may not have completed. Nothing was deleted '
            '— re-check, or clean up the server-held key if you are sure '
            'the setup failed.',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                key: const Key('ai-config-unresolved-recheck'),
                onPressed: onRecheck,
                child: const Text('Re-check'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('ai-config-unresolved-cleanup'),
                onPressed: onCleanup,
                child: const Text('Clean up'),
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
