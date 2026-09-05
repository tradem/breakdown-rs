// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-scene command:
/// ephemeral UI state keyed by the server-assigned `id` — never in Drift.
class SceneOverlay implements ReconciliationOverlay {
  const SceneOverlay({
    required this.id,
    required this.status,
    this.summary,
    this.sceneNumber,
    this.warning,
  });

  @override
  final String id;

  /// Summary carried from the submitted form (display-only field).
  final String? summary;

  /// Scene number carried from the submitted form (display-only field).
  final int? sceneNumber;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  SceneOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => SceneOverlay(
    id: id,
    summary: summary,
    sceneNumber: sceneNumber,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneOverlay &&
          other.id == id &&
          other.summary == summary &&
          other.sceneNumber == sceneNumber &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, summary, sceneNumber, status, warning);
}

/// One row rendered by `ScenesScreen`.
sealed class SceneRow {
  const SceneRow();
}

class ProjectedSceneRow extends SceneRow {
  const ProjectedSceneRow(this.scene);

  /// The generated read DTO (`breakdown_api` `SceneView`); authoritative,
  /// comes from Drift only.
  final SceneView scene;
}

class OptimisticSceneRow extends SceneRow {
  const OptimisticSceneRow(this.overlay);

  final SceneOverlay overlay;
}

/// Controller state shape (seasons reference pattern).
class ScenesScreenState {
  const ScenesScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<SceneView>> projected;
  final List<SceneView> cachedRows;
  final bool isStale;
  final List<SceneOverlay> overlays;

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

  List<SceneRow> get rows {
    final projectedIds = {for (final s in cachedRows) s.id};
    return <SceneRow>[
      for (final s in cachedRows) ProjectedSceneRow(s),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticSceneRow(o),
    ];
  }
}
