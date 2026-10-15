// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_providers.dart';
import '../../auth/active_block.dart';
import '../../auth/membership/membership_providers.dart';
import '../auth/sign_out.dart';
import '../../data/settings/api_base_validation.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../data/settings/easter_eggs_store.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../ai_import/ai_config/ai_config_screen.dart';
import '../ai_import/clippy/clippy_trigger.dart';
import '../ai_import/clippy/karl_kleiderbuegel_figure.dart';
import '../easter_eggs/dejavu_cat.dart';

/// Full-screen settings (issue #516, capability `flutter-settings-screen`):
/// replaces the former `SettingsDialog` — pushed from the profile menu's
/// "Einstellungen" tile, back via AppBar.
///
/// Two clearly separated sections:
/// - **General app settings** (every flavor): the per-egg Easter-Eggs
///   switches (issue #615; default ON, persisted, globally reactive via
///   [easterEggProvider]). A failed preference read falls back to default
///   ON with a visible error state — never a silent failure.
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
          _SectionHeader(label: l10n.settingsGeneral),
          _SectionHeader(label: l10n.settingsEasterEggs),
          Padding(
            key: const Key('settings-easter-eggs-subtitle'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space16,
              0,
              AppSpacing.space16,
              AppSpacing.space8,
            ),
            child: Text(l10n.settingsEasterEggsSubtitle),
          ),
          for (final id in EasterEggId.values) _EggSwitchRow(id: id),
          const Divider(),

          // ── Easter-eggs gallery (issue #640): replay/preview each egg
          //    regardless of month — the preview bypasses only the
          //    October month gate, never the per-egg switch. ─────────
          _SectionHeader(label: l10n.settingsEasterEggsPreview),
          Padding(
            key: const Key('settings-eggs-preview-subtitle'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space16,
              0,
              AppSpacing.space16,
              AppSpacing.space8,
            ),
            child: Text(l10n.settingsEasterEggsPreviewSubtitle),
          ),
          for (final id in EasterEggId.values) _EggPreviewRow(id: id),

          // ── AI (issue #644): a dedicated, always-present section —
          //    the AI-configuration entry (issue #643, role-gated).
          //    Issue #672: the AI-import JOBS entry moved to the account
          //    drawer (`profile-ai-imports`) — the jobs list is the
          //    operational surface users check repeatedly, not a setting;
          //    the redundant Settings tile was removed in favor of the
          //    drawer entry (same route name kept for the apply-outcome
          //    `popUntil` contract).
          _SectionHeader(label: l10n.settingsAi),
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

/// The central AI-configuration entry (issue #643): a tile in the AI
/// section pushing the existing [AiConfigScreen] — no new screen, no new
/// controller, no new API surface.
///
/// AUTHZ-GATE: the AI-config handlers are handler-internally gated by
/// `has_active_credential_role` (an active `costume_designer` /
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

/// Small labeled section header used for "Allgemein", the "Easter eggs" /// group, "KI" (AI section, issue #644) and "Entwicklung" (settings-
/// screen section separation, issue #516/#615).
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

/// One per-egg switch row (issue #615).
///
/// A dedicated [ConsumerWidget] owns the watches for a SINGLE egg, so
/// flipping one egg rebuilds only its own row — never the settings screen
/// or the other egg's row (spec `flutter-easter-eggs`).
class _EggSwitchRow extends ConsumerWidget {
  const _EggSwitchRow({required this.id});

  final EasterEggId id;

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final result = await ref
        .read(easterEggProvider(id).notifier)
        .toggle(EasterEggsStore(SharedPreferencesAsync()));
    // The in-memory flip already happened (global reactivity). A failed
    // persistence is surfaced as an inline error — no silent discard.
    if (!context.mounted) return;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final readFailed = ref.watch(easterEggProvider(id).notifier).readFailed;
    final value = ref.watch(easterEggProvider(id));
    return SwitchListTile(
      key: Key('settings-egg-${id.name}'),
      secondary: Icon(_eggIcon(id)),
      title: Text(_eggTitle(l10n, id)),
      subtitle: readFailed
          ? Text(
              l10n.settingsEasterEggsError,
              key: Key('settings-egg-${id.name}-error'),
            )
          : Text(_eggSubtitle(l10n, id)),
      value: value,
      onChanged: (enabled) => _toggle(context, ref, enabled),
    );
  }
}

/// The localized name of an Easter egg (issue #615).
String _eggTitle(AppLocalizations l10n, EasterEggId id) => switch (id) {
  EasterEggId.karlKleiderbuegel => l10n.settingsEasterEggsKarlKleiderbuegel,
  EasterEggId.dejaVuCat => l10n.settingsEasterEggsDejavuCat,
};

/// One per-egg gallery preview card (issue #640, design decision
/// "Easter-eggs gallery in Settings"): renders the egg's figure as an
/// explicit showcase — **regardless of month** — so every egg is
/// discoverable and testable year-round.
///
/// Gates preserved by construction:
/// - the **per-egg switch** stays the master gate: a switched-off egg
///   renders no preview (the row watches the same
///   [easterEggProvider] family member, so a flip appears/disappears
///   the preview live);
/// - the system **"remove animations"** setting renders the static
///   pose — no controller runs (same rule as the live surfaces).
///
/// The October month gate is deliberately NOT applied here — bypassing
/// it is the gallery's entire purpose (issue #640). The gate itself is
/// untouched on the live surfaces ([DejaVuCatOverlay]).
class _EggPreviewRow extends ConsumerWidget {
  const _EggPreviewRow({required this.id});

  final EasterEggId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(easterEggProvider(id));
    if (!enabled) return const SizedBox.shrink();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return Padding(
      key: Key('settings-egg-preview-${id.name}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space16,
        0,
        AppSpacing.space16,
        AppSpacing.space8,
      ),
      child: Card(
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: Center(
            child: switch (id) {
              EasterEggId.karlKleiderbuegel => KarlKleiderbuegelFigure(
                pose: ClippyPose.neutral,
                animate: !disableAnimations,
              ),
              // The walker paints the cat along the lower band of its
              // box (y = height − 72 − cat height); 150 logical px keep
              // the full silhouette inside the card.
              EasterEggId.dejaVuCat => DejaVuCatWalker(
                key: const Key('settings-egg-preview-dejavu-cat'),
                animate: !disableAnimations,
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// The localized short description of an Easter egg (issue #615).
String _eggSubtitle(AppLocalizations l10n, EasterEggId id) => switch (id) {
  EasterEggId.karlKleiderbuegel =>
    l10n.settingsEasterEggsKarlKleiderbuegelSubtitle,
  EasterEggId.dejaVuCat => l10n.settingsEasterEggsDejavuCatSubtitle,
};

/// The row icon of an Easter egg (issue #615).
IconData _eggIcon(EasterEggId id) => switch (id) {
  EasterEggId.karlKleiderbuegel => Icons.checkroom,
  EasterEggId.dejaVuCat => Icons.pets_outlined,
};
