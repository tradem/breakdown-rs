// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/data/settings/easter_eggs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// In-memory `SharedPreferencesAsyncPlatform` double that can be forced
/// to fail every operation (storage-failure → Err-value tests).
final class FakeAsyncPlatform extends InMemorySharedPreferencesAsync {
  FakeAsyncPlatform.empty() : super.empty();

  bool failAll = false;

  Never _fail() => throw Exception('storage unavailable');

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    if (failAll) _fail();
    return super.getBool(key, options);
  }

  @override
  Future<bool> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {
    if (failAll) _fail();
    return super.setBool(key, value, options);
  }
}

void main() {
  late FakeAsyncPlatform platform;

  setUp(() {
    platform = FakeAsyncPlatform.empty();
    SharedPreferencesAsyncPlatform.instance = platform;
  });

  group('EasterEggsStore (issue #516)', () {
    test('uses the spec key', () {
      expect(EasterEggsStore.key, 'easter_eggs');
    });

    test('missing value reads null (first launch → default ON)', () async {
      final store = EasterEggsStore(SharedPreferencesAsync());
      expect((await store.read()).getRight().toNullable(), isNull);
    });

    test('round-trip: write, read, overwrite', () async {
      final store = EasterEggsStore(SharedPreferencesAsync());

      expect((await store.write(false)).isRight(), isTrue);
      expect((await store.read()).getRight().toNullable(), isFalse);

      expect((await store.write(true)).isRight(), isTrue);
      expect((await store.read()).getRight().toNullable(), isTrue);
    });

    test('storage failures are Err values with stable codes', () async {
      final store = EasterEggsStore(SharedPreferencesAsync());
      platform.failAll = true;

      // Err branches asserted explicitly (Err-branch rule).
      expect(
        (await store.read()).getLeft().toNullable()?.code,
        'settings.easter_eggs_read_failed',
      );
      expect(
        (await store.write(false)).getLeft().toNullable()?.code,
        'settings.easter_eggs_write_failed',
      );
    });
  });

  group('EasterEggs notifier (issue #516)', () {
    late FakeAsyncPlatform platform;

    setUp(() {
      platform = FakeAsyncPlatform.empty();
      SharedPreferencesAsyncPlatform.instance = platform;
    });

    test('default is enabled when nothing is persisted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(easterEggsProvider), isTrue);
      expect(container.read(easterEggsProvider.notifier).readFailed, isFalse);
    });

    test('bootstrap seeds a persisted false via HydratedEasterEggs', () async {
      await SharedPreferencesAsync().setBool(EasterEggsStore.key, false);

      final container = ProviderContainer(
        overrides: [
          easterEggsProvider.overrideWith(
            () => HydratedEasterEggs(initial: false, failed: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(easterEggsProvider), isFalse);
      expect(container.read(easterEggsProvider.notifier).readFailed, isFalse);
    });

    test('toggle flips immediately and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(easterEggsProvider.notifier);

      final flips = <bool>[];
      container.listen(easterEggsProvider, (_, v) => flips.add(v));

      await notifier.toggle(EasterEggsStore(SharedPreferencesAsync()));
      expect(container.read(easterEggsProvider), isFalse);
      expect(flips, [false]);
      expect(
        await SharedPreferencesAsync().getBool(EasterEggsStore.key),
        isFalse,
      );
    });

    test(
      'read-failure seeding falls back to default ON + visible error flag',
      () {
        final container = ProviderContainer(
          overrides: [
            easterEggsProvider.overrideWith(
              () => HydratedEasterEggs(initial: true, failed: true),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(easterEggsProvider.notifier);
        expect(notifier.readFailed, isTrue);
        expect(container.read(easterEggsProvider), isTrue); // default ON
      },
    );

    test(
      'toggle returns the write failure as Err (no silent discard)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(easterEggsProvider.notifier);

        platform.failAll = true;
        // The in-memory flip happened; the persistence failure surfaces.
        final result = await notifier.toggle(
          EasterEggsStore(SharedPreferencesAsync()),
        );
        expect(
          result.getLeft().toNullable()?.code,
          'settings.easter_eggs_write_failed',
        );
        expect(container.read(easterEggsProvider), isFalse);
      },
    );
  });
}
