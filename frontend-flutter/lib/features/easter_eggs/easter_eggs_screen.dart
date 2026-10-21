// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/settings/easter_eggs_store.dart';
import '../../design/components/section_header.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../ai_import/clippy/clippy_trigger.dart';
import '../ai_import/clippy/karl_kleiderbuegel_figure.dart';
import 'dejavu_cat.dart';

/// Dedicated Easter-eggs management screen (issue #708, analogous to the
/// AI-configuration screen, issue #643): pushed from the settings entry
/// tile, it hosts the complete per-egg functionality — the per-egg
/// switches (issue #615; default ON, persisted, globally reactive via
/// [easterEggProvider]) and the Easter-eggs gallery (issue #640).
///
/// A failed preference read falls back to default ON with a visible error
/// state — never a silent failure; a failed write surfaces a localized
/// snackbar. Gates preserved unchanged (no behavior moved, only the
/// surface): the per-egg switch is the master gate, `disableAnimations`
/// renders the static pose, and the October month-gate bypass stays
/// limited to the gallery — the live surfaces (`DejaVuCatOverlay` etc.)
/// are untouched.
class EasterEggsScreen extends ConsumerWidget {
  const EasterEggsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return Scaffold(
      key: const Key('easter-eggs-screen'),
      appBar: AppBar(
        key: const Key('easter-eggs-appbar'),
        title: Text(l10n.settingsEasterEggsScreenTitle),
      ),
      body: ListView(
        key: const Key('easter-eggs-list'),
        children: [
          // ── Per-egg switches (issue #615) ───────────────────────────
          SectionHeader(label: l10n.settingsEasterEggs),
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
          SectionHeader(label: l10n.settingsEasterEggsPreview),
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
        ],
      ),
    );
  }
}

/// One per-egg switch row (issue #615).
///
/// A dedicated [ConsumerWidget] owns the watches for a SINGLE egg, so
/// flipping one egg rebuilds only its own row — never the screen
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
/// "Easter-eggs gallery"): renders the egg's figure as an explicit
/// showcase — **regardless of month** — so every egg is discoverable and
/// testable year-round.
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
