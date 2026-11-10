// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../../core/problem_error.dart';

/// The projection a screen reads from (Design Decision D1/D4).
///
/// The screen consumes only this value — never the API client or the cache
/// directly. [rows] is the latest good snapshot; [isStale] is derived from the
/// cache TTL or a failed refetch (D2/D4); [error] carries a surfaced fetch
/// failure so the UI can render a retry affordance instead of silently
/// discarding it (Task 3.3).
class SeasonsView {
  const SeasonsView({
    required this.rows,
    required this.isStale,
    this.error,
    this.isLoaded = false,
  });

  final List<SeasonView> rows;

  /// `true` when the served rows are from an expired cache (D2) or a failed
  /// refetch left only stale cached rows (D4).
  final bool isStale;

  /// Non-null when the last fetch failed. The rows are still served (retained
  /// stale rows, D4) so the screen never goes blank on a transient error.
  final ProblemError? error;

  /// `true` only when [rows] came from a **successful** read of the projection
  /// (issue #817).
  ///
  /// [rows] is deliberately always usable — cached rows while the fetch is in
  /// flight, retained rows after a failure — so "has rows" says nothing about
  /// whether the projection is authoritative. A consumer that has to *prove* a
  /// row is gone (evicting a persisted reference, #817) must ask this flag
  /// instead: an unloaded or failed view is not evidence of absence. The
  /// default is `false` (fail-closed: never treat rows as authoritative by
  /// omission).
  final bool isLoaded;

  @override
  String toString() =>
      'SeasonsView(rows: ${rows.length}, isStale: $isStale, '
      'isLoaded: $isLoaded, error: $error)';
}
