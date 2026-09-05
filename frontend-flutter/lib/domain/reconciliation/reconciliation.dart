// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

/// Shared projector-lag reconciliation machinery
/// (`flutter-hierarchy-navigation` D2, extracted from the seasons reference
/// screen): injectable backoff scheduler, generic overlay bookkeeping, and
/// the single-flight + acknowledgement-generation reconcile runner.
///
/// Rules: overlay only after 2xx, controller state never in Drift, bounded
/// retries, stale retention on exhaustion, late-ack follow-up passes.
library;

export 'overlay_store.dart';
export 'reconcile_coordinator.dart';
export 'reconciliation_scheduler.dart';
