// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_block.dart';

void main() {
  group('ActiveBlock', () {
    test('starts unset (requests go out headerless)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeBlockProvider), isNull);
    });

    test('set stores the season/block pair', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-1');
      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 'season-1', blockId: 'block-1'),
      );
    });

    test('clear returns to unset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeBlockProvider.notifier);
      notifier.set(seasonId: 'season-1', blockId: 'block-1');
      notifier.clear();
      expect(container.read(activeBlockProvider), isNull);
    });

    test('survives invalidation only as unset (sign-out reset)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-1');
      container.invalidate(activeBlockProvider);
      expect(container.read(activeBlockProvider), isNull);
    });

    test('ActiveScope equality is by value', () {
      expect(
        const ActiveScope(seasonId: 's', blockId: 'b'),
        const ActiveScope(seasonId: 's', blockId: 'b'),
      );
      expect(
        const ActiveScope(seasonId: 's', blockId: 'b'),
        isNot(const ActiveScope(seasonId: 's', blockId: 'other')),
      );
    });
  });
}
