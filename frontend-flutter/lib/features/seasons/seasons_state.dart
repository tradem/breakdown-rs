// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// The controller-state optimistic overlay entry (spec `OverlayEntry`;
/// renamed to avoid the collision with Flutter's `OverlayEntry`). It is
/// ephemeral UI state keyed by the server-assigned `id` from
/// `IdVersionResponse` — never written to Drift (D2: Drift holds only
/// projected rows).
class SeasonOverlay implements ReconciliationOverlay {
  const SeasonOverlay({
    required this.id,
    required this.status,
    this.name,
    this.number,
    this.warning,
  });

  /// Server-assigned id (from the command's 2xx acknowledgement).
  @override
  final String id;

  /// Display name carried from the Create Season form so the row renders
  /// immediately; the authoritative value arrives with the projected row.
  final String? name;

  /// Season number carried from the submitted form (display-only field).
  final int? number;

  @override
  final OverlayStatus status;

  /// Non-fatal warning shown when [status] is [OverlayStatus.stale].
  @override
  final String? warning;

  @override
  SeasonOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => copyWith(
    status: status,
    warning: warning,
    clearWarning: clearWarning ? () {} : null,
  );

  SeasonOverlay copyWith({
    OverlayStatus? status,
    String? warning,
    void Function()? clearWarning,
  }) => SeasonOverlay(
    id: id,
    name: name,
    number: number,
    status: status ?? this.status,
    warning: clearWarning != null ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonOverlay &&
          other.id == id &&
          other.name == name &&
          other.number == number &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, name, number, status, warning);

  @override
  String toString() => 'SeasonOverlay($id, $status)';
}

/// One row rendered by `SeasonsScreen`: either an authoritative projected
/// Drift row or an ephemeral optimistic overlay (the merged view of
/// `SeasonsScreenState.rows`).
sealed class SeasonRow {
  const SeasonRow();
}

class ProjectedSeasonRow extends SeasonRow {
  const ProjectedSeasonRow(this.season);

  /// The generated read DTO (`breakdown_api` `SeasonView` — the spec's
  /// `SeasonDto`); authoritative, comes from Drift only.
  final SeasonView season;
}

class OptimisticSeasonRow extends SeasonRow {
  const OptimisticSeasonRow(this.overlay);

  final SeasonOverlay overlay;
}

/// Controller state shape (spec `flutter-first-screen`, D2).
///
/// [projected] carries only the projected rows' async state (loading /
/// data / error) — overlay metadata never lives inside it.
/// [cachedRows] is the retained last-good Drift snapshot (offline cold
/// start / failed refetch, per the `add-drift-read-cache` contract).
/// [overlays] is the ephemeral optimistic layer merged on top by `id`.
class SeasonsScreenState {
  const SeasonsScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  /// Async state of the seasons read projection.
  final AsyncValue<List<SeasonView>> projected;

  /// Authoritative rows (Drift-backed; retained snapshot on refetch error).
  final List<SeasonView> cachedRows;

  /// True when the served rows come from an expired/retained cache.
  final bool isStale;

  /// Ephemeral optimistic overlay entries (controller state, never Drift).
  final List<SeasonOverlay> overlays;

  /// Last command failure keyed by its stable problem `code` (the screen
  /// surfaces localized copy, never the server `detail` text).
  final ProblemError? commandError;

  /// The merged list a screen renders: authoritative projected Drift rows
  /// first, with server-acknowledged optimistic overlays layered below
  /// (merged by `id`). A projected row carrying an overlay's id wins — the
  /// reconciliation drop may not have run yet, but the merge never doubles
  /// or hides the projected data (D2).
  List<SeasonRow> get rows {
    final projectedIds = {for (final s in cachedRows) s.id};
    return <SeasonRow>[
      for (final s in cachedRows) ProjectedSeasonRow(s),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticSeasonRow(o),
    ];
  }

  SeasonsScreenState copyWith({
    AsyncValue<List<SeasonView>>? projected,
    List<SeasonView>? cachedRows,
    bool? isStale,
    List<SeasonOverlay>? overlays,
  }) => SeasonsScreenState(
    projected: projected ?? this.projected,
    cachedRows: cachedRows ?? this.cachedRows,
    isStale: isStale ?? this.isStale,
    overlays: overlays ?? this.overlays,
    commandError: commandError,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonsScreenState &&
          other.projected == projected &&
          other.isStale == isStale &&
          other.commandError == commandError &&
          _sameRows(other.cachedRows, cachedRows) &&
          _sameOverlays(other.overlays, overlays);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    projected,
    isStale,
    commandError,
    ...cachedRows,
    ...overlays,
  ]);

  @override
  String toString() =>
      'SeasonsScreenState(projected: $projected, rows: ${cachedRows.length}, '
      'overlays: ${overlays.length}, isStale: $isStale, '
      'commandError: $commandError)';
}

bool _sameRows(List<SeasonView> a, List<SeasonView> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.number != y.number ||
        x.version != y.version ||
        x.title != y.title) {
      return false;
    }
  }
  return true;
}

bool _sameOverlays(List<SeasonOverlay> a, List<SeasonOverlay> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
