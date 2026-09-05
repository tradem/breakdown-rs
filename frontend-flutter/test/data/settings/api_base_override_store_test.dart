// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/data/settings/api_base_override_store.dart';

/// In-memory [FlutterSecureStoragePlatform] double (same pattern as the
/// token-store tests): verifies the override really round-trips through the
/// secure-storage API, never a plaintext store.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};
  bool failAll = false;

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
    if (failAll) throw PlatformException(code: 'delete_failed');
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    if (failAll) throw PlatformException(code: 'delete_failed');
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failAll) throw PlatformException(code: 'read_failed');
    return store[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    if (failAll) throw PlatformException(code: 'read_failed');
    return Map.of(store);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failAll) throw PlatformException(code: 'write_failed');
    store[key] = value;
  }
}

void main() {
  late FakeSecureStoragePlatform platform;

  setUp(() {
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  group('ApiBaseOverrideStore (task 6.2)', () {
    test('round-trip: write, read, overwrite, clear', () async {
      final store = ApiBaseOverrideStore.secure();

      expect((await store.read()).getRight().toNullable(), isNull);

      expect((await store.write('https://a.example')).isRight(), isTrue);
      expect((await store.read()).getRight().toNullable(), 'https://a.example');

      expect((await store.write('https://b.example')).isRight(), isTrue);
      expect((await store.read()).getRight().toNullable(), 'https://b.example');

      expect((await store.clear()).isRight(), isTrue);
      expect((await store.read()).getRight().toNullable(), isNull);
    });

    test('uses the spec key, not a plaintext preference', () async {
      expect(ApiBaseOverrideStore.key, 'api_base_override');
      final store = ApiBaseOverrideStore.secure();
      await store.write('https://a.example');
      expect(platform.store.keys, ['api_base_override']);
    });

    test('storage failures are Err values with stable codes', () async {
      final store = ApiBaseOverrideStore.secure();
      platform.failAll = true;

      expect(
        (await store.read()).getLeft().toNullable()?.code,
        'settings.override_read_failed',
      );
      expect(
        (await store.write('https://a.example')).getLeft().toNullable()?.code,
        'settings.override_write_failed',
      );
      expect(
        (await store.clear()).getLeft().toNullable()?.code,
        'settings.override_clear_failed',
      );
    });
  });
}
