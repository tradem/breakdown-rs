// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

/// Injectable clock so cache TTL / reconciliation tests are hermetic.
///
/// Foundation deterministic-tests rule (AGENTS.md §6): never call
/// [DateTime.now] directly inside cache logic — route through a [Clock] so
/// tests can advance time with a fake. [system] uses the real wall clock.
class Clock {
  const Clock([this._now]);

  /// Creates a clock pinned to [fixed], used by deterministic tests.
  factory Clock.fixed(DateTime fixed) => Clock(() => fixed);

  static const Clock system = Clock();

  final DateTime Function()? _now;

  DateTime now() => _now?.call() ?? DateTime.now();
}
