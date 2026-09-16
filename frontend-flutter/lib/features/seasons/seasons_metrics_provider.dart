// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';

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
/// verdict's inputs change — INCLUDING the TTL boundary itself: the provider
/// schedules a one-shot invalidation at the EARLIEST per-entry TTL expiry
/// (the [clockProvider] clock is stable, so a memoized fresh verdict would
/// otherwise never flip to stale while the screen is open). The timer is
/// cancelled on dispose ([Ref.onDispose]) so tests see no pending timers.
///
/// Errors are surfaced, never swallowed: the provider resolves to
/// [AsyncError] on a DAO failure and the screen degrades to cards WITHOUT
/// a metadata line (`AsyncValue.asData` → `null` map — the Err branch of
/// the task 2.1 merge).
final seasonMetricsProvider = FutureProvider<Map<String, SeasonMetrics>>((
  ref,
) async {
  // Refresh triggers: the projection controller (fetch/refetch) and the
  // TTL staleness input — same refresh boundaries the list screen uses.
  ref.watch(seasonsViewControllerProvider);
  ref.watch(seasonsCacheStaleProvider);

  final clock = ref.watch(clockProvider);
  final dao = SeasonMetricsDao(ref.watch(cacheDatabaseProvider));
  final res = await dao.readAll(ttl: kCacheTtl, clock: clock);
  final metrics = res.match((err) => throw err, (m) => m);

  // TTL-boundary invalidation (review fix): recompute when the freshest
  // verdict's next expiry crosses, so "fresh" deterministically flips to
  // stale without waiting for another projection event. Only future
  // boundaries schedule a timer; an already-stale set re-evaluates on the
  // next normal invalidation as before.
  final now = clock.now();
  Duration? earliest;
  for (final m in metrics.values) {
    final until = m.cachedAt.add(kCacheTtl).difference(now);
    if (until > Duration.zero && (earliest == null || until < earliest)) {
      earliest = until;
    }
  }
  if (earliest != null) {
    Timer? timer;
    timer = Timer(earliest, () {
      if (ref.mounted) ref.invalidateSelf();
    });
    ref.onDispose(() => timer?.cancel());
  }
  return metrics;
});
