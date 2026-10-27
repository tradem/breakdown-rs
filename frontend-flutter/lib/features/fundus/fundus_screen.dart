// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../shell/shell_controller.dart';
import '../shell/view_states.dart';
import 'fundus_controller.dart';
import 'fundus_destinations.dart';
import 'fundus_model.dart';

/// The piece **fundus** surface (issue #625, OpenSpec change
/// `flutter-fundus-search`).
///
/// A SEPARATE, cross-season browsing surface — NOT a fifth OmniSearch chip
/// (design D1). It shows every piece of the ACTIVE PROJECT whose repertoire
/// intersects the project's seasons, with a season-chip facet model and a
/// name prefilter over the pinned fields (notes + category name). Season
/// names on each row come from the seasons projection (a read-DTO join —
/// never a second projection lookup).
///
/// The surface consumes the shell's active season for its `project_id`
/// (design D2); with no active season it shows the localized no-season empty
/// state and computes no results.
class FundusScreen extends ConsumerStatefulWidget {
  const FundusScreen({super.key});

  @override
  ConsumerState<FundusScreen> createState() => _FundusScreenState();
}

class _FundusScreenState extends ConsumerState<FundusScreen> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Bounded prefetch on open (tasks §3.2): fire-and-forget — cached rows
    // render immediately; the pass fills a cold project cache and re-reads.
    // LISTEN-MANUAL with `fireImmediately` covers the opening project and a
    // project switch while the surface is open.
    ref.listenManual(shellControllerProvider, (previous, next) {
      final previousId = previous?.activeSeason?.projectId;
      final nextProject = next.activeSeason?.projectId;
      if (nextProject == null || nextProject == previousId) return;
      ref.read(fundusControllerProvider(nextProject).notifier).refresh();
    }, fireImmediately: true);
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
      appBar: AppBar(title: Text(l10n.fundusTitle)),
      body: season == null
          ? ViewEmptyState(
              emptyKey: const Key('fundus-no-season'),
              message: l10n.fundusNoSeason,
              icon: Icons.checkroom_outlined,
            )
          : _FundusBody(season: season, text: _text),
    );
  }
}

class _FundusBody extends ConsumerWidget {
  const _FundusBody({required this.season, required this.text});

  final SeasonView season;
  final TextEditingController text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final state = ref.watch(fundusControllerProvider(season.projectId));

    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(key: Key('fundus-loading')),
      ),
      // Storage failure (the DAO read failed): localized problem copy +
      // retry — never a silent empty presented as ground truth.
      error: (error, _) => ViewErrorState(
        errorKey: const Key('fundus-error'),
        message: l10n.fundusError,
        onRetry: ref
            .read(fundusControllerProvider(season.projectId).notifier)
            .retryAfterError,
      ),
      data: (view) => RefreshIndicator(
        onRefresh: ref
            .read(fundusControllerProvider(season.projectId).notifier)
            .refresh,
        child: _FundusList(view: view, season: season, text: text),
      ),
    );
  }
}

class _FundusList extends ConsumerWidget {
  const _FundusList({
    required this.view,
    required this.season,
    required this.text,
  });

  final FundusViewState view;
  final SeasonView season;
  final TextEditingController text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(
      fundusControllerProvider(season.projectId).notifier,
    );
    final hasChips = view.projectSeasons.isNotEmpty;
    final contentRows = view.rows.isEmpty ? 1 : view.rows.length;
    final itemCount =
        1 + // text field
        (hasChips ? 1 : 0) + // season chips
        (view.stale ? 1 : 0) + // stale banner
        contentRows;

    return ListView.builder(
      key: const Key('fundus-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // `cursor` is recomputed PER row (never shared across itemBuilder
        // calls — ListView.builder may invoke rows out of order or rebuild
        // them): each row re-walks the fixed section prefix.
        var cursor = 0;
        if (index == cursor++) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              key: const Key('fundus-field'),
              controller: text,
              onChanged: notifier.setText,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10nOf(context).fundusHint,
                prefixIcon: const Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
            ),
          );
        }
        if (hasChips && index == cursor++) {
          return _SeasonChips(
            seasons: view.projectSeasons,
            selected: view.selectedSeasonIds,
            onToggle: notifier.toggleSeason,
          );
        }
        if (view.stale && index == cursor++) {
          return _StaleBanner(message: l10nOf(context).fundusStaleBanner);
        }
        if (view.rows.isEmpty) {
          return _FundusNarrative(view: view);
        }
        return _PieceRow(
          piece: view.rows[index - cursor],
          season: season,
          projectSeasons: view.projectSeasons,
        );
      },
    );
  }
}

class _FundusNarrative extends StatelessWidget {
  const _FundusNarrative({required this.view});

  final FundusViewState view;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    // Rows present → the list renders them; the narrative only covers the
    // empty cases. Zero-match first (it is only true once a pass completed),
    // then the not-yet-loaded note, then the genuinely empty fundus.
    if (view.zeroMatch) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          key: const Key('fundus-zero-match'),
          l10n.fundusZeroMatch(view.text),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!view.loaded) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          key: const Key('fundus-not-loaded'),
          l10n.fundusNotLoaded,
          textAlign: TextAlign.center,
        ),
      );
    }
    // Loaded, no rows, no query: the project's fundus is genuinely empty.
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        key: const Key('fundus-empty'),
        l10n.fundusEmpty,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The season-chip facet model (design D4): one chip per season of the
/// active project. All deselected = the whole fundus.
class _SeasonChips extends StatelessWidget {
  const _SeasonChips({
    required this.seasons,
    required this.selected,
    required this.onToggle,
  });

  final List<SeasonView> seasons;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final season in seasons)
            FilterChip(
              key: Key('fundus-season-chip-${season.id}'),
              label: Text(
                season.title ?? l10n.seasonsDefaultTitle(season.number),
              ),
              selected: selected.contains(season.id),
              onSelected: (_) => onToggle(season.id),
            ),
        ],
      ),
    );
  }
}

class _PieceRow extends StatelessWidget {
  const _PieceRow({
    required this.piece,
    required this.season,
    required this.projectSeasons,
  });

  final PieceView piece;
  final SeasonView season;
  final List<SeasonView> projectSeasons;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final byId = {for (final s in projectSeasons) s.id: s};
    String nameOf(String id) {
      final s = byId[id];
      // A repertoire season the projection does not know yet (dangling
      // reference) renders its raw id instead of hiding the row.
      if (s == null) return id;
      return s.title ?? l10n.seasonsDefaultTitle(s.number);
    }

    final seasonNames = [for (final id in piece.seasonIds) nameOf(id)];
    final title = piece.notes.isEmpty
        ? (piece.categoryName ?? l10n.fundusTitle)
        : piece.notes;
    final detailSeason = fundusDetailSeason(
      piece: piece,
      activeSeason: season,
      projectSeasons: projectSeasons,
    );

    return ListTile(
      key: Key('fundus-row-${piece.id}'),
      leading: const CircleAvatar(
        child: Icon(Icons.checkroom_outlined, size: 20),
      ),
      title: Text(title),
      subtitle: seasonNames.isEmpty
          ? null
          : Text(l10n.fundusRepertoireSeasons(seasonNames.join(' · '))),
      trailing: const Icon(Icons.chevron_right),
      onTap: detailSeason == null
          ? null
          : () => pushFundusDestination(context, detailSeason, piece),
    );
  }
}

/// The established stale treatment — a warning row above the results (the
/// same tone the read screens use); pull-to-refresh re-reconciles.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      key: const Key('fundus-stale-banner'),
      leading: Icon(
        Icons.sync_problem_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(message),
    ),
  );
}
