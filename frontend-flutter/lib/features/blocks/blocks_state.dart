// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-block command: ephemeral
/// UI state keyed by the server-assigned `id` — never written to Drift.
class BlockOverlay implements ReconciliationOverlay {
  const BlockOverlay({
    required this.id,
    required this.status,
    this.number,
    this.warning,
  });

  @override
  final String id;

  /// Block number carried from the submitted form (display-only field).
  final int? number;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  BlockOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => BlockOverlay(
    id: id,
    number: number,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockOverlay &&
          other.id == id &&
          other.number == number &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, number, status, warning);
}

/// One row rendered by `BlocksScreen`: either an authoritative projected
/// Drift row or an ephemeral optimistic overlay.
sealed class BlockRow {
  const BlockRow();
}

class ProjectedBlockRow extends BlockRow {
  const ProjectedBlockRow(this.block);

  /// The generated read DTO (`breakdown_api` `BlockView`); authoritative,
  /// comes from Drift only.
  final BlockView block;
}

class OptimisticBlockRow extends BlockRow {
  const OptimisticBlockRow(this.overlay);

  final BlockOverlay overlay;
}

/// Controller state shape (seasons reference pattern): [projected] carries
/// only the projected rows' async state, [cachedRows] is the retained
/// last-good Drift snapshot, [overlays] is the ephemeral optimistic layer
/// merged on top by `id`.
class BlocksScreenState {
  const BlocksScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<BlockView>> projected;
  final List<BlockView> cachedRows;
  final bool isStale;
  final List<BlockOverlay> overlays;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// The `*.not-found` problem of a deleted parent (D5): the screen renders
  /// the 404 narrative with a back affordance instead of stale rows.
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

  /// The merged list a screen renders: authoritative projected Drift rows
  /// first, with server-acknowledged optimistic overlays layered below
  /// (merged by `id` — a projected row carrying an overlay's id wins).
  List<BlockRow> get rows {
    final projectedIds = {for (final b in cachedRows) b.id};
    return <BlockRow>[
      for (final b in cachedRows) ProjectedBlockRow(b),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticBlockRow(o),
    ];
  }
}
