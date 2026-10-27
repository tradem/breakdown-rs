// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/active_block.dart';
import '../../auth/membership/membership_providers.dart';
import '../auth/sign_out.dart';
import '../../data/settings/api_base_validation.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../design/components/section_header.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../ai_import/ai_config/ai_config_screen.dart';
import '../easter_eggs/easter_eggs_screen.dart';

/// Full-screen settings (issue #516, capability `flutter-settings-screen`):
/// replaces the former `SettingsDialog` — pushed from the profile menu's
/// "Einstellungen" tile, back via AppBar.
///
/// Two clearly separated sections:
/// - **General app settings** (every flavor): a single Easter-eggs
///   entry tile (issue #708, analogous to the AI-configuration entry,
///   issue #643) pushing the dedicated [EasterEggsScreen] — the per-egg
///   switches (#615) and the gallery (#640) live there unchanged.
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

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final base = _effectiveBase();
    final l10n = l10nOf(context);

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
          SectionHeader(label: l10n.settingsGeneral),
          // Easter-eggs management (issues #615/#640) moved to the
          // dedicated [EasterEggsScreen] (issue #708); only the entry
          // tile stays — same counter-model as the AI section (#643).
          const _EasterEggsEntryTile(),
          const Divider(),

          // ── AI (issue #644): a dedicated, always-present section —
          //    the AI-configuration entry (issue #643, role-gated).
          //    Issue #672: the AI-import JOBS entry moved to the account
          //    drawer (`profile-ai-imports`) — the jobs list is the
          //    operational surface users check repeatedly, not a setting;
          //    the redundant Settings tile was removed in favor of the
          //    drawer entry (same route name kept for the apply-outcome
          //    `popUntil` contract).
          SectionHeader(label: l10n.settingsAi),
          const _AiConfigEntryTile(),
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
            SectionHeader(label: l10n.settingsDev),
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

/// The central AI-configuration entry (issue #643): a tile in the AI
/// section pushing the existing [AiConfigScreen] — no new screen, no new
/// controller, no new API surface.
///
/// AUTHZ-GATE: the AI-config handlers are handler-internally gated by
/// `has_active_credential_role` (an active `piece_designer` /
/// `costume_assistant` in any active membership — backend
/// `AuthorizationPolicy`). The exact global predicate is not on the
/// wire, so the client mirrors it through the existing D2/D3 resolution
/// chain — the sticky active-block scope's season membership and its
/// backend-computed `hasActiveCostumeRoleInSeason` flag (deliberately
/// wider: it also covers `wardrobe_supervisor`). The tile is offered
/// ONLY while that gate resolves to true: no active-block scope, a
/// pending fetch, a membership error, or a resolved denial render no
/// tile (a pending fetch hides, never denies — D3). A wider-role
/// member admitted by the tile then meets the server's localized 403
/// narrative inside [AiConfigScreen] (its documented D4 exception) —
/// honest degradation, server authoritative, never a bypass.
/// The Easter-eggs entry (issue #708): a tile in the general section
/// pushing the dedicated [EasterEggsScreen] — the per-egg switches
/// (issue #615) and the gallery (issue #640) moved there unchanged,
/// exactly the counter-model of the AI section below (issue #643).
///
/// No membership gate (contrast [_AiConfigEntryTile]): the Easter-eggs
/// preferences are local-only — on-device `shared_preferences`, no
/// network call, no backend authorization surface — so the entry stays
/// as unconditional as the inline sections it replaces.
class _EasterEggsEntryTile extends StatelessWidget {
  const _EasterEggsEntryTile();

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListTile(
      key: const Key('settings-easter-eggs-entry'),
      leading: const Icon(Icons.celebration_outlined),
      title: Text(l10n.settingsEasterEggsEntryTitle),
      subtitle: Text(l10n.settingsEasterEggsEntrySubtitle),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget push (no result consumed), same as the AI-config
      // entry. ListTile keeps the ≥ 48×48 dp target.
      onTap: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const EasterEggsScreen()),
        ),
      ),
    );
  }
}

class _AiConfigEntryTile extends ConsumerWidget {
  const _AiConfigEntryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The sticky scope is the only ambient season context the shell
    // carries; without it the role cannot resolve and the entry hides
    // (show only when the role resolves — issue #643 decision).
    final seasonId = ref.watch(activeBlockProvider)?.seasonId;
    if (seasonId == null) return const SizedBox.shrink();
    final membership = ref.watch(currentMembershipProvider(seasonId));
    // `AsyncValue.value` is null while loading/errored — both hide the
    // tile (D3: a pending fetch disables, never denies).
    if (membership.value?.hasActiveCostumeRoleInSeason != true) {
      return const SizedBox.shrink();
    }
    return ListTile(
      key: const Key('settings-ai-config'),
      leading: const Icon(Icons.psychology_alt_outlined),
      title: Text(l10nOf(context).settingsAiConfig),
      subtitle: Text(l10nOf(context).settingsAiConfigSubtitle),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget push (no result consumed), same as the wizard
      // and import-submit entries. ListTile keeps the ≥ 48×48 dp target.
      onTap: () => unawaited(
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AiConfigScreen())),
      ),
    );
  }
}
