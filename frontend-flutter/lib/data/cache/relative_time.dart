// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode)

import 'clock.dart';

/// Localized unit copy for [relativeTimeSince].
///
/// The data layer stays free of user-facing strings: it selects a coarse
/// bucket and the presentation layer supplies the wording through this
/// value object. That keeps the formatter deterministic and testable while
/// letting each locale render its own units (ADR-034: all user-facing copy
/// lives in the ARB catalogs, never inline in `lib/data/**`).
class RelativeTimeCopy {
  const RelativeTimeCopy({
    required this.justNow,
    required this.minutes,
    required this.hours,
    required this.days,
  });

  /// Text for a write younger than one minute.
  final String justNow;

  /// Renders `<n> minutes` in the target locale.
  final String Function(int count) minutes;

  /// Renders `<n> hours` in the target locale.
  final String Function(int count) hours;

  /// Renders `<n> days` in the target locale.
  final String Function(int count) days;
}

/// Localized unit copy for [relativeTimeUntil] (the future-facing twin of
/// [RelativeTimeCopy]).
class RelativeTimeUntilCopy {
  const RelativeTimeUntilCopy({
    required this.imminent,
    required this.minutes,
    required this.hours,
    required this.days,
  });

  /// Text for a due instant less than one minute away (or already past).
  final String imminent;

  /// Renders `<n> minutes` in the target locale.
  final String Function(int count) minutes;

  /// Renders `<n> hours` in the target locale.
  final String Function(int count) hours;

  /// Renders `<n> days` in the target locale.
  final String Function(int count) days;
}

/// Coarse time remaining until a future instant.
///
/// Used for the AI-import "next retry in …" ETA (issue #639): the live ticker
/// re-renders at most once per bucket, and an instant already in the past
/// reports [RelativeTimeUntilCopy.imminent] rather than a negative countdown.
/// Pure formatting over an injected [clock] — never calls `DateTime.now`
/// directly, so tests pin a [Clock] and stay hermetic (deterministic-tests
/// rule, AGENTS.md §6). The data layer stays free of user-facing strings; the
/// presentation layer supplies the wording through [copy] (ADR-034).
String relativeTimeUntil(
  DateTime when, {
  Clock clock = Clock.system,
  required RelativeTimeUntilCopy copy,
}) {
  final diff = when.difference(clock.now());
  if (diff <= const Duration(minutes: 1)) return copy.imminent;
  if (diff < const Duration(hours: 1)) return copy.minutes(diff.inMinutes);
  if (diff < const Duration(hours: 24)) return copy.hours(diff.inHours);
  return copy.days(diff.inDays);
}

/// Relative age of a cache write for the season-card stale indicator
/// (`redesign-seasons-home` task 2.3, design D2).
///
/// Pure formatting over an injected [clock] — never calls `DateTime.now`
/// directly, so tests pin a [Clock.fixed] and stay hermetic
/// (deterministic-tests rule, AGENTS.md §6). Coarse buckets only: the
/// indicator is a subtle freshness hint, not a clock.
///
/// [copy] supplies the localized units; pass the catalog's wording from the
/// presentation layer (see `seasonsScreen`'s `_staleLabel`).
String relativeTimeSince(
  DateTime when, {
  Clock clock = Clock.system,
  required RelativeTimeCopy copy,
}) {
  final diff = clock.now().difference(when);
  if (diff < const Duration(minutes: 1)) return copy.justNow;
  if (diff < const Duration(hours: 1)) return copy.minutes(diff.inMinutes);
  if (diff < const Duration(hours: 24)) return copy.hours(diff.inHours);
  return copy.days(diff.inDays);
}
