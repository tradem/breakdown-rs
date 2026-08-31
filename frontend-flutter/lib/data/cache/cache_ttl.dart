// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'clock.dart';

/// Default cache TTL per table (Design Decision D2).
///
/// 24h is the baseline; fast-moving projections (e.g. `scene_shoots`) may pass
/// a shorter per-table [Duration] at the call site. The value is tunable; the
/// invariant — TTL is computed from the client-only `cachedAt`, never the
/// server `updatedAt` — is fixed.
const Duration kCacheTtl = Duration(hours: 24);

/// Returns `true` when a row written at [cachedAt] is older than [ttl] per the
/// injectable [clock].
///
/// [cachedAt] is the cache-write time set on upsert (D2); the server
/// `updatedAt` is preserved unchanged and never used for TTL. A failed refetch
/// leaves `cachedAt` untouched, so an unrefreshed row eventually expires and
/// is surfaced as stale rather than silently served forever.
bool isRowExpired(
  DateTime cachedAt,
  Duration ttl, {
  Clock clock = Clock.system,
}) => clock.now().difference(cachedAt) > ttl;
