// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../data/cache/relative_time.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_en.dart';
import '../shell/shell_controller.dart';
import 'create_season_sheet.dart';
import 'seasons_controller.dart';
import 'seasons_metrics_provider.dart';
import 'seasons_state.dart';
import 'setup/setup_wizard_screen.dart';
import 'widgets/season_card.dart';
import 'widgets/seasons_empty_state.dart';
import 'widgets/seasons_skeleton.dart';

/// Localized client-side copy for a create-command failure, keyed on the
/// stable problem `code` (AGENTS.md §5 — never branch on / show the server's
/// localized `detail`). Unknown codes fall back to a code-carrying generic.
String createErrorCopy(ProblemError error, [AppLocalizations? catalog]) {
  final l10n = catalog ?? AppLocalizationsEn();
  return switch (error.code) {
    // Real backend code first (issue #443); legacy aliases kept for stale
    // fixtures.
    'season.number-already-exists' ||
    'seasons.conflict' ||
    'season.conflict' => l10n.seasonsCreateConflict,
    'authz.denied' || 'auth.session_required' => l10n.seasonsCreateAuth,
    _ when error.code.startsWith('transport.') => l10n.seasonsCreateNetwork,
    _ => l10n.seasonsCreateGeneric,
  };
}

/// The seasons screen — the reference pattern for every subsequent screen
/// (spec `flutter-first-screen`; AGENTS.md §9).
///
/// A `ConsumerWidget`: it renders and dispatches only (no `StatefulWidget`
/// / `setState`) — all domain branching lives in [SeasonsController]
/// state. The merged card list comes from `SeasonsScreenState`
/// `rowsWithMetrics`: authoritative rows from the Drift cache with
/// per-season cached metadata (`seasonMetricsProvider`), optimistic
/// overlays layered by the controller (never a Drift write).
///
/// Presentation per the seasons-home capability (tasks 3.1–3.5): rows
/// render as Material 3 cards, the create action is an extended FAB with
/// a visible label, and the empty/loading states are the guided empty
/// state and the skeleton.
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final state = ref.watch(seasonsControllerProvider);
    final controller = ref.read(seasonsControllerProvider.notifier);
    // Err branch of the metrics source → `null` map: cards render without
    // a metadata line (task 2.1 merge; never fabricated counts).
    final metrics = ref.watch(seasonMetricsProvider).asData?.value;
    final rows = state.rowsWithMetrics(metrics);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.seasonsTitle)),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('create-error-banner'),
              text: createErrorCopy(error, l10n),
              tone: BannerTone.error,
              onDismiss: controller.dismissCommandError,
              action: const Icon(Icons.close, key: Key('create-error-dismiss')),
            ),
          if (state.isStale)
            _Banner(
              key: const Key('seasons-stale-banner'),
              text: l10n.seasonsStale,
              tone: BannerTone.warning,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _body(context, ref, state, rows),
            ),
          ),
        ],
      ),
      // AUTHZ-GATE: the backend `create_season` handler requires an
      // authenticated caller (CurrentUser extractor; auth-only — there is
      // no season-membership role to check for a season that does not
      // exist yet). The extended FAB is therefore shown only for a
      // resolved authenticated session; loading and error states show
      // nothing (the request would be refused server-side anyway).
      floatingActionButton: _canCreateSeason(ref)
          ? FloatingActionButton.extended(
              key: const Key('season-add-fab'),
              onPressed: () => showCreateSeasonSheet(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.seasonsCreate),
            )
          : null,
    );
  }

  /// The list area's state machine (tasks 3.2/3.4/3.5): skeleton for the
  /// cold-start loading window (no cached rows yet — the empty state never
  /// flashes), guided empty state when empty without failures, cards when
  /// data exists, and an error hint when the projection failed with
  /// nothing to serve.
  Widget _body(
    BuildContext context,
    WidgetRef ref,
    SeasonsScreenState state,
    List<SeasonRow> rows,
  ) {
    if (rows.isEmpty) {
      if (state.projected.isLoading) {
        return ListView(
          key: const Key('seasons-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SeasonsSkeleton()],
        );
      }
      if (state.projected.hasError) {
        return ListView(
          key: const Key('seasons-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Center(child: Text(l10nOf(context).seasonsLoadError)),
          ],
        );
      }
      return ListView(
        key: const Key('seasons-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 96),
          SeasonsEmptyState(
            // Session gate: same rule as the FAB (auth-only create).
            // Guided path entry (add-season-setup-wizard): opens the setup
            // wizard as a full-screen route on THIS tab's navigator; the
            // quick-create sheet remains the FAB's path (additive, not a
            // replacement).
            onSetup: _canCreateSeason(ref)
                ? () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SetupWizardScreen(),
                      ),
                    ),
                  )
                : null,
            // AUTHZ-GATE: the AI-import upload routes are gated by the
            // season costume-dept membership INSIDE the import submit
            // controller BEFORE any network call — this CTA only performs
            // a client-side tab jump (no request is issued from here),
            // and the gate comment travels with the Mehr tab's Import
            // entry it lands on.
            onImport: () => ref
                .read(shellControllerProvider.notifier)
                .selectTab(kMehrTabIndex),
          ),
        ],
      );
    }
    return ListView.builder(
      key: const Key('seasons-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, i) => _SeasonCard(row: rows[i]),
    );
  }

  bool _canCreateSeason(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }
}

