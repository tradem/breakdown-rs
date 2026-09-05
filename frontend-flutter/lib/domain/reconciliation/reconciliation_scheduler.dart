// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reconciliation_scheduler.g.dart';

/// Bounded-retry budget for the projector-lag reconciliation
/// (`flutter-first-screen` D2/D3, shared by every hierarchy screen —
/// `flutter-hierarchy-navigation` D2). The first attempt runs immediately;
/// later attempts wait on [ReconciliationScheduler].
const int kMaxReconcileAttempts = 4;

/// Non-fatal warning retained with a stale overlay after retry exhaustion
/// (D3). Client-side copy — screens never show server `detail` text.
const String kReconcileStaleWarning =
    'Created — the list is still catching up. Pull to refresh.';

/// Injectable backoff seam so reconciliation tests are deterministic
/// (AGENTS.md §6: never gate a test on wall-clock / real `Future.delayed`).
abstract class ReconciliationScheduler {
  const ReconciliationScheduler();

  /// Waits before reconciliation attempt [attempt] (0-based, so the first
  /// pass through the runner never sleeps).
  Future<void> tick(int attempt);
}

/// Production scheduler: capped exponential backoff (500ms → 4s).
class ExponentialBackoffScheduler extends ReconciliationScheduler {
  const ExponentialBackoffScheduler();

  @override
  Future<void> tick(int attempt) =>
      Future<void>.delayed(const Duration(milliseconds: 500) * (1 << attempt));
}

/// The reconciliation backoff seam (overridden with a controllable fake in
/// tests).
@riverpod
ReconciliationScheduler reconciliationScheduler(Ref ref) =>
    const ExponentialBackoffScheduler();
