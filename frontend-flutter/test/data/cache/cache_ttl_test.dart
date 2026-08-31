// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';

void main() {
  // Task 3.1 — TTL invalidation per table.
  group('isRowExpired (TTL, D2)', () {
    final now = DateTime.utc(2026, 1, 2, 12, 0, 0);

    test('a freshly cached row is not expired', () {
      final cachedAt = now.subtract(const Duration(hours: 1));
      expect(
        isRowExpired(cachedAt, kCacheTtl, clock: Clock.fixed(now)),
        isFalse,
      );
    });

    test('a row older than the TTL is expired', () {
      final cachedAt = now.subtract(const Duration(hours: 25));
      expect(
        isRowExpired(cachedAt, kCacheTtl, clock: Clock.fixed(now)),
        isTrue,
      );
    });

    test('TTL is tunable per table (fast-moving projection uses a shorter one)',
        () {
      final cachedAt = now.subtract(const Duration(minutes: 31));
      // Expired against a 30-minute per-table TTL...
      expect(
        isRowExpired(cachedAt, const Duration(minutes: 30),
            clock: Clock.fixed(now)),
        isTrue,
      );
      // ...but still fresh against the default 24h TTL.
      expect(
        isRowExpired(cachedAt, kCacheTtl, clock: Clock.fixed(now)),
        isFalse,
      );
    });
  });
}