/// One list item: a projected season or an optimistic overlay, both
/// rendered in the card language (task 3.2 — the row keys
/// `season-<id>` / `overlay-<id>` / `overlay-spinner` /
/// `overlay-warning` are preserved unchanged).
class _SeasonCard extends ConsumerWidget {
  const _SeasonCard({required this.row});

  final SeasonRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return switch (row) {
      ProjectedSeasonRow(:final season, :final metrics) => SeasonCard(
        key: Key('season-${season.id}'),
        title: season.title ?? l10n.seasonsDefaultTitle(season.number),
        metadata: _metadataLine(metrics, l10n),
        staleLabel: _staleLabel(ref, metrics, l10n),
        // Task 4.4 + spec `flutter-hierarchy-navigation`: the season-row
        // BlocksScreen push stays on the PLANEN tab's navigator (the
        // shell's hierarchy spine — the Season tab never hosts hierarchy
        // pushes). The card tap sets the active season from the ACTED-ON
        // row DTO (CQRS boundary: no second projection lookup) and jumps
        // to the Planen tab, exactly like the shell's Kategorien entry.
        onTap: () => _openPlanning(context, ref, season),
      ),
      OptimisticSeasonRow(:final overlay) => SeasonCard(
        key: Key('overlay-${overlay.id}'),
        title: overlay.name?.isNotEmpty == true
            ? overlay.name!
            : l10n.seasonsDefaultTitle(overlay.number ?? ''),
        // The overlay's status copy (keys/semantics unchanged from the
        // tile era): the syncing line, or the retained stale warning.
        metadata: overlay.status == OverlayStatus.stale
            // The domain layer stores a stable warning CODE; the
            // user-facing wording comes from the catalog.
            ? (overlay.warning == kReconcileStaleWarningCode
                  ? l10n.reconcileStaleWarning
                  : overlay.warning)
            : l10n.seasonsSyncing,
        trailing: overlay.status == OverlayStatus.stale
            ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
            : const SizedBox(
                key: Key('overlay-spinner'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    };
  }

  /// Relative staleness label computed with the injectable clock (D2):
  /// `null` while the metadata is fresh or absent — goldens stay
  /// deterministic because the clock is pinned by the test container.
  String? _staleLabel(
    WidgetRef ref,
    SeasonMetrics? metrics,
    AppLocalizations l10n,
  ) {
    if (metrics == null || !metrics.isStale) return null;
    return l10n.seasonsStaleAt(
      relativeTimeSince(
        metrics.cachedAt,
        clock: ref.read(clockProvider),
        // The data-layer formatter stays free of user-facing strings; the
        // units come from the resolved catalog, so an English card never
        // renders a German relative timestamp.
        copy: RelativeTimeCopy(
          justNow: l10n.seasonsStaleJustNow,
          minutes: (count) => l10n.seasonsStaleMinutes('$count'),
          hours: (count) => l10n.seasonsStaleHours('$count'),
          days: (count) => l10n.seasonsStaleDays('$count'),
        ),
      ),
    );
  }

  /// Cached counts joined into the metadata line (glossary keys
  /// `seasons.meta.*`): only cached sources contribute; `null` when the
  /// season has no cached entry at all (the line is omitted — spec
  /// "No cached metadata" scenario). Singular inflection when the count
  /// is one ("1 Block", "1 Szene", "1 Kostüm" — review grammar fix).
  String? _metadataLine(SeasonMetrics? metrics, AppLocalizations l10n) {
    if (metrics == null) return null;
    final parts = [
      if (metrics.blockCount case final b?) l10n.seasonsMetaBlocks(b),
      if (metrics.sceneCount case final s?) l10n.seasonsMetaScenes(s),
      if (metrics.costumeCount case final c?) l10n.seasonsMetaCostumes(c),
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  void _openPlanning(BuildContext context, WidgetRef ref, SeasonView season) {
    final shell = ref.read(shellControllerProvider.notifier);
    shell.setActiveSeason(season);
    shell.selectTab(kPlanenTabIndex);
  }
}

enum BannerTone { warning, error }

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.tone,
    this.onDismiss,
    this.action,
  });

  final String text;
  final BannerTone tone;
  final VoidCallback? onDismiss;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = switch (tone) {
      BannerTone.warning => scheme.tertiaryContainer,
      BannerTone.error => scheme.errorContainer,
    };
    final foreground = switch (tone) {
      BannerTone.warning => scheme.onTertiaryContainer,
      BannerTone.error => scheme.onErrorContainer,
    };
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
            if (action != null)
              GestureDetector(
                onTap: onDismiss,
                child: IconTheme(
                  data: IconThemeData(color: foreground),
                  child: action!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
