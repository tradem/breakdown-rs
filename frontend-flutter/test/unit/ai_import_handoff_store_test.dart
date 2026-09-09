// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests for the AI-import hand-off store (task 1.3): round-trip,
// bounded/deduplicated job list, per-subject keying (the A → B switch
// exposes no state of A), clear (sign-out), and corrupt-payload self-heal.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/data/ai_import_handoff_store.dart';

/// In-memory [FlutterSecureStoragePlatform] double (same pattern as the
/// token-store and active-block-store tests).
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

  AiImportHandoffStore store() => AiImportHandoffStore.secure();

  group('AiImportHandoffStore (task 1.3)', () {
    test('starts empty', () async {
      final state = (await store().read('user-a')).getRight().toNullable()!;
      expect(state.configId, isNull);
      expect(state.jobIds, isEmpty);
    });

    test('round-trip: config id + jobs per subject', () async {
      final s = store();
      expect((await s.saveConfigId('user-a', 'config-1')).isRight(), isTrue);
      expect((await s.rememberJob('user-a', 'job-1')).isRight(), isTrue);
      expect((await s.rememberJob('user-a', 'job-2')).isRight(), isTrue);

      final state = (await s.read('user-a')).getRight().toNullable()!;
      expect(state.configId, 'config-1');
      // Newest first.
      expect(state.jobIds, ['job-2', 'job-1']);
    });

    test('rememberJob deduplicates and moves the id to the front', () async {
      final s = store();
      await s.rememberJob('user-a', 'job-1');
      await s.rememberJob('user-a', 'job-2');
      await s.rememberJob('user-a', 'job-1');

      final state = (await s.read('user-a')).getRight().toNullable()!;
      expect(state.jobIds, ['job-1', 'job-2']);
    });

    test(
      'rememberJob is bounded to kMaxRememberedJobIds, oldest dropped',
      () async {
        final s = store();
        for (var i = 0; i < kMaxRememberedJobIds + 5; i++) {
          await s.rememberJob('user-a', 'job-$i');
        }
        final state = (await s.read('user-a')).getRight().toNullable()!;
        expect(state.jobIds.length, kMaxRememberedJobIds);
        // Newest first: the highest index leads, the 5 oldest dropped.
        expect(state.jobIds.first, 'job-${kMaxRememberedJobIds + 4}');
        expect(state.jobIds.contains('job-0'), isFalse);
      },
    );

    test('forgetJob removes a single id; a missing id is a no-op', () async {
      final s = store();
      await s.rememberJob('user-a', 'job-1');
      await s.rememberJob('user-a', 'job-2');
      expect((await s.forgetJob('user-a', 'job-1')).isRight(), isTrue);
      expect((await s.forgetJob('user-a', 'nope')).isRight(), isTrue);
      final state = (await s.read('user-a')).getRight().toNullable()!;
      expect(state.jobIds, ['job-2']);
    });

    test('A → B switch: user B reads no state of user A', () async {
      final s = store();
      await s.saveConfigId('user-a', 'config-a');
      await s.rememberJob('user-a', 'job-a');

      final forB = (await s.read('user-b')).getRight().toNullable()!;
      expect(forB.configId, isNull, reason: 'config of A must not leak to B');
      expect(forB.jobIds, isEmpty, reason: 'jobs of A must not leak to B');

      // B stores its own state; A's is untouched and still readable.
      await s.saveConfigId('user-b', 'config-b');
      final forA = (await s.read('user-a')).getRight().toNullable()!;
      expect(forA.configId, 'config-a');
      final forBAgain = (await s.read('user-b')).getRight().toNullable()!;
      expect(forBAgain.configId, 'config-b');
    });

    test('clear wipes every subject (Phase 1a sign-out reset)', () async {
      final s = store();
      await s.saveConfigId('user-a', 'config-a');
      await s.saveConfigId('user-b', 'config-b');
      expect((await s.clear()).isRight(), isTrue);
      expect(
        (await s.read('user-a')).getRight().toNullable(),
        AiImportHandoffState.empty,
      );
      expect(
        (await s.read('user-b')).getRight().toNullable(),
        AiImportHandoffState.empty,
      );
    });

    test('a corrupt payload self-heals to the empty state', () async {
      platform.store[AiImportHandoffStore.key] = '{"users": "not-a-map"}';
      final state = (await store().read('user-a')).getRight().toNullable()!;
      expect(state, AiImportHandoffState.empty);
      // The heal wiped the corrupt document.
      expect(platform.store.containsKey(AiImportHandoffStore.key), isFalse);
    });

    test('a storage failure surfaces as Err, never throws', () async {
      platform.failAll = true;
      final res = await store().read('user-a');
      expect(res.getLeft().toNullable()!.code, 'ai_import.handoff_read_failed');
      expect(
        (await store().saveConfigId(
          'user-a',
          'c',
        )).getLeft().toNullable()!.code,
        'ai_import.handoff_write_failed',
      );
      expect(
        (await store().clear()).getLeft().toNullable()!.code,
        'ai_import.handoff_clear_failed',
      );
    });
  });
}
