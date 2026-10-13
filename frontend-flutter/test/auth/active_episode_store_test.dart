// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_episode_store.dart';

import '../support/fake_secure_storage.dart';

void main() {
  late FakeSecureStoragePlatform platform;

  setUp(() {
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  group('ActiveEpisodeStore (issue #624)', () {
    test('starts empty', () async {
      final store = ActiveEpisodeStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('round-trip: save per season, overwrite, remove, clear', () async {
      final store = ActiveEpisodeStore.secure();

      expect(
        (await store.saveScope(
          seasonId: 's-1',
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 1,
          episodeName: 'Pilot',
        )).isRight(),
        isTrue,
      );
      expect(
        (await store.saveScope(
          seasonId: 's-2',
          blockId: 'b-2',
          episodeId: 'e-2',
          episodeNumber: 2,
        )).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': const PersistedEpisodeScope(
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 1,
          episodeName: 'Pilot',
        ),
        's-2': const PersistedEpisodeScope(
          blockId: 'b-2',
          episodeId: 'e-2',
          episodeNumber: 2,
        ),
      });

      // Overwrite keeps the other season untouched.
      expect(
        (await store.saveScope(
          seasonId: 's-1',
          blockId: 'b-1',
          episodeId: 'e-9',
          episodeNumber: 9,
        )).isRight(),
        isTrue,
      );
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': const PersistedEpisodeScope(
          blockId: 'b-1',
          episodeId: 'e-9',
          episodeNumber: 9,
        ),
        's-2': const PersistedEpisodeScope(
          blockId: 'b-2',
          episodeId: 'e-2',
          episodeNumber: 2,
        ),
      });

      // Stale eviction removes one season only.
      expect((await store.removeScope('s-1')).isRight(), isTrue);
      expect((await store.readScopes()).getRight().toNullable(), {
        's-2': const PersistedEpisodeScope(
          blockId: 'b-2',
          episodeId: 'e-2',
          episodeNumber: 2,
        ),
      });

      // Removing an unknown season is a no-op success.
      expect((await store.removeScope('s-unknown')).isRight(), isTrue);

      // Sign-out wipe.
      expect((await store.clear()).isRight(), isTrue);
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('overlapping saves do not lose seasons (serialized)', () async {
      final store = ActiveEpisodeStore.secure();
      // Fire-and-forget like `ActiveEpisode.set`: without serialization both
      // reads would observe the same map and the last write would discard
      // the other season. No `await` between the invocations on purpose.
      final first = store.saveScope(
        seasonId: 's-1',
        blockId: 'b-1',
        episodeId: 'e-1',
        episodeNumber: 1,
      );
      final second = store.saveScope(
        seasonId: 's-2',
        blockId: 'b-2',
        episodeId: 'e-2',
        episodeNumber: 2,
      );
      await Future.wait([first, second]);
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': const PersistedEpisodeScope(
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 1,
        ),
        's-2': const PersistedEpisodeScope(
          blockId: 'b-2',
          episodeId: 'e-2',
          episodeNumber: 2,
        ),
      });
    });

    test('clear settles after in-flight saves (fenced sign-out)', () async {
      final store = ActiveEpisodeStore.secure();
      final save = store.saveScope(
        seasonId: 's-1',
        blockId: 'b-1',
        episodeId: 'e-1',
        episodeNumber: 1,
      );
      final cleared = store.clear();
      await Future.wait([save, cleared]);
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('uses the scoped key, not a plaintext preference', () async {
      expect(ActiveEpisodeStore.key, 'breakdown.active_episode_scopes');
      final store = ActiveEpisodeStore.secure();
      await store.saveScope(
        seasonId: 's-1',
        blockId: 'b-1',
        episodeId: 'e-1',
        episodeNumber: 1,
      );
      expect(platform.store.keys, ['breakdown.active_episode_scopes']);
    });

    test('corrupt payload self-heals to empty', () async {
      platform.store[ActiveEpisodeStore.key] = 'not-json{{{';
      final store = ActiveEpisodeStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
      expect(platform.store.containsKey(ActiveEpisodeStore.key), isFalse);
    });

    test('non-map payload self-heals to empty', () async {
      platform.store[ActiveEpisodeStore.key] = '[1,2,3]';
      final store = ActiveEpisodeStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), isEmpty);
    });

    test('invalid value shapes are dropped, valid ones load', () async {
      platform.store[ActiveEpisodeStore.key] =
          '{"s-1":{"blockId":"b-1","episodeId":"e-1","number":1,"name":"A"},'
          '"s-2":{"unknown":true}}';
      final store = ActiveEpisodeStore.secure();
      expect((await store.readScopes()).getRight().toNullable(), {
        's-1': const PersistedEpisodeScope(
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 1,
          episodeName: 'A',
        ),
      });
    });

    test('storage failures are Err values with stable codes', () async {
      final store = ActiveEpisodeStore.secure();
      platform.failAll = true;

      expect(
        (await store.readScopes()).getLeft().toNullable()?.code,
        'active_episode.scopes_read_failed',
      );
      expect(
        (await store.saveScope(
          seasonId: 's',
          blockId: 'b',
          episodeId: 'e',
          episodeNumber: 1,
        )).getLeft().toNullable()?.code,
        anyOf(
          'active_episode.scopes_read_failed',
          'active_episode.scopes_write_failed',
        ),
      );
      expect(
        (await store.clear()).getLeft().toNullable()?.code,
        'active_episode.scopes_clear_failed',
      );
    });
  });
}
