// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Generation fence for cache writes (task 6.3).
///
/// A fetch captures the current [generation] when it starts; before
/// persisting, the repository asks [isCurrentGeneration] whether that
/// generation still holds. A base switch or sign-out reset bumps the
/// generation first — a late pre-reset write is then discarded (returned to
/// its caller, never persisted), so rows from one identity/backend cannot
/// leak into the next. Pure Dart, Tier-1 testable.
class CacheWriteFence {
  const CacheWriteFence({
    required this.generation,
    required this.isCurrentGeneration,
  });

  /// Generation captured at fetch start.
  final int generation;

  /// Whether [generation] is still current at write time.
  final bool Function(int generation) isCurrentGeneration;
}

/// Cache-write generation (task 6.3): bumped by the session-reset
/// coordinator before every Drift clear (sign-out and backend switch), so
/// in-flight reads fence themselves out. KeepAlive by construction (plain
/// [NotifierProvider] defaults to it) — the epoch must survive screen
/// disposal, or a reset generation would compare equal to a fresh zero.
class CacheGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final cacheGenerationProvider = NotifierProvider<CacheGeneration, int>(
  CacheGeneration.new,
);
