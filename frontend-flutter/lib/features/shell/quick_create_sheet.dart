// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../auth/active_episode.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_de.dart';
import '../ai_import/import_jobs/import_submit_screen.dart';
import '../scenes/create_scene_screen.dart';
import '../seasons/setup/setup_wizard_screen.dart';
import '../shooting_days/create_shooting_day_screen.dart';

/// One affordance row of the shell quick-create sheet (issue #612).
///
/// Plain data on purpose: the sheet renders and routes only — the write
/// affordances themselves gate inside their controllers (the sheet issues
/// NO network request for merely being opened). New surfaces (scene,
/// piece, character) append to the factory's list; nothing else changes.
class QuickCreateAction {
  const QuickCreateAction({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.routeBuilder,
  });

  /// Test key (`quick-create-<name>`).
  final Key key;

  /// Glossary icon (icon reinforces the visible label, never replaces it).
  final IconData icon;

  /// Visible label (glossary rule — icon-only affordances are forbidden).
  final String title;

  /// One-line narrative of what the flow does.
  final String subtitle;

  /// The existing flow to deep-link (sheet → push, never embed, issue
  /// #612 feasibility note).
  final Widget Function() routeBuilder;
}

/// The quick-create affordance list (issue #612, extended by #624): the
/// context-free entries are always present, and when an [episode] scope is
/// active the two context-sensitive entries are prepended for that episode.
/// The list is data-driven, so extension stays additive — the sheet renders
/// whatever it is handed.
List<QuickCreateAction> shellQuickCreateActions(
  AppLocalizations l10n, {
  ActiveEpisodeScope? episode,
}) => [
  if (episode != null) ...[
    QuickCreateAction(
      key: const Key('quick-create-scene'),
      icon: Icons.view_agenda_outlined,
      title: l10n.quickCreateSceneTitle,
      subtitle: l10n.quickCreateSceneSubtitle,
      routeBuilder: () => CreateSceneScreen(episodeId: episode.episodeId),
    ),
    QuickCreateAction(
      key: const Key('quick-create-shooting-day'),
      icon: Icons.calendar_month_outlined,
      title: l10n.quickCreateShootingDayTitle,
      subtitle: l10n.quickCreateShootingDaySubtitle,
      routeBuilder: () => CreateShootingDayScreen(episodeId: episode.episodeId),
    ),
  ],
  QuickCreateAction(
    key: const Key('quick-create-ai-import'),
    icon: Icons.smart_toy_outlined,
    title: l10n.navAiImport,
    subtitle: l10n.quickCreateAiImportSubtitle,
    routeBuilder: AiImportSubmitScreen.new,
  ),
  QuickCreateAction(
    key: const Key('quick-create-wizard'),
    icon: Icons.rocket_launch_outlined,
    title: l10n.wizardTitle,
    subtitle: l10n.quickCreateWizardSubtitle,
    routeBuilder: SetupWizardScreen.new,
  ),
];

/// Opens the quick-create sheet (issue #612): the plus FAB's single
/// surface. A modal bottom sheet on every morphology — it is a menu of
/// choices, not a form (the forms live behind the chosen entry).
Future<void> showQuickCreateSheet(
  BuildContext context, {
  required List<QuickCreateAction> actions,
}) => showModalBottomSheet<void>(
  context: context,
  // The root navigator hosts the sheet; the chosen entry then pushes the
  // full-screen flow on the same navigator (covers the shell entirely —
  // the same behavior the season scope picker established).
  useRootNavigator: true,
  builder: (sheetContext) => QuickCreateSheet(actions: actions),
);

/// The sheet body: one icon + visible-label row per affordance.
class QuickCreateSheet extends StatelessWidget {
  const QuickCreateSheet({super.key, required this.actions});

  final List<QuickCreateAction> actions;

  void _open(BuildContext sheetContext, QuickCreateAction action) {
    // Capture the navigator BEFORE popping (using the context after the
    // pop would be unsafe). Pop first, THEN push: the full-screen flow
    // replaces the sheet instead of stacking on top of it.
    final navigator = Navigator.of(sheetContext, rootNavigator: true);
    navigator.pop();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => action.routeBuilder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Standalone sheet previews/tests use the canonical German suite; the
    // production App supplies resolved delegates for the device locale
    // (same fallback rule as the shell).
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizationsDe();
    return SafeArea(
      // Scrollable so a longer affordance list (issue #624 added the
      // context-sensitive entries) never overflows the sheet's bounded
      // height on short screens.
      child: SingleChildScrollView(
        child: Column(
          key: const Key('shell-quick-create-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                l10n.quickCreateTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final action in actions)
              ListTile(
                key: action.key,
                leading: Icon(action.icon),
                title: Text(action.title),
                subtitle: Text(action.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
