// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../characters/characters_state.dart';
import '../shell/shell_controller.dart';
import '../shell/view_states.dart';
import 'omni_search_controller.dart';
import 'omni_search_destinations.dart';
import 'omni_search_model.dart';
import 'omni_search_refresher.dart';

/// The OmniSearch surface (issue #616, OpenSpec change `add-omni-search` —
/// tasks §3.1–3.4).
///
/// The top-bar-search-triggered route (issue #613's slot): a DATA-ONLY
/// search — facet chips ("Szene" · "Rolle" · "Kostüm" · "Drehtag", all
/// active by default), a quick name prefilter, grouped results (D3 order:
/// scenes → roles → costumes → shooting days), every row deep-linking via
/// the single `omni_search_destinations.dart` mapping. No create commands,
/// no navigation shortcuts beyond the result rows (spec "Search is
/// data-only").
///
/// Season scoping (spec "Active-season scope"): the screen consumes the
/// SHELL's active season (task 4.2 — the same `shellControllerProvider`
/// read the views make, never a second projection lookup); the season
/// switch while the surface is open recomputes over the new season only
/// (family-keyed controllers). With no active season the surface shows the
/// localized empty state and NO results are computed — the search body is
/// not even built.
///
/// Staleness honesty (spec "Cached-data honesty"): any TTL-stale source
/// behind the ACTIVE facets renders the established stale treatment (same
/// warning treatment the read screens give cache-derived views), and
/// pull-to-refresh runs another bounded pass — no new freshness semantics
/// of its own.
class OmniSearchScreen extends ConsumerStatefulWidget {
  const OmniSearchScreen({super.key});

  /// Stable test targets per facet chip (tasks 3.3 → §7 tests).
  static const Map<OmniSearchFacet, String> chipKeys =
      <OmniSearchFacet, String>{
        OmniSearchFacet.scene: 'omni-search-chip-scene',
        OmniSearchFacet.character: 'omni-search-chip-character',
        OmniSearchFacet.costume: 'omni-search-chip-costume',
        OmniSearchFacet.shootingDay: 'omni-search-chip-shooting-day',
      };

  @override
  ConsumerState<OmniSearchScreen> createState() => _OmniSearchScreenState();
}

class _OmniSearchScreenState extends ConsumerState<OmniSearchScreen> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Bounded prefresh on surface open (task §3.4): fire-and-forget — the
    // cache results render immediately; the pass only lifts the
    // not-yet-loaded notes and, on success, brings fresh rows in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final season = ref.read(shellControllerProvider).activeSeason;
      if (season != null) {
        ref.read(omniSearchSourceRefresherProvider).prefresh(season.id);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.omniSearchTitle)),
      body: season == null
          ? ListView(
              key: const Key('omni-search-no-season'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                const Icon(Icons.search_off_outlined, size: 48),
                const SizedBox(height: 16),
                Center(child: Text(l10n.omniSearchNoSeason)),
              ],
            )
          : _SearchBody(season: season, text: _text),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  const _SearchBody({required this.season, required this.text});

  final SeasonView season;
  final TextEditingController text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final state = ref.watch(omniSearchControllerProvider(season.id));

    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(key: Key('omni-search-loading')),
      ),
      // Storage failure (the DAO read failed): localized problem copy +
      // retry — never silent empty presented as ground truth.
      error: (error, _) => ViewErrorState(
        errorKey: const Key('omni-search-error'),
        message: l10n.omniSearchError,
        onRetry: ref
            .read(omniSearchControllerProvider(season.id).notifier)
            .retryAfterError,
      ),
      data: (view) => RefreshIndicator(
        onRefresh: ref
            .read(omniSearchControllerProvider(season.id).notifier)
            .refresh,
        child: _ResultList(view: view, season: season, text: text),
      ),
    );
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({
    required this.view,
    required this.season,
    required this.text,
  });

  final OmniSearchViewState view;
  final SeasonView season;
  final TextEditingController text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final notifier = ref.read(omniSearchControllerProvider(season.id).notifier);

    return ListView.builder(
      key: const Key('omni-search-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _itemCount,
      itemBuilder: (context, index) =>
          _row(context, ref, l10n, notifier, index),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    OmniSearchController notifier,
    int index,
  ) {
    // Section layout (fixed order): 0 field → 1 chips → [stale banner] →
    // [one not-yet-loaded notice per cold active facet] → the content
    // section (exactly one narrative row, or group headers + hit rows).
    var cursor = 0;
    if (index == cursor++) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          key: const Key('omni-search-field'),
          controller: text,
          onChanged: notifier.setText,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.omniSearchHint,
            prefixIcon: const Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
        ),
      );
    }
    if (index == cursor++) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _ChipsRow(
          active: view.activeFacets,
          onToggle: notifier.toggleFacet,
        ),
      );
    }
    if (view.anyStale) {
      if (index == cursor++) {
        return _StaleBanner(message: l10n.omniSearchStaleBanner);
      }
    }
    for (final facet in OmniSearchFacet.values) {
      if (!view.notLoadedFacets.contains(facet)) continue;
      if (index == cursor++) {
        return ViewPartialNotice(
          noticeKey: Key('omni-search-not-loaded-${facet.name}'),
          message: l10n.omniSearchNotLoaded(_facetChipLabel(context, facet)),
        );
      }
    }
    return _ContentRow(
      view: view,
      season: season,
      contentIndex: index - cursor,
    );
  }

  int get _itemCount {
    var count = 2;
    if (view.anyStale) count++;
    count += view.notLoadedFacets.length;
    count += _contentCount;
    return count;
  }

  int get _contentCount {
    if (view.groups.isNotEmpty) {
      return [for (final group in view.groups) 1 + group.hits.length]
          .fold(0, (a, b) => a + b);
    }
    final narrativeVisible =
        !view.zeroMatch ||
        view.consultedFacets.isNotEmpty ||
        view.notLoadedFacets.isEmpty;
    return narrativeVisible ? 1 : 0;
  }
}

