// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

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

/// Controller-state optimistic overlay for a scene COSTUME BEAT command
/// (issue #546): ephemeral UI state keyed by the SCENE id — never in Drift.
///
/// Unlike [SceneOverlay] (whole-row create), this overlay carries the FULL
/// optimistic beat list of the scene (computed from the pre-command state
/// plus the acked change) and the acked aggregate version. The version is
/// the optimistic fence: the overlay is dropped only when the projected
/// scene row carries `version >= overlay.version` — never on a lagging
/// projection row.
class SceneBeatOverlay implements ReconciliationOverlay {
  const SceneBeatOverlay({
    required this.id,
    required this.version,
    required this.beats,
    required this.status,
    this.warning,
  });

  /// The SCENE id this overlay's beats belong to.
  @override
  final String id;

  /// The aggregate version echoed by the command's 2xx ack — the new
  /// scene version (optimistic fence + version source for follow-ups).
  final int version;

  /// The complete optimistic beat list of the scene (display rendering
  /// only; the projected list replaces it once the projection catches up).
  final List<SceneCostumeBeatView> beats;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  SceneBeatOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => SceneBeatOverlay(
    id: id,
    version: version,
    beats: beats,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  /// Returns the scene row with the overlay's optimistic beats applied
  /// (display-only; the projected row wins after the version-fenced drop).
  SceneView applyTo(SceneView row) => row.rebuild(
    (b) => b
      ..costumeBeats.replace(beats)
      ..version = version,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneBeatOverlay &&
          other.id == id &&
          other.version == version &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, version, status, warning);
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
    this.beatOverlays = const [],
    this.commandError,
  });

  final AsyncValue<List<SceneView>> projected;
  final List<SceneView> cachedRows;
  final bool isStale;
  final List<SceneOverlay> overlays;

  /// Ephemeral optimistic beat overlays per scene (issue #546), merged
  /// into [cachedRows] by the controller; the screen reads this for the
  /// reconciling/stale indicator.
  final List<SceneBeatOverlay> beatOverlays;

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
