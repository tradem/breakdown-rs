// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-category command:
/// ephemeral UI state keyed by the server-assigned `id` — never in Drift.
class CostumeCategoryOverlay implements ReconciliationOverlay {
  const CostumeCategoryOverlay({
    required this.id,
    required this.status,
    this.name,
    this.orderKey,
    this.warning,
  });

  @override
  final String id;

  /// Category name carried from the submitted form (display-only field).
  final String? name;

  /// Derived order key carried from the submitted form (display-only field).
  final String? orderKey;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  CostumeCategoryOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => CostumeCategoryOverlay(
    id: id,
    name: name,
    orderKey: orderKey,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostumeCategoryOverlay &&
          other.id == id &&
          other.name == name &&
          other.orderKey == orderKey &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, name, orderKey, status, warning);
}

/// One row rendered by `CostumeCategoriesScreen`.
sealed class CostumeCategoryRow {
  const CostumeCategoryRow();
}

class ProjectedCostumeCategoryRow extends CostumeCategoryRow {
  const ProjectedCostumeCategoryRow(this.category);

  /// The generated read DTO (`breakdown_api` `CostumeCategoryView`);
  /// authoritative, comes from Drift only.
  final CostumeCategoryView category;
}

class OptimisticCostumeCategoryRow extends CostumeCategoryRow {
  const OptimisticCostumeCategoryRow(this.overlay);

  final CostumeCategoryOverlay overlay;
}

/// Controller state shape (seasons reference pattern + [showArchived]
/// render toggle: archived categories are hidden behind an explicit toggle,
/// never silently unlisted).
class CostumeCategoriesScreenState {
  const CostumeCategoriesScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
    this.showArchived = false,
  });

  final AsyncValue<List<CostumeCategoryView>> projected;

  /// Complete season projection (archived rows included — derivation reads
  /// this, never the filtered render list).
  final List<CostumeCategoryView> cachedRows;
  final bool isStale;
  final List<CostumeCategoryOverlay> overlays;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// Render-only toggle (default off). Affects rendering only — order-key
  /// derivation always reads the complete [cachedRows].
  final bool showArchived;

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

  /// The merged list the screen renders: authoritative rows (archived
  /// filtered unless [showArchived]) plus optimistic overlays by `id`.
  List<CostumeCategoryRow> get rows {
    final projectedIds = {for (final c in cachedRows) c.id};
    return <CostumeCategoryRow>[
      for (final c in cachedRows)
        if (showArchived || !c.archived) ProjectedCostumeCategoryRow(c),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticCostumeCategoryRow(o),
    ];
  }
}
