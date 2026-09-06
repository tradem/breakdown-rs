// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-shooting-day command:
/// ephemeral UI state keyed by the server-assigned `id` — never in Drift.
class ShootingDayOverlay implements ReconciliationOverlay {
  const ShootingDayOverlay({
    required this.id,
    required this.status,
    this.label,
    this.orderKey,
    this.warning,
  });

  @override
  final String id;

  final String? label;
  final String? orderKey;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  ShootingDayOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => ShootingDayOverlay(
    id: id,
    label: label,
    orderKey: orderKey,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShootingDayOverlay &&
          other.id == id &&
          other.label == label &&
          other.orderKey == orderKey &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, label, orderKey, status, warning);
}

/// One row rendered by `ShootingDaysScreen` (server order — never re-sorted).
sealed class ShootingDayRow {
  const ShootingDayRow();
}

class ProjectedShootingDayRow extends ShootingDayRow {
  const ProjectedShootingDayRow(this.day);

  /// The generated read DTO (`breakdown_api` `ShootingDayView`);
  /// authoritative, comes from Drift only, in `order_key ASC`.
  final ShootingDayView day;
}

class OptimisticShootingDayRow extends ShootingDayRow {
  const OptimisticShootingDayRow(this.overlay);

  final ShootingDayOverlay overlay;
}

/// Controller state shape (seasons reference pattern).
class ShootingDaysScreenState {
  const ShootingDaysScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<ShootingDayView>> projected;

  /// Complete episode projection in server order.
  final List<ShootingDayView> cachedRows;
  final bool isStale;
  final List<ShootingDayOverlay> overlays;

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
  /// plus optimistic overlays by `id`.
  List<ShootingDayRow> get rows {
    final projectedIds = {for (final d in cachedRows) d.id};
    return <ShootingDayRow>[
      for (final d in cachedRows) ProjectedShootingDayRow(d),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticShootingDayRow(o),
    ];
  }
}
