// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../data/costume_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;
export '../../data/costume_repository.dart'
    show
        applyAssignOptimistic,
        applyUnassignOptimistic,
        applyNotesOptimistic,
        applyAddDetailOptimistic,
        shouldClearCostumeOverlay,
        mergeCostumeOverlays;

/// Controller-state optimistic overlay for a costume-row command: ephemeral
/// UI state keyed by costume `id` — never in Drift.
///
/// Unlike create-shell overlays (which vanish by projected id), row-level
/// edits clear by the **version fence** ([shouldClearCostumeOverlay]): the
/// overlay survives stale projections carrying an older `version`.
class CostumeRowOverlay implements ReconciliationOverlay {
  const CostumeRowOverlay({
    required this.id,
    required this.overlay,
    required this.acknowledgedVersion,
    required this.status,
    this.warning,
  });

  @override
  final String id;

  /// The optimistic row (assignment / notes / details applied after 2xx).
  final CostumeView overlay;

  /// The `AggregateVersion` the command acknowledgement returned. The fence
  /// clears this overlay only when the projection reaches it.
  final int acknowledgedVersion;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  CostumeRowOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => CostumeRowOverlay(
    id: id,
    overlay: overlay,
    acknowledgedVersion: acknowledgedVersion,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostumeRowOverlay &&
          other.id == id &&
          other.overlay == overlay &&
          other.acknowledgedVersion == acknowledgedVersion &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode =>
      Object.hash(id, overlay, acknowledgedVersion, status, warning);
}

/// One row rendered by `CostumesScreen`.
sealed class CostumeRow {
  const CostumeRow();
}

class ProjectedCostumeRow extends CostumeRow {
  const ProjectedCostumeRow(this.costume, {required this.characterName});

  /// The generated read DTO (`breakdown_api` `CostumeView`); authoritative,
  /// comes from Drift only (or the merged overlay while reconciling).
  final CostumeView costume;

  /// Display name resolved from the characters projection (read-DTO join),
  /// or `null` when unassigned / unknown.
  final String? characterName;

  /// `true` while the version fence holds (the row shows the optimistic
  /// edit, not yet the projection).
  bool get reconciling => false;
}

class OptimisticCostumeRow extends CostumeRow {
  const OptimisticCostumeRow(this.overlay, {required this.characterName});

  final CostumeRowOverlay overlay;
  final String? characterName;
}

/// Controller state shape (seasons reference pattern).
class CostumesScreenState {
  const CostumesScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.characterNames = const {},
    this.commandError,
  });

  final AsyncValue<List<CostumeView>> projected;

  /// Complete season projection (the fence merges overlays over these).
  final List<CostumeView> cachedRows;
  final bool isStale;
  final List<CostumeRowOverlay> overlays;

  /// Character display names by id (read-DTO join from the characters
  /// projection — never aggregate reconstruction).
  final Map<String, String> characterNames;

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

  /// The merged list the screen renders: authoritative rows with
  /// fence-held optimistic edits applied (never a stale restore).
  ///
  /// An overlay renders as [OptimisticCostumeRow] while the cached
  /// projection is still behind the acknowledged version; once the fence
  /// passes the authoritative row renders as [ProjectedCostumeRow].
  /// Overlays for ids absent from the projection (create path) append.
  List<CostumeRow> get rows {
    final projectedById = {for (final c in cachedRows) c.id: c};
    final overlayById = {for (final o in overlays) o.id: o};
    return <CostumeRow>[
      for (final c in cachedRows)
        if (overlayById[c.id] case final pending?
            when !_fencePassed(c, pending.acknowledgedVersion))
          OptimisticCostumeRow(
            pending,
            characterName: characterNames[pending.overlay.characterId],
          )
        else
          ProjectedCostumeRow(c, characterName: characterNames[c.characterId]),
      for (final o in overlays)
        if (!projectedById.containsKey(o.id))
          OptimisticCostumeRow(
            o,
            characterName: characterNames[o.overlay.characterId],
          ),
    ];
  }

  bool _fencePassed(CostumeView row, int acknowledged) =>
      shouldClearCostumeOverlay(
        projection: row,
        acknowledgedVersion: acknowledged,
      );
}