/// The narrative / grouped-hits section rendered AFTER the conditionally
/// present prefix rows, consuming the remaining list indices in order.
class _ContentRow extends StatelessWidget {
  const _ContentRow({
    required this.view,
    required this.season,
    required this.contentIndex,
  });

  final OmniSearchViewState view;
  final SeasonView season;
  final int contentIndex;

  @override
  Widget build(BuildContext context) {
    if (view.groups.isEmpty) {
      // Exactly one narrative row — EXCEPT while ANY queried source is
      // unanswered (cold): the not-yet-loaded notes above then carry the
      // narrative, and no zero-match sentence is rendered as ground truth
      // the surface does not have (task 2.3: distinguishable states). An
      // all-chips-deselected query still shows its zero-match sentence
      // (nothing was selected to search — an echo of an empty set).
      if (view.zeroMatch &&
          view.consultedFacets.isEmpty &&
          view.notLoadedFacets.isNotEmpty) {
        return const SizedBox.shrink();
      }
      return _NarrativeState(view: view);
    }
    var rowCursor = 0;
    for (final group in view.groups) {
      if (contentIndex == rowCursor++) {
        return _GroupHeader(facet: group.facet);
      }
      for (final hit in group.hits) {
        if (contentIndex == rowCursor++) {
          return _HitRow(hit: hit, season: season);
        }
      }
    }
    // Never reached: the list length is derived from the same structure.
    return const SizedBox.shrink();
  }
}

class _NarrativeState extends StatelessWidget {
  const _NarrativeState({required this.view});

  final OmniSearchViewState view;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    if (view.zeroMatch) {
      final consulted = view.activeFacets
          .difference(view.notLoadedFacets)
          .map((f) => _facetChipLabel(context, f))
          .join(' · ');
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          key: const Key('omni-search-zero-match'),
          l10n.omniSearchZeroMatch(view.text, consulted),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        key: const Key('omni-search-initial'),
        l10n.omniSearchInitialEmpty,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The facet chip row (task 3.1): shipped German copy, all four active by
/// default; the FilterChip's rendered semantics carry the toggle state
/// (task 4.3's chip a11y — no hand-rolled Semantics needed).
class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.active, required this.onToggle});

  final Set<OmniSearchFacet> active;
  final ValueChanged<OmniSearchFacet> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final facet in OmniSearchFacet.values)
        FilterChip(
          key: Key(OmniSearchScreen.chipKeys[facet]!),
          label: Text(_facetChipLabel(context, facet)),
          selected: active.contains(facet),
          onSelected: (_) => onToggle(facet),
        ),
    ],
  );
}

