// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/cache_ttl.dart';
import '../../data/cache/season_metrics_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import 'seasons_state.dart';

/// Per-season cached metadata for the season cards (`redesign-seasons-home`
/// task 2.1, design D1).
///
/// Re-runs the read-only aggregation whenever the seasons projection
/// refreshes (a command's refetch invalidates the controller) or the TTL
/// verdict's inputs change. Errors are surfaced, never swallowed: the
/// provider resolves to [AsyncError] on a DAO failure and the screen
/// degrades to cards WITHOUT a metadata line (`AsyncValue.valueOrNull`
/// → `null` map — the Err branch of the task 2.1 merge).
final seasonMetricsProvider = FutureProvider<Map<String, SeasonMetrics>>((
  ref,
) async {
  // Refresh triggers: the projection controller (fetch/refetch) and the
  // TTL staleness input — same refresh boundaries the list screen uses.
  ref.watch(seasonsViewControllerProvider);
  ref.watch(seasonsCacheStaleProvider);

  final dao = SeasonMetricsDao(ref.watch(cacheDatabaseProvider));
  final res = await dao.readAll(
    ttl: kCacheTtl,
    clock: ref.watch(clockProvider),
  );
  return res.match((err) => throw err, (m) => m);
});
