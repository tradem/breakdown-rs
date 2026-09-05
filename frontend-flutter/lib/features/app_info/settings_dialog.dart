// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../data/settings/api_base_validation.dart';
import '../../design/spacing.dart';
import '../auth/sign_out.dart';

/// Shows the settings dialog (spec `flutter-app-dialogs`, design.md §7).
Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const SettingsDialog(),
);

/// Settings dialog (spec `flutter-app-dialogs`):
/// - always: active API base (read-only) + flavor;
/// - `dev` flavor only: editable backend-URI field with inline validation
///   ([validateApiBase]), save (persist → rebuild → fence → clear →
///   invalidate via [SessionReset.switchBackend], progress surfaced) and
///   reset-to-default ([SessionReset.resetBackendToDefault]);
/// - `prod` flavor: no editor — the active base shows read-only with
///   explanatory copy (store compliance: visible explanation, not a
///   disabled trap).
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late final TextEditingController _uriController;
  String? _fieldError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    final base = ref.read(runtimeApiBaseProvider) ?? config.apiBase;
    _uriController = TextEditingController(text: base);
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  String _effectiveBase() {
    final config = ref.read(appConfigProvider);
    return ref.watch(runtimeApiBaseProvider) ?? config.apiBase;
  }

  void _validateField() {
    final config = ref.read(appConfigProvider);
    final result = validateApiBase(_uriController.text, isDev: config.isDev);
    setState(() {
      _fieldError = result.match((e) => apiBaseValidationCopy(e), (_) => null);
    });
  }

  Future<void> _save() async {
    _validateField();
    if (_fieldError != null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(sessionResetProvider.notifier)
          .switchBackend(_uriController.text);
      final error = result.getLeft().toNullable();
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _fieldError = apiBaseValidationCopy(error);
          _saving = false;
        });
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(sessionResetProvider.notifier)
          .resetBackendToDefault();
      if (!mounted) return;
      final error = result.getLeft().toNullable();
      if (error != null) {
        setState(() {
          _fieldError = apiBaseValidationCopy(error);
        });
      } else {
        _uriController.text = _effectiveBase();
        setState(() => _fieldError = null);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final base = _effectiveBase();
    return AlertDialog(
      key: const Key('settings-dialog'),
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: const Key('settings-base'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Server address'),
              subtitle: Text(base),
            ),
            ListTile(
              key: const Key('settings-flavor'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.science_outlined),
              title: const Text('Flavor'),
              subtitle: Text(config.flavor.name),
            ),
            if (config.isDev) ...[
              const SizedBox(height: AppSpacing.space8),
              TextField(
                key: const Key('settings-uri-field'),
                controller: _uriController,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Backend URI',
                  hintText: 'https://api.example.com',
                  errorText: _fieldError,
                ),
                onChanged: (_) {
                  if (_fieldError != null) _validateField();
                },
              ),
              const SizedBox(height: AppSpacing.space8),
              if (_saving)
                const LinearProgressIndicator(key: Key('settings-progress')),
            ] else
              const Padding(
                key: Key('settings-prod-note'),
                padding: EdgeInsets.only(top: AppSpacing.space8),
                child: Text(
                  'The server address is set by your organization for '
                  'security and cannot be changed here.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (config.isDev)
          TextButton(
            key: const Key('settings-reset'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _saving ? null : _reset,
            child: const Text('Reset'),
          ),
        if (config.isDev)
          FilledButton(
            key: const Key('settings-save'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        TextButton(
          key: const Key('settings-close'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
