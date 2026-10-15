// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/active_block.dart';
import '../../auth/active_episode.dart';
import '../../design/spacing.dart';
import 'active_episode_chip.dart';
import 'active_scope_chip.dart';
import 'location_strip.dart';
import 'planning_location_route_observer.dart';
import 'profile_menu_button.dart';
import 'scope_pill.dart';
import 'search_action_button.dart';
import 'season_scope_chip.dart';
import 'window_size_class.dart';

/// The shell's sticky two-row top bar (issue #638).
///
/// Row 1 — profile and scope pills: the profile affordance at the far left,
/// then the Season · Block · Episode [ScopePill]s in a horizontally
/// scrollable cluster. Row 2 — view bar: the active destination's visible
/// title, the hierarchy breadcrumb ([LocationStrip]) and the search
/// affordance.
///
/// The whole bar is inset by the `MediaQuery` view padding (`SafeArea`), so
/// no content renders beneath the Android status bar in any morphology. The
/// bar is shell-owned and never hidden: the season pill is always present,
/// because it is also the only affordance that can SET a season when none is
/// active.
///
/// Two independent surfaces share the bar (issue #548): the LOCATION strip
/// (WHERE YOU NAVIGATED — per-route, per destination, hidden at destination
/// roots) and the SCOPE pills (WHAT FILTERS YOUR REQUESTS — sticky across
/// destinations and cold starts). The [observer] is the reactive seam for
/// the active destination's nested navigator.
///
/// // AUTHZ-GATE: the bar is display + navigation only — the pickers it opens
/// read the same authenticated projections the views already read, and it
/// dispatches no command, so it needs no membership check of its own.
class ShellTopBar extends ConsumerWidget {
  const ShellTopBar({
    super.key,
    required this.title,
    required this.navigatorKey,
    required this.observer,
  });

  /// The active destination's visible title (the shell derives it from the
  /// destination spec, so the bar can never drift from the destination
  /// list).
  final String title;

  /// The ACTIVE destination's nested navigator — the push target for the
  /// search and profile affordances (so they open inside the active view's
  /// stack).
  final GlobalKey<NavigatorState> navigatorKey;

  /// Reactive seam for the active destination's route stack.
  final LocationRouteObserver observer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: observer,
          builder: (context, _) {
            final navigator = navigatorKey.currentState;
            final location = navigator == null ? null : locationOf(navigator);
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Column(
                key: const Key('shell-context-bar'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ScopeRow(location: location),
                  _ViewRow(
                    title: title,
                    location: location,
                    navigatorKey: navigatorKey,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The scope bar (issue #667, agreed #638 design): TWO pill rows —
///
/// * row 1: profile affordance + Season + Block pills,
/// * row 2: the Episode chip on its own line — the hierarchy reads
///   top-down and the episode chip gets room instead of competing with
///   two other pills in one horizontally scrollable cluster. The row
///   collapses entirely while the chip is hidden (no #638 prerequisite
///   met yet) so no empty second line remains.
///
/// The horizontal-scroll fallback stays on row 1 (three pills + profile
/// icon on a 360dp phone); the episode row never scrolls — one chip.
///
/// The profile affordance needs no navigator: it only opens the shell
/// Scaffold's account drawer (issue #653), whose entries target the
/// ACTIVE destination's navigator (see `AccountDrawer.navigatorKey`).
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.location});

  final PlanningLocation? location;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('shell-scope-bar'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: AppSpacing.space4),
            ProfileMenuButton(),
            const SizedBox(width: AppSpacing.space4),
            // The pill cluster scrolls rather than overflows on a narrow bar.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SeasonScopeChip(
                      onOpenPicker: () =>
                          _push(context, const SeasonScopePickerScreen()),
                    ),
                    const SizedBox(width: AppSpacing.space8),
                    ActiveScopeChip(
                      location: location,
                      onOpenPicker: (seasonId) => _push(
                        context,
                        ScopeChipPickerScreen(seasonId: seasonId),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space4),
          ],
        ),
        _ScopeEpisodeRow(location: location),
      ],
    );
  }

  /// The scope pickers keep the shell's own (root) navigator — they cover
  /// the shell, exactly as they did before the top bar was redesigned
  /// (design.md *Out of scope* of `638-shell-top-bar-redesign`). Note that
  /// this is NOT design D7: D7 covers only the search/profile seam, which
  /// targets the DESTINATION navigator — the opposite direction.
  void _push(BuildContext context, Widget screen) {
    // Fire-and-forget navigation (no result consumed).
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }
}

/// Row 2 of the scope bar (issue #667): the episode chip alone, indented
/// under the profile affordance so the hierarchy reads top-down
/// (Season/Block above, Episode below). Collapses WITH the chip — while
/// the #638 prerequisite is unmet there is no second row at all.
class _ScopeEpisodeRow extends ConsumerWidget {
  const _ScopeEpisodeRow({required this.location});

  final PlanningLocation? location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same predicate as the chip itself (shared via the chip's static
    // helper) — no drift between "row hidden" and "chip hidden".
    final visible = ActiveEpisodeChip.visibleFor(
      ref.watch(activeBlockProvider),
      ref.watch(activeEpisodeProvider),
    );
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        0,
        AppSpacing.space4,
        AppSpacing.space8,
      ),
      child: ActiveEpisodeChip(
        location: location,
        onOpenPicker: (seasonId, blockId) => _pushRow(
          context,
          EpisodeScopePickerScreen(seasonId: seasonId, blockId: blockId),
        ),
      ),
    );
  }

  void _pushRow(BuildContext context, Widget screen) {
    // Fire-and-forget navigation (no result consumed); same root-navigator
    // seam as the row-1 pills (see _ScopeRow._push).
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }
}

/// Row 2: view title + hierarchy breadcrumb + search affordance.
class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.title,
    required this.location,
    required this.navigatorKey,
  });

  final String title;
  final PlanningLocation? location;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final compact =
        resolveWindowSizeClass(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.compact;
    return Row(
      key: const Key('shell-view-bar'),
      children: [
        const SizedBox(width: AppSpacing.space16),
        Text(
          title,
          key: const Key('shell-view-title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: AppSpacing.space8),
        // The breadcrumb takes the remaining width and WRAPS onto a second
        // line when the chain is long (issue #638), so a deep path shows all
        // of its levels instead of losing the outermost ones; its merged
        // semantics node keeps the full path in either case.
        Expanded(
          child: location == null
              ? const SizedBox.shrink()
              : LocationStrip(
                  location: location!,
                  maxSegments: compact ? 3 : 4,
                ),
        ),
        ShellSearchAction(navigatorKey: navigatorKey),
        const SizedBox(width: AppSpacing.space4),
      ],
    );
  }
}
