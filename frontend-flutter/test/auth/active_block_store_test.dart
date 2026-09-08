// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (opencode-go)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/auth/active_block_store.dart';

/// In-memory [FlutterSecureStoragePlatform] double (same pattern as the
/// token-store and api-base-override tests): verifies the scopes really
/// round-trip through the secure-storage API, never a plaintext store.
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

  group('ActiveBlockStore (issue #382)', () {
    test('starts empty', () async {
      final store = ActiveBlockStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('round-trip: save per season, overwrite, remove, clear', () async {
      final store = ActiveBlockStore.secure();

      expect(
        (await store.saveScope(seasonId: 's-1', blockId: 'b-1')).isRight(),
        isTrue,
      );
      expect(
        (await store.saveScope(seasonId: 's-2', blockId: 'b-2')).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-1',
        's-2': 'b-2',
      });

      // Overwrite keeps the other season untouched.
      expect(
        (await store.saveScope(seasonId: 's-1', blockId: 'b-9')).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-9',
        's-2': 'b-2',
      });

      // Stale eviction removes one season only.
      expect((await store.removeScope('s-1')).isRight(), isTrue);
      expect((await store.readScopes()).getRight().toNullable(), {
        's-2': 'b-2',
      });

      // Removing an unknown season is a no-op success.
      expect((await store.removeScope('s-unknown')).isRight(), isTrue);

      // Sign-out wipe.
      expect((await store.clear()).isRight(), isTrue);
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('uses the scoped key, not a plaintext preference', () async {
      expect(ActiveBlockStore.key, 'breakdown.active_block_scopes');
      final store = ActiveBlockStore.secure();
      await store.saveScope(seasonId: 's-1', blockId: 'b-1');
      expect(platform.store.keys, ['breakdown.active_block_scopes']);
    });

    test('corrupt payload self-heals to empty', () async {
      platform.store[ActiveBlockStore.key] = 'not-json{{{';
      final store = ActiveBlockStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
      // Healed: the corrupt entry is gone, the next write starts clean.
      expect(platform.store.containsKey(ActiveBlockStore.key), isFalse);
      expect(
        (await store.saveScope(seasonId: 's-1', blockId: 'b-1')).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-1',
      });
    });

    test('non-map payload self-heals to empty', () async {
      platform.store[ActiveBlockStore.key] = '[1,2,3]';
      final store = ActiveBlockStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('storage failures are Err values with stable codes', () async {
      final store = ActiveBlockStore.secure();
      platform.failAll = true;

      expect(
        (await store.readScopes()).getLeft().toNullable()?.code,
        'active_block.scopes_read_failed',
      );
      expect(
        (await store.saveScope(
          seasonId: 's',
          blockId: 'b',
        )).getLeft().toNullable()?.code,
        anyOf(
          'active_block.scopes_read_failed',
          'active_block.scopes_write_failed',
        ),
      );
      expect(
        (await store.clear()).getLeft().toNullable()?.code,
        'active_block.scopes_clear_failed',
      );
    });
  });
}
