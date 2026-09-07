// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../data/scene_shoot_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;
export '../../data/scene_shoot_repository.dart'
    show
        applyActualOrderOptimistic,
        applyFinishOptimistic,
        applyReplanOptimistic,
        applySkipOptimistic,
        applyStartOptimistic,
        mergeSceneShootOverlays,
        shouldClearSceneShootOverlay;

/// Day-board scope: the shooting day whose shoots render, the scene in
/// context, and the season scoping the membership gate.
///
/// `sceneId` travels the list route's path (the backend lists by day and
/// ignores it — path-only, like `PlanSceneShootRequest`'s path ids) and
/// provides the scene context for plan commands. `seasonId` scopes the
/// continuity AUTHZ-GATE. All three come from the read DTOs the user acts
/// on (scene detail) — never from a second projection lookup (CQRS
/// boundary: the client must not derive command context from another
/// read-model call).
class SceneShootDayScope {
  const SceneShootDayScope({
    required this.dayId,
    required this.sceneId,
    required this.seasonId,
  });

  final String dayId;
  final String sceneId;
  final String seasonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneShootDayScope &&
          other.dayId == dayId &&
          other.sceneId == sceneId &&
          other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(dayId, sceneId, seasonId);
}

/// Controller-state optimistic overlay for a scene-shoot command: the
/// full optimistic row applied after 2xx plus the acknowledged version.
/// Entries clear by the **version fence**
/// ([shouldClearSceneShootOverlay]): the overlay survives stale projections
/// carrying an older `version`.
class SceneShootRowOverlay implements ReconciliationOverlay {
  const SceneShootRowOverlay({
    required this.id,
    required this.overlay,
    required this.acknowledgedVersion,
    required this.status,
    this.warning,
  });

  @override
  final String id;

  /// The optimistic row (start/finish/skip/order/notes applied after 2xx).
  final SceneShootView overlay;

  /// The `AggregateVersion` the command acknowledgement returned. The fence
  /// clears this overlay only when the projection reaches it.
  final int acknowledgedVersion;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  SceneShootRowOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => SceneShootRowOverlay(
    id: id,
    overlay: overlay,
    acknowledgedVersion: acknowledgedVersion,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneShootRowOverlay &&
          other.id == id &&
          other.overlay == overlay &&
          other.acknowledgedVersion == acknowledgedVersion &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode =>
      Object.hash(id, overlay, acknowledgedVersion, status, warning);
}

/// One row rendered by `SceneShootsScreen` (server order — never re-sorted).
sealed class SceneShootRow {
  const SceneShootRow();
}

class ProjectedSceneShootRow extends SceneShootRow {
  const ProjectedSceneShootRow(this.shoot);

  /// The generated read DTO (`breakdown_api` `SceneShootView`);
  /// authoritative, comes from Drift only, in
  /// `COALESCE(actual_order, planned_order) ASC`.
  final SceneShootView shoot;
}

class OptimisticSceneShootRow extends SceneShootRow {
  const OptimisticSceneShootRow(this.overlay);

  final SceneShootRowOverlay overlay;
}

/// Controller state shape (seasons reference pattern).
class SceneShootsScreenState {
  const SceneShootsScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<SceneShootView>> projected;

  /// Complete day projection in server order.
  final List<SceneShootView> cachedRows;
  final bool isStale;
  final List<SceneShootRowOverlay> overlays;

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

  /// The merged list the screen renders: authoritative rows (server order)
  /// with row-level optimistic overlays applied by the version fence, plus
  /// create-path overlays appended.
  List<SceneShootRow> get rows {
    final merged = mergeSceneShootOverlays(
      projected: cachedRows,
      overlays: {
        for (final o in overlays)
          o.id: (
            overlay: o.overlay,
            acknowledgedVersion: o.acknowledgedVersion,
          ),
      },
    );
    final overlayById = {for (final o in overlays) o.id: o};
    return [
      for (final shoot in merged)
        if (overlayById[shoot.id] case final o?
            when identical(shoot, o.overlay))
          OptimisticSceneShootRow(o)
        else
          ProjectedSceneShootRow(shoot),
    ];
  }
}