String _facetChipLabel(BuildContext context, OmniSearchFacet facet) {
  final l10n = l10nOf(context);
  return switch (facet) {
    OmniSearchFacet.scene => l10n.omniSearchChipScene,
    OmniSearchFacet.character => l10n.omniSearchChipCharacter,
    OmniSearchFacet.costume => l10n.omniSearchChipCostume,
    OmniSearchFacet.shootingDay => l10n.omniSearchChipShootingDay,
  };
}

/// Localized group header in D3 order — each group's first row (keyed for
/// the grouping tests).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.facet});

  final OmniSearchFacet facet;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListTile(
      key: Key('omni-search-group-${facet.name}'),
      dense: true,
      title: Text(switch (facet) {
        OmniSearchFacet.scene => l10n.omniSearchGroupScenes,
        OmniSearchFacet.character => l10n.omniSearchGroupCharacters,
        OmniSearchFacet.costume => l10n.omniSearchGroupCostumes,
        OmniSearchFacet.shootingDay => l10n.omniSearchGroupShootingDays,
      }, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// One result row: the per-type context labeling (task 3.2, the "Szene 12
/// · Wohnung — Zoe" narrative) and the tap → deep link through the single
/// destination mapping (D4). The visible labels reuse the vocabulary the
/// originating views' rows use; the row key pins the hit id for the
/// contract tests.
class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.season});

  final OmniSearchHit hit;
  final SeasonView season;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);

    final (String title, String subtitle, Widget leading) = switch (hit) {
      SceneOmniHit(:final scene, :final episode) => (
        scene.summary == null || scene.summary!.isEmpty
            ? (scene.sceneNumber == null
                  ? l10n.scriptSceneNumberUnknown
                  : l10n.scriptSceneNumber(scene.sceneNumber!))
            : scene.summary!,
        l10n.scriptEpisodeLabel(episode.name ?? '${episode.number}'),
        _leadingAvatar(hit),
      ),
      CharacterOmniHit(:final character) => (
        character.name,
        characterCategoryLabel(l10n, character),
        _leadingAvatar(hit),
      ),
      CostumeOmniHit(:final costume) => (
        costume.notes.isEmpty
            ? (costume.categoryName ?? l10n.omniSearchGroupCostumes)
            : costume.notes,
        costume.categoryName ?? '',
        _leadingAvatar(hit),
      ),
      ShootingDayOmniHit(:final day, :final episode) => (
        day.label ??
            (day.date == null
                ? l10n.scheduleDayUndated
                : l10n.scheduleDayLabel('${day.date}')),
        l10n.scriptEpisodeLabel(episode.name ?? '${episode.number}'),
        _leadingAvatar(hit),
      ),
    };

    return ListTile(
      key: switch (hit) {
        SceneOmniHit(:final scene) => Key('omni-search-hit-scene-${scene.id}'),
        CharacterOmniHit(:final character) => Key(
          'omni-search-hit-character-${character.id}',
        ),
        CostumeOmniHit(:final costume) => Key(
          'omni-search-hit-costume-${costume.id}',
        ),
        ShootingDayOmniHit(:final day) => Key(
          'omni-search-hit-shooting-day-${day.id}',
        ),
      },
      leading: leading,
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      // Fire-and-forget navigation (no result consumed).
      onTap: () => pushOmniSearchDestination(context, season, hit),
    );
  }
}

/// The scene's projected number is its identity mark (script-view
/// convention); every other facet type carries its glossary icon.
Widget _leadingAvatar(OmniSearchHit hit) => CircleAvatar(
  child: switch (hit) {
    SceneOmniHit(:final scene) when scene.sceneNumber != null => Text(
      '${scene.sceneNumber}',
    ),
    SceneOmniHit() => const Text('–'),
    CharacterOmniHit() => const Icon(Icons.face_outlined, size: 20),
    CostumeOmniHit() => const Icon(Icons.checkroom_outlined, size: 20),
    ShootingDayOmniHit() => const Icon(Icons.calendar_month_outlined, size: 20),
  },
);

/// The established stale treatment — a warning row above the results (the
/// same tone the read screens use); pull-to-refresh re-reconciles.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      key: const Key('omni-search-stale-banner'),
      leading: Icon(
        Icons.sync_problem_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(message),
    ),
  );
}
