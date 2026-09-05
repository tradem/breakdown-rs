// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-episode command:
/// ephemeral UI state keyed by the server-assigned `id` — never in Drift.
class EpisodeOverlay implements ReconciliationOverlay {
  const EpisodeOverlay({
    required this.id,
    required this.status,
    this.number,
    this.name,
    this.warning,
  });

  @override
  final String id;

  /// Episode number carried from the submitted form (display-only field).
  final int? number;

  /// Episode name carried from the submitted form (display-only field).
  final String? name;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  EpisodeOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => EpisodeOverlay(
    id: id,
    number: number,
    name: name,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeOverlay &&
          other.id == id &&
          other.number == number &&
          other.name == name &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, number, name, status, warning);
}

/// One row rendered by `EpisodesScreen`.
sealed class EpisodeRow {
  const EpisodeRow();
}

class ProjectedEpisodeRow extends EpisodeRow {
  const ProjectedEpisodeRow(this.episode);

  /// The generated read DTO (`breakdown_api` `EpisodeView`); authoritative,
  /// comes from Drift only.
  final EpisodeView episode;
}

class OptimisticEpisodeRow extends EpisodeRow {
  const OptimisticEpisodeRow(this.overlay);

  final EpisodeOverlay overlay;
}

/// Controller state shape (seasons reference pattern).
class EpisodesScreenState {
  const EpisodesScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<EpisodeView>> projected;
  final List<EpisodeView> cachedRows;
  final bool isStale;
  final List<EpisodeOverlay> overlays;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// The `*.not-found` problem of a deleted parent (D5).
  ProblemError? get notFound {
    final p = projected;
    if (p is AsyncError) {
      final error = p.error;
      if (error is ProblemError && error.code.endsWith('.not-found')) {
        return error;
      }
    }
    return null;
  }

  List<EpisodeRow> get rows {
    final projectedIds = {for (final e in cachedRows) e.id};
    return <EpisodeRow>[
      for (final e in cachedRows) ProjectedEpisodeRow(e),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticEpisodeRow(o),
    ];
  }
}
