// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../characters/characters_screen.dart';
import '../costume_categories/costume_categories_screen.dart';
import '../costumes/costumes_screen.dart';
import 'planning_location.dart';
import 'profile_menu_button.dart';
import 'season_scope_chip.dart';
import 'shell_controller.dart';

/// The Cast view (issue #610, destination 1): the actor roster and the
/// costume surface, scoped to the shell's active season.
///
/// Design decision D3: the dissolved `Garderobe` destination did NOT
/// become a second launcher tab — costumes are integrated here, one switch
/// away from the characters they are bound to, and the season-scoped
/// costume-category vocabulary sits on this view's app bar (never with the
/// user settings, issue #610's hard acceptance criterion).
///
/// Both list screens keep their controllers, repositories, keys and
/// AUTHZ-GATE comments (issue #610: only the entry point moves). They are
/// embedded as tab content beneath the view's own app bar; each brings its
/// own scaffold, so their titles stay visible with the roster/costume
/// surface they belong to.
///
/// With no active season the view renders a season-selection empty state
/// whose call to action opens the season scope picker (never an error, and
/// no longer a jump to another destination — there is no Season tab to
/// jump to).
class CastTabScreen extends ConsumerStatefulWidget {
  const CastTabScreen({super.key});

  @override
  ConsumerState<CastTabScreen> createState() => _CastTabScreenState();
}

class _CastTabScreenState extends ConsumerState<CastTabScreen> {
  /// Which half of the Cast view is on screen. Local view state only — it
  /// is not navigation history (the tab switch is a user "jump").
  bool _showCostumes = false;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCast),
        actions: [
          if (season != null)
            IconButton(
              key: const Key('cast-categories-action'),
              icon: const Icon(Icons.style_outlined),
              tooltip: l10n.castCategoriesTooltip,
              // Fire-and-forget navigation (no result consumed).
              onPressed: () => _openCategories(context),
            ),
          const ProfileMenuButton(),
        ],
      ),
      body: season == null ? _emptyState(context) : _content(context, season),
    );
  }

  /// The roster/costume switch plus the selected surface.
  Widget _content(BuildContext context, SeasonView season) {
    final l10n = l10nOf(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<bool>(
            key: const Key('cast-surface-switch'),
            segments: [
              ButtonSegment<bool>(
                value: false,
                icon: const Icon(Icons.person_outline),
                label: Text(l10n.castSegmentCharacters),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: const Icon(Icons.checkroom_outlined),
                label: Text(l10n.castSegmentCostumes),
              ),
            ],
            selected: {_showCostumes},
            onSelectionChanged: (selection) =>
                setState(() => _showCostumes = selection.first),
          ),
        ),
        Expanded(
          child: _showCostumes
              ? CostumesScreen(season: season)
              : CharactersScreen(season: season),
        ),
      ],
    );
  }

  /// No active season: a plain-language empty state whose call to action
  /// opens the season scope picker (the surface that can SET the season —
  /// same rule the former Kleidung tab used for its Planen-tab jump).
  Widget _emptyState(BuildContext context) {
    final l10n = l10nOf(context);
    return ListView(
      key: const Key('cast-empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.face_outlined, size: 48),
        const SizedBox(height: 16),
        Center(child: Text(l10n.castNoSeason)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            key: const Key('cast-pick-season-cta'),
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SeasonScopePickerScreen(),
                ),
              ),
            ),
            child: Text(l10n.castPickSeason),
          ),
        ),
      ],
    );
  }

  /// Pushes the season-scoped category vocabulary for the active season
  /// (the season DTO lives in the shell state; the CQRS boundary is
  /// unchanged — this is the season the user is scoped to, not a lookup).
  void _openCategories(BuildContext context) {
    final season = ref.read(shellControllerProvider).activeSeason;
    if (season == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(arguments: PlanningLocation.season(season)),
          builder: (_) => CostumeCategoriesScreen(season: season),
        ),
      ),
    );
  }
}
