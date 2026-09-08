// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/active_block_store.dart';

/// Reuses the [`FlutterSecureStoragePlatform`] fake shape from the store
/// tests so the write-through really round-trips (and failures stay
/// silent at the notifier level by design — persistence is best-effort).
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}

/// Flushes the notifier's fire-and-forget persistence (write + provider
/// invalidation): each arrow is an event-loop turn; a few turns bound the
/// chain with slack. No wall-clock assertion (deterministic-tests rule).
Future<void> settlePersistence() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSecureStoragePlatform platform;

  setUp(() {
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

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

    test('set persists the scope per season (write-through)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-1');
      await settlePersistence();
      final persisted = await container.read(
        activeBlockPersistedProvider.future,
      );
      expect(persisted, {'season-1': 'block-1'});
    });

    test('set keeps every season (per-season map)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeBlockProvider.notifier);
      notifier.set(seasonId: 'season-1', blockId: 'block-1');
      await settlePersistence();
      notifier.set(seasonId: 'season-2', blockId: 'block-2');
      await settlePersistence();
      final persisted = await container.read(
        activeBlockPersistedProvider.future,
      );
      expect(persisted, {'season-1': 'block-1', 'season-2': 'block-2'});
      // The sticky scope is still single (last set wins in memory).
      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 'season-2', blockId: 'block-2'),
      );
    });

    test('clear wipes the persisted scopes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeBlockProvider.notifier);
      notifier.set(seasonId: 'season-1', blockId: 'block-1');
      await settlePersistence();
      notifier.clear();
      await settlePersistence();
      final persisted = await container.read(
        activeBlockPersistedProvider.future,
      );
      expect(persisted, isEmpty);
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
