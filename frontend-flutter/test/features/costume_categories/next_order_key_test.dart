// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/costume_categories/next_order_key.dart';

void main() {
  group('nextOrderKey (D4 append rule over `!`..`~`)', () {
    test('empty list derives `!`', () {
      expect(nextOrderKey(const []), '!');
    });

    test('normal successor appends after the greatest key', () {
      expect(nextOrderKey(['!']), '"');
      expect(nextOrderKey(['!', '"', '#']), r'$');
      expect(nextOrderKey(['a', 'b']), 'c');
    });

    test('overflow of the last position grows the length (`~` → `~!`)', () {
      expect(nextOrderKey(['~']), '~!');
      expect(nextOrderKey(['a~']), 'a~!');
    });

    test('derives from the greatest key, not the last element', () {
      expect(nextOrderKey(['c', 'a', 'b']), 'd');
    });

    test(
      'every derived key compares strictly greater than its predecessor',
      () {
        const cases = <List<String>>[
          [],
          ['!'],
          ['!', '"'],
          ['a', 'b'],
          ['~'],
          ['a~'],
          ['z', '~'],
          ['~~'],
        ];
        for (final keys in cases) {
          final derived = nextOrderKey(keys);
          for (final key in keys) {
            expect(
              derived.compareTo(key),
              greaterThan(0),
              reason: 'derived $derived must sort after $key',
            );
          }
        }
      },
    );

    test('multi-char keys increment only the final byte', () {
      expect(nextOrderKey(['ab']), 'ac');
      expect(nextOrderKey(['a!']), 'a"');
    });
  });
}
