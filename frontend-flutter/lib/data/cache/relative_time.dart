// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'clock.dart';

/// German relative age of a cache write for the season-card stale
/// indicator (`redesign-seasons-home` task 2.3, design D2).
///
/// Pure formatting over an injected [clock] — never calls `DateTime.now`
/// directly, so tests pin a [Clock.fixed] and stay hermetic
/// (deterministic-tests rule, AGENTS.md §6). Coarse buckets only: the
/// indicator is a subtle freshness hint, not a clock.
String relativeTimeSince(DateTime when, {Clock clock = Clock.system}) {
  final diff = clock.now().difference(when);
  if (diff < const Duration(minutes: 1)) return 'gerade eben';
  if (diff < const Duration(hours: 1)) return 'vor ${diff.inMinutes} min';
  if (diff < const Duration(hours: 24)) return 'vor ${diff.inHours} h';
  return 'vor ${diff.inDays} d';
}
