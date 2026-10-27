// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

library;

import 'package:breakdown_api/breakdown_api.dart';

import '../omni_search/name_prefilter.dart';

/// Tier-1 pure model of the fundus browse (OpenSpec change
/// `flutter-fundus-search`, tasks §1.1).
///
/// No Flutter, no Drift, no Riverpod: the cached inputs, the repertoire
/// scope rule, and the matched rows. The name prefilter reuses the single
/// [foldForSearch] contract from the OmniSearch feature (case- and
/// diacritics-insensitive dictionary folding — never fuzzy matching).

/// The cached fundus universe of ONE active project.
class FundusInputs {
  const FundusInputs({
    required this.projectId,
    required this.pieces,
    required this.seasons,
    required this.stale,
  });

  final String projectId;

  /// Every piece the project-scoped cache slice holds (including rows
  /// whose repertoire is empty — the matcher applies the exclusion).
  final List<PieceView> pieces;

  /// The project's seasons, used for the season chips and the scope rule.
  final List<SeasonView> seasons;

  /// TTL staleness verdict from the project slice's `cachedAt` column.
  final bool stale;

  Set<String> get seasonIds => {for (final s in seasons) s.id};
}

/// The renderable fundus state.
class FundusViewState {
  const FundusViewState({
    required this.text,
    required this.selectedSeasonIds,
    required this.projectSeasons,
    required this.rows,
    required this.zeroMatch,
    required this.loaded,
    required this.stale,
  });

  final String text;

  final Set<String> selectedSeasonIds;

  /// The project's seasons (season-chip model, design D4).
  final List<SeasonView> projectSeasons;

  /// Matched pieces in cache snapshot order (server order — no client
  /// re-sort). The widget resolves repertoire season NAMES from
  /// [projectSeasons] (localization stays in the widget layer).
  final List<PieceView> rows;

  /// Non-empty query with no hits — the zero-match narrative echoes the
  /// active season filter.
  final bool zeroMatch;

  /// Whether a bounded prefetch pass has completed for this project: an
  /// empty, completed pass is genuinely empty; an empty, unfinished one is
  /// not-yet-loaded.
  final bool loaded;

  final bool stale;

  bool get hasRows => rows.isNotEmpty;
}

/// Filters [pieces] to the fundus contract (design D2/D4).
///
/// A piece is in the fundus when ALL hold:
/// - its repertoire is non-empty (non-repertoire pieces are excluded),
/// - its repertoire intersects [projectSeasonIds] (foreign-project rows are
///   excluded even if a stale cache holds them),
/// - when [selectedSeasonIds] is non-empty, its repertoire intersects the
///   selected seasons,
/// - when [text] is non-blank, the folded query is a substring of the folded
///   notes OR the folded category name (the pinned field contract — no
///   `details`/`photos` creep).
List<PieceView> matchFundus({
  required List<PieceView> pieces,
  required Set<String> projectSeasonIds,
  required Set<String> selectedSeasonIds,
  required String text,
}) {
  final foldedQuery = foldForSearch(text.trim());
  final result = <PieceView>[];
  for (final piece in pieces) {
    final repertoire = piece.seasonIds;
    if (repertoire.isEmpty) continue;
    if (!repertoire.any(projectSeasonIds.contains)) continue;
    if (selectedSeasonIds.isNotEmpty &&
        !repertoire.any(selectedSeasonIds.contains)) {
      continue;
    }
    if (foldedQuery.isNotEmpty) {
      final haystack =
          '${foldForSearch(piece.notes)} '
          '${foldForSearch(piece.categoryName ?? '')}';
      if (!haystack.contains(foldedQuery)) continue;
    }
    result.add(piece);
  }
  return result;
}
