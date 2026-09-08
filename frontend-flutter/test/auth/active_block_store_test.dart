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

    test('overlapping saves do not lose seasons (serialized)', () async {
      final store = ActiveBlockStore.secure();
      // Fire-and-forget like `ActiveBlock.set`: without serialization both
      // reads would observe the same map and the last write would discard
      // the other season. No `await` between the invocations on purpose.
      final first = store.saveScope(seasonId: 's-1', blockId: 'b-1');
      final second = store.saveScope(seasonId: 's-2', blockId: 'b-2');
      await Future.wait([first, second]);
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-1',
        's-2': 'b-2',
      });
    });

    test('stale eviction never deletes a fresh pick (conditional)', () async {
      final store = ActiveBlockStore.secure();
      expect(
        (await store.saveScope(seasonId: 's-1', blockId: 'b-fresh')).isRight(),
        isTrue,
      );
      // The eviction names the id the gate saw as stale; the stored id has
      // moved on, so this is a no-op — in either scheduling order.
      final evict = store.removeScopeIfMatch(
        seasonId: 's-1',
        blockId: 'b-stale',
      );
      final save = store.saveScope(seasonId: 's-1', blockId: 'b-fresh');
      await Future.wait([evict, save]);
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-fresh',
      });
    });

    test('stale eviction removes the matching entry', () async {
      final store = ActiveBlockStore.secure();
      expect(
        (await store.saveScope(seasonId: 's-1', blockId: 'b-stale')).isRight(),
        isTrue,
      );
      expect(
        (await store.removeScopeIfMatch(
          seasonId: 's-1',
          blockId: 'b-stale',
        )).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('clear settles after in-flight saves (fenced sign-out)', () async {
      final store = ActiveBlockStore.secure();
      // Scheduled before the clear, like a tap racing sign-out: the
      // awaited clear runs after it, so nothing resurrects afterwards.
      final save = store.saveScope(seasonId: 's-1', blockId: 'b-1');
      final cleared = store.clear();
      await Future.wait([save, cleared]);
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('save scheduled after clear wins (new session scope)', () async {
      final store = ActiveBlockStore.secure();
      expect((await store.clear()).isRight(), isTrue);
      await store.saveScope(seasonId: 's-1', blockId: 'b-1');
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': 'b-1',
      });
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
