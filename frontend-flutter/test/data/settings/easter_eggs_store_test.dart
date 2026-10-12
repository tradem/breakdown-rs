// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/data/settings/easter_eggs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// In-memory `SharedPreferencesAsyncPlatform` double that can be forced
/// to fail every operation (storage-failure → Err-value tests), or only
/// `remove` (legacy-cleanup-failure test).
final class FakeAsyncPlatform extends InMemorySharedPreferencesAsync {
  FakeAsyncPlatform.empty() : super.empty();

  bool failAll = false;
  bool failRemove = false;

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

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    if (failAll || failRemove) _fail();
    return super.clear(parameters, options);
  }
}

void main() {
  late FakeAsyncPlatform platform;

  setUp(() {
    platform = FakeAsyncPlatform.empty();
    SharedPreferencesAsyncPlatform.instance = platform;
  });

  group('EasterEggId (issue #615)', () {
    test('uses flat per-egg spec keys + the legacy key', () {
      expect(EasterEggId.karlKlammer.prefsKey, 'easter_eggs.karl_klammer');
      expect(EasterEggId.dejaVuCat.prefsKey, 'easter_eggs.dejavu_cat');
      expect(EasterEggsStore.legacyKey, 'easter_eggs');
    });
  });

  group('EasterEggsStore (issue #615)', () {
    test(
      'missing per-egg value reads null (first launch → default ON)',
      () async {
        final store = EasterEggsStore(SharedPreferencesAsync());
        expect(
          (await store.read(EasterEggId.karlKlammer)).getRight().toNullable(),
          isNull,
        );
        expect(
          (await store.read(EasterEggId.dejaVuCat)).getRight().toNullable(),
          isNull,
        );
      },
    );

    test('round-trip per egg: one egg never affects the other', () async {
      final store = EasterEggsStore(SharedPreferencesAsync());

      expect(
        (await store.write(EasterEggId.karlKlammer, false)).isRight(),
        isTrue,
      );
      expect(
        (await store.read(EasterEggId.karlKlammer)).getRight().toNullable(),
        isFalse,
      );
      // The other egg stays unset.
      expect(
        (await store.read(EasterEggId.dejaVuCat)).getRight().toNullable(),
        isNull,
      );

      expect(
        (await store.write(EasterEggId.dejaVuCat, true)).isRight(),
        isTrue,
      );
      expect(
        (await store.read(EasterEggId.dejaVuCat)).getRight().toNullable(),
        isTrue,
      );
    });

    test('storage failures are Err values with stable codes', () async {
      final store = EasterEggsStore(SharedPreferencesAsync());
      platform.failAll = true;

      // Err branches asserted explicitly (Err-branch rule).
      expect(
        (await store.read(EasterEggId.karlKlammer))
            .getLeft()
            .toNullable()
            ?.code,
        'settings.easter_eggs_read_failed',
      );
      expect(
        (await store.write(
          EasterEggId.karlKlammer,
          false,
        )).getLeft().toNullable()?.code,
        'settings.easter_eggs_write_failed',
      );
      expect(
        (await store.readAll()).getLeft().toNullable()?.code,
        'settings.easter_eggs_read_failed',
      );
    });

    test(
      'readAll: unset eggs read null, effective defaults ON, no migration',
      () async {
        final snapshot = (await EasterEggsStore(
          SharedPreferencesAsync(),
        ).readAll()).getRight().toNullable()!;

        expect(snapshot.migratedLegacy, isFalse);
        for (final id in EasterEggId.values) {
          expect(snapshot.values[id], isNull);
          expect(snapshot.effective(id), isTrue);
        }
      },
    );

    test(
      'readAll migrates the legacy flag into both eggs and drops it',
      () async {
        await SharedPreferencesAsync().setBool(
          EasterEggsStore.legacyKey,
          false,
        );

        final snapshot = (await EasterEggsStore(
          SharedPreferencesAsync(),
        ).readAll()).getRight().toNullable()!;

        expect(snapshot.migratedLegacy, isTrue);
        expect(snapshot.values[EasterEggId.karlKlammer], isFalse);
        expect(snapshot.values[EasterEggId.dejaVuCat], isFalse);
        // The legacy key is removed.
        expect(
          await SharedPreferencesAsync().getBool(EasterEggsStore.legacyKey),
          isNull,
        );
      },
    );

    test('readAll migration preserves an explicit per-egg choice', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setBool(EasterEggsStore.legacyKey, true);
      await prefs.setBool(EasterEggId.karlKlammer.prefsKey, false);

      final snapshot = (await EasterEggsStore(
        prefs,
      ).readAll()).getRight().toNullable()!;

      // Explicit value kept; the unset egg seeded from the legacy value.
      expect(snapshot.values[EasterEggId.karlKlammer], isFalse);
      expect(snapshot.values[EasterEggId.dejaVuCat], isTrue);
      expect(await prefs.getBool(EasterEggsStore.legacyKey), isNull);
    });

    test(
      'a failed legacy cleanup is non-fatal (values still migrated)',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setBool(EasterEggsStore.legacyKey, false);
        platform.failRemove = true;

        final snapshot = (await EasterEggsStore(
          prefs,
        ).readAll()).getRight().toNullable()!;

        expect(snapshot.migratedLegacy, isTrue);
        expect(snapshot.values[EasterEggId.karlKlammer], isFalse);
        // The leftover legacy key is harmless and ignored on the next boot.
        expect(await prefs.getBool(EasterEggsStore.legacyKey), isFalse);
      },
    );
  });

  group('EasterEggs notifier family (issue #615)', () {
    test('default is enabled per egg when nothing is persisted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      for (final id in EasterEggId.values) {
        expect(container.read(easterEggProvider(id)), isTrue);
        expect(
          container.read(easterEggProvider(id).notifier).readFailed,
          isFalse,
        );
      }
    });

    test('bootstrap seeds a persisted false per egg', () {
      final container = ProviderContainer(
        overrides: [
          easterEggProvider(EasterEggId.karlKlammer).overrideWith(
            () => HydratedEasterEggs(
              EasterEggId.karlKlammer,
              initial: false,
              failed: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(easterEggProvider(EasterEggId.karlKlammer)),
        isFalse,
      );
      expect(container.read(easterEggProvider(EasterEggId.dejaVuCat)), isTrue);
    });

    test('toggle flips only its own egg and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final flips = <bool>[];
      container.listen(
        easterEggProvider(EasterEggId.karlKlammer),
        (_, v) => flips.add(v),
      );

      await container
          .read(easterEggProvider(EasterEggId.karlKlammer).notifier)
          .toggle(EasterEggsStore(SharedPreferencesAsync()));

      expect(
        container.read(easterEggProvider(EasterEggId.karlKlammer)),
        isFalse,
      );
      expect(container.read(easterEggProvider(EasterEggId.dejaVuCat)), isTrue);
      expect(flips, [false]);
      expect(
        await SharedPreferencesAsync().getBool(
          EasterEggId.karlKlammer.prefsKey,
        ),
        isFalse,
      );
    });

    test(
      'read-failure seeding falls back to default ON + visible error flag',
      () {
        final container = ProviderContainer(
          overrides: [
            for (final id in EasterEggId.values)
              easterEggProvider(id).overrideWith(
                () => HydratedEasterEggs(id, initial: true, failed: true),
              ),
          ],
        );
        addTearDown(container.dispose);

        for (final id in EasterEggId.values) {
          expect(
            container.read(easterEggProvider(id).notifier).readFailed,
            isTrue,
          );
          expect(container.read(easterEggProvider(id)), isTrue); // default ON
        }
      },
    );

    test(
      'toggle returns the write failure as Err (no silent discard)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          easterEggProvider(EasterEggId.karlKlammer).notifier,
        );

        platform.failAll = true;
        final result = await notifier.toggle(
          EasterEggsStore(SharedPreferencesAsync()),
        );
        expect(
          result.getLeft().toNullable()?.code,
          'settings.easter_eggs_write_failed',
        );
        // The in-memory flip still happened.
        expect(
          container.read(easterEggProvider(EasterEggId.karlKlammer)),
          isFalse,
        );
      },
    );
  });
}
