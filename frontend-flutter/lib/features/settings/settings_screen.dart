// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_providers.dart';
import '../auth/sign_out.dart';
import '../../data/settings/api_base_validation.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../data/settings/easter_eggs_store.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';

/// Full-screen settings (issue #516, capability `flutter-settings-screen`):
/// replaces the former `SettingsDialog` — pushed from the Mehr tab's
/// "Einstellungen" tile, back via AppBar.
///
/// Two clearly separated sections:
/// - **General app settings** (every flavor): the Easter-Eggs switch
///   (default ON, persisted, globally reactive via [easterEggsProvider]).
///   A failed preference read falls back to default ON with a visible
///   error state — never a silent failure.
/// - **Entwicklung** (dev flavor only): migration target of the dialog's
///   dev-only content — editable backend URI with inline validation
///   ([validateApiBase]), save (persist → rebuild → invalidate via
///   [SessionReset.switchBackend], progress surfaced) and reset-to-default
///   ([SessionReset.resetBackendToDefault]).
///
/// In `prod` the read-only server address + flavor display remain, with
/// the explanatory store-compliance note — the functional scope matches
/// the previous dialog exactly (migration without feature loss).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
      setState(() {
        _fieldError = error == null ? null : apiBaseValidationCopy(error);
        _saving = false;
      });
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
      setState(() {
        _fieldError = error == null ? null : apiBaseValidationCopy(error);
        _saving = false;
      });
      if (error == null) {
        _uriController.text = _effectiveBase();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleEasterEggs(bool enabled) async {
    final result = await ref
        .read(easterEggsProvider.notifier)
        .toggle(EasterEggsStore(SharedPreferencesAsync()));
    // The in-memory flip already happened (global reactivity). A failed
    // persistence is surfaced as an inline error — no silent discard.
    if (!mounted) return;
    result.match(
      // CodeRabbit fix: localized, code-scoped copy — never the
      // backend-URI validation copy (that maps different codes).
      (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).settingsEasterEggsWriteError)),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final base = _effectiveBase();
    final l10n = l10nOf(context);
    final easterEggsError = ref.watch(easterEggsProvider.notifier).readFailed;
    final easterEggsEnabled = ref.watch(easterEggsProvider);

    return Scaffold(
      key: const Key('settings-screen'),
      appBar: AppBar(
        key: const Key('settings-appbar'),
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        key: const Key('settings-list'),
        children: [
          // ── General app settings (every flavor) ─────────────────────
          _SectionHeader(label: l10n.settingsGeneral),
          SwitchListTile(
            key: const Key('settings-easter-eggs'),
            secondary: const Icon(Icons.celebration_outlined),
            title: Text(l10n.settingsEasterEggs),
            subtitle: easterEggsError
                ? Text(
                    l10n.settingsEasterEggsError,
                    key: const Key('settings-easter-eggs-error'),
                  )
                : Text(l10n.settingsEasterEggsSubtitle),
            value: easterEggsEnabled,
            onChanged: (enabled) => _toggleEasterEggs(enabled),
          ),
          const Divider(),

          // ── Read-only server info (every flavor, as the dialog had) ──
          ListTile(
            key: const Key('settings-base'),
            leading: const Icon(Icons.dns_outlined),
            title: Text(l10n.settingsServerAddress),
            subtitle: Text(base),
          ),
          ListTile(
            key: const Key('settings-flavor'),
            leading: const Icon(Icons.science_outlined),
            title: Text(l10n.settingsFlavor),
            subtitle: Text(config.flavor.name),
          ),

          // ── Development (dev flavor only) ────────────────────────────
          if (config.isDev) ...[
            const SizedBox(height: AppSpacing.space8),
            _SectionHeader(label: l10n.settingsDev),
            TextField(
              key: const Key('settings-uri-field'),
              controller: _uriController,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.settingsBackendUri,
                hintText: 'https://api.example.com',
                errorText: _fieldError,
              ),
              onChanged: (_) {
                if (_fieldError != null) _validateField();
              },
            ),
            Padding(
              key: const Key('settings-dev-actions'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
              child: Row(
                children: [
                  TextButton(
                    key: const Key('settings-reset'),
                    onPressed: _saving ? null : _reset,
                    child: Text(l10n.settingsReset),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('settings-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(l10n.settingsSave),
                  ),
                ],
              ),
            ),
            if (_saving)
              const LinearProgressIndicator(key: Key('settings-progress')),
          ] else
            Padding(
              key: const Key('settings-prod-note'),
              padding: const EdgeInsets.all(AppSpacing.space8),
              child: Text(l10n.settingsProdNote),
            ),
        ],
      ),
    );
  }
}

/// Small labeled section header used for "Allgemein" and "Entwicklung"
/// (settings-screen section separation, issue #516).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space16,
        AppSpacing.space16,
        AppSpacing.space16,
        AppSpacing.space8,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
