// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../data/outfit_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;
export '../../data/outfit_repository.dart' show shouldClearOutfitOverlay;

/// The command surface a failure belongs to — fitting photos vs. look writes.
/// The banner routes the localized copy by this ORIGIN, never by the code
/// prefix (a photo command can fail with `domain.validation`).
enum OutfitCommandSurface { outfit, photo }

/// A command failure with its originating surface.
class OutfitCommandFailure {
  const OutfitCommandFailure(this.surface, this.error);

  final OutfitCommandSurface surface;
  final ProblemError error;
}

/// Controller-state optimistic overlay for one look: ephemeral UI state keyed
/// by outfit id — never in Drift.
///
/// Cleared by the **version fence** ([shouldClearOutfitOverlay]) so a stale
/// projection carrying an older `version` cannot restore the pre-command row.
class OutfitRowOverlay implements ReconciliationOverlay {
  const OutfitRowOverlay({
    required this.id,
    required this.overlay,
    required this.acknowledgedVersion,
    required this.status,
    this.warning,
  });

  @override
  final String id;

  /// The optimistic row state after the 2xx acknowledgement.
  final OutfitView overlay;

  /// The `AggregateVersion` the command acknowledgement returned.
  final int acknowledgedVersion;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  OutfitRowOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => OutfitRowOverlay(
    id: id,
    overlay: overlay,
    acknowledgedVersion: acknowledgedVersion,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutfitRowOverlay &&
          other.id == id &&
          other.overlay == overlay &&
          other.acknowledgedVersion == acknowledgedVersion &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode =>
      Object.hash(id, overlay, acknowledgedVersion, status, warning);
}

/// One rendered row of the character's look list.
sealed class OutfitRow {
  const OutfitRow();
}

/// Authoritative row from the projection (no pending edit).
class ProjectedOutfitRow extends OutfitRow {
  const ProjectedOutfitRow(this.outfit);

  final OutfitView outfit;
}

/// Row still showing the optimistic edit (the fence has not passed yet).
class OptimisticOutfitRow extends OutfitRow {
  const OptimisticOutfitRow(this.overlay);

  final OutfitRowOverlay overlay;
}

/// The projection a screen reads (seasons reference pattern): the character's
/// looks plus the TTL staleness verdict.
class OutfitsView {
  const OutfitsView({required this.rows, required this.isStale, this.error});

  final List<OutfitView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Controller state of one character's look list.
class OutfitsScreenState {
  const OutfitsScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<OutfitView>> projected;

  /// Complete character projection (the fence merges overlays over these).
  final List<OutfitView> cachedRows;
  final bool isStale;
  final List<OutfitRowOverlay> overlays;

  /// Last command failure (with its originating surface).
  final OutfitCommandFailure? commandError;

  /// The `*.not-found` problem of a deleted parent (character/season).
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

  /// Rows to render: projected rows with fence-held optimistic edits applied.
  /// An overlay whose id is absent from the projection appends (create path).
  List<OutfitRow> get rows {
    final projectedById = {for (final o in cachedRows) o.id: o};
    final overlayById = {for (final o in overlays) o.id: o};
    return <OutfitRow>[
      for (final outfit in cachedRows)
        if (overlayById[outfit.id] case final pending?
            when !shouldClearOutfitOverlay(
              projection: outfit,
              acknowledgedVersion: pending.acknowledgedVersion,
            ))
          OptimisticOutfitRow(pending)
        else
          ProjectedOutfitRow(outfit),
      for (final overlay in overlays)
        if (!projectedById.containsKey(overlay.id))
          OptimisticOutfitRow(overlay),
    ];
  }

  /// Closest view of one overlay's row (for detail screens that render a
  /// single look while its edit reconciles).
  OutfitView? rowById(String id) {
    for (final row in rows) {
      final outfit = switch (row) {
        ProjectedOutfitRow(:final outfit) => outfit,
        OptimisticOutfitRow(:final overlay) => overlay.overlay,
      };
      if (outfit.id == id) return outfit;
    }
    return null;
  }
}
