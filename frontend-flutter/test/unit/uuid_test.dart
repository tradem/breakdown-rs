// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-1 unit test (no Flutter imports): `generateUuidV7` must produce a
// wire-valid UUIDv7 every time — the contract types such ids as `uuid`
// (required), so a non-UUID string (the old `'pending'` placeholder)
// 422'd before the handler ran (issue #472).

import 'package:frontend_flutter/core/uuid.dart';
import 'package:test/test.dart';

/// RFC-9562 UUIDv7: version nibble 7, variant nibble 8-9-a-b.
final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('generateUuidV7 emits a unique, parseable UUIDv7', () {
    final ids = {for (var i = 0; i < 100; i++) generateUuidV7()};
    // 100 generations are all distinct (no collisions / constant placeholder).
    expect(ids, hasLength(100));
    for (final id in ids) {
      expect(_uuidV7.hasMatch(id), isTrue, reason: 'not a UUIDv7: $id');
    }
  });

  test('generateUuidV7 is never the rejected placeholder', () {
    expect(generateUuidV7(), isNot('pending'));
  });

  test('generateUuidV7 is time-ordered (monotonic ms prefix)', () {
    final a = generateUuidV7();
    final b = generateUuidV7();
    // 48-bit unix_ts_ms occupies the first 8 hex chars; v7 ids sort by time.
    expect(a.substring(0, 8).compareTo(b.substring(0, 8)) <= 0, isTrue);
  });
}
