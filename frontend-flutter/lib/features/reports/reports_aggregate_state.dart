// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import 'reports_state.dart' show PdfCardState;

/// The aggregate report scope kind: the backend serves the aggregation at
/// exactly two scopes (issue #571) — the season and the episode.
enum ReportAggregateScopeKind { season, episode }

/// Scope for the aggregated Soll-Ist screen: which scope's report renders
/// and the season scoping the membership gate. All three come from the
/// read DTOs / nav context the user is acting on — never from a second
/// projection lookup (client CQRS boundary).
class ReportsAggregateScope {
  const ReportsAggregateScope({
    required this.kind,
    required this.id,
    required this.seasonId,
    required this.label,
  });

  final ReportAggregateScopeKind kind;
  final String id;
  final String seasonId;

  /// Human-readable scope label for the app bar and the PDF filename (the
  /// acted-on season title / episode label — nav context, never refetched).
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportsAggregateScope &&
          other.kind == kind &&
          other.id == id &&
          other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(kind, id, seasonId);
}

/// Controller state shape for the aggregated Soll-Ist screen (seasons
/// reference pattern). Finality and day counts are the SERVER's fields of
/// the `AggregateSollIstReport` DTO — rendered verbatim, never recomputed
/// client-side (issue #571 decision 2).
class ReportsAggregateScreenState {
  const ReportsAggregateScreenState({
    required this.sollIst,
    this.pdf,
    this.commandError,
    this.accessDenial,
  });

  /// The aggregated report DTO (rows + `isFinal` + day counts).
  final AsyncValue<AggregateSollIstReport> sollIst;

  /// The single PDF card state for this scope's aggregate PDF (idle until
  /// the user fetches — no prefetching).
  final PdfCardState? pdf;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// Local AUTHZ-GATE denial — zero requests while unresolved or denied.
  final ProblemError? accessDenial;
}
