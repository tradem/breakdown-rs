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
  });

  final List<SeasonView> rows;

  /// `true` when the served rows are from an expired cache (D2) or a failed
  /// refetch left only stale cached rows (D4).
  final bool isStale;

  /// Non-null when the last fetch failed. The rows are still served (retained
  /// stale rows, D4) so the screen never goes blank on a transient error.
  final ProblemError? error;

  @override
  String toString() =>
      'SeasonsView(rows: ${rows.length}, isStale: $isStale, error: $error)';
}
