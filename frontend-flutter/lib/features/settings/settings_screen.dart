// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/capabilities.dart';
import '../auth/sign_out.dart';
import '../../data/settings/api_base_validation.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../design/components/section_header.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../ai_import/ai_config/ai_config_reachability.dart';
import '../ai_import/ai_config/ai_config_screen.dart';
import '../easter_eggs/easter_eggs_screen.dart';
import '../../design/components/breakdown_app_bar.dart';

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
      appBar: BreakdownAppBar(
        key: const Key('settings-appbar'),
        title: l10n.settingsTitle,
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
          //    the AI-configuration entry (issue #643) is ALWAYS rendered
          //    since issue #809 (its reachability state lives in the
          //    subtitle, never in its presence).
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

/// The central AI-configuration entry (issues #643 / #809): a tile in the AI
/// section pushing the existing [AiConfigScreen] — no new screen, no new
/// controller, no new API surface.
///
/// **Always rendered** (issue #809 supersedes #643's hide-based gate):
/// #643's "a pending fetch hides, never denies" (D3) is right for
/// *acting on domain data* and wrong for a *settings entry point* — hiding
/// is indistinguishable from absence, and it fails exactly in the
/// unknown/stale state (cold start, dev data reset, projector lag) where
/// the user most needs the entry. So the tile never returns
/// `SizedBox.shrink()`; the state it knows is rendered in the subtitle:
///
/// * probe in flight → "Backend wird geprüft…" + spinner;
/// * backend answered   → the ordinary subtitle + chevron;
/// * backend unreachable → "Backend noch nicht erreichbar" + Retry.
///
/// AUTHZ-GATE: the AI-config handlers are handler-internally gated by
/// `has_active_credential_role` (an active `piece_designer` /
/// `costume_assistant` in any active membership — backend
/// `AuthorizationPolicy`). That predicate is deployment-scoped; since issue
/// #816 it IS on the wire (`GET /v1/me/capabilities`), so this tile mirrors
/// it EXACTLY instead of approximating it with the season-scoped signal
/// (which is a superset — it also covers `wardrobe_supervisor` — *and*
/// ambient: a stale scope made it read as a denial). A resolved denial
/// renders "Keine Berechtigung" here, before the tap, and the AI-config
/// discovery dispatch is suppressed in
/// `AiConfigController`'s discovery seam (no request). An UNKNOWN answer
/// (probe in flight, transport failure, 5xx) is never a denial: the server
/// stays authoritative and a real 403 (`ai-config.forbidden` /
/// `settings.forbidden`) still renders its localized narrative inside
/// [AiConfigScreen] — the documented D4 exception, with no retry
/// affordance. Never a bypass, never a hidden entry.
///
/// Reachability comes from [aiConfigReachabilityProvider] — a ONE-SHOT
/// probe over the existing `backendHealthProbeProvider` seam (`GET
/// /v1/health`, public, never throws). No polling: the drawer's health pill
/// owns the periodic poll. A failed read is never rendered as "no
/// configuration exists" (that claim belongs to the screen's resolved
/// state, and only the server may make it).
class _AiConfigEntryTile extends ConsumerWidget {
  const _AiConfigEntryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final reachability = ref.watch(aiConfigReachabilityProvider);
    // Issue #816: the SERVER's own credential predicate, read off the wire
    // (`GET /v1/me/capabilities`) instead of approximated from a season-scoped
    // membership signal — that one is a superset (it also admits
    // `wardrobe_supervisor`) AND ambient (a stale scope read as a denial).
    final capabilities = ref.watch(myCapabilitiesProvider);
    // Unknown is a STATE, never a denial and never an absence: while either
    // probe has not answered (or a defensive error left no value) the tile
    // says so and stays tappable.
    final checking =
        reachability.isLoading ||
        !reachability.hasValue ||
        capabilities.isLoading;
    final unreachable =
        !checking &&
        reachability.value == AiConfigBackendReachability.unreachable;
    // A RESOLVED denial is the only state allowed to say "Keine Berechtigung".
    // An error on the capability read is UNKNOWN, not a denial: a failed read
    // must never put a permission problem in front of a user whose role is
    // intact, and the server stays authoritative on every gated call.
    final denied =
        !checking && !unreachable && (capabilities.value?.isDenied ?? false);
    final subtitle = checking
        ? l10n.settingsAiConfigChecking
        : unreachable
        ? l10n.settingsAiConfigUnreachable
        : denied
        ? l10n.settingsAiConfigDenied
        : l10n.settingsAiConfigSubtitle;
    return ListTile(
      key: const Key('settings-ai-config'),
      leading: const Icon(Icons.psychology_alt_outlined),
      title: Text(l10n.settingsAiConfig),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checking)
            const SizedBox(
              key: Key('settings-ai-config-checking'),
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (unreachable)
            IconButton(
              key: const Key('settings-ai-config-retry'),
              tooltip: l10n.commonRetry,
              icon: const Icon(Icons.refresh),
              // One-shot by design: re-running the probes is explicit user
              // intent, never an implicit poll. Both seams are re-run: a
              // reachability retry that left a stale capability answer in place
              // would keep rendering the old state.
              onPressed: () {
                ref.invalidate(aiConfigReachabilityProvider);
                ref.invalidate(myCapabilitiesProvider);
              },
            ),
          // A resolved denial is shown, not hidden (#809 rule) and never
          // turned into a lock-out: no Retry affordance (retrying cannot flip
          // a role), and the tile stays tappable so the screen can answer.
          if (denied)
            const Icon(
              key: Key('settings-ai-config-denied'),
              Icons.lock_outline,
              size: 18,
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      // Fire-and-forget push (no result consumed), same as the wizard
      // and import-submit entries — in EVERY state: an unreachable backend
      // is a state the screen explains, not a reason to withhold the push.
      // ListTile keeps the ≥ 48×48 dp target.
      onTap: () => unawaited(
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AiConfigScreen())),
      ),
    );
  }
}
