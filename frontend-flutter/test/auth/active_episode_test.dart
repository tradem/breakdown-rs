// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/auth/active_episode_store.dart';

import '../support/fake_secure_storage.dart';

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

  group('ActiveEpisode (issue #624)', () {
    test('starts unset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeEpisodeProvider), isNull);
    });

    test('set holds the scope and persists it per season', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 's-1',
            blockId: 'b-1',
            episodeId: 'e-1',
            episodeNumber: 3,
            episodeName: 'Pilot',
          );

      expect(
        container.read(activeEpisodeProvider),
        const ActiveEpisodeScope(
          seasonId: 's-1',
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 3,
          episodeName: 'Pilot',
        ),
      );

      await settlePersistence();
      final persisted = await container.read(
        activeEpisodePersistedProvider.future,
      );
      expect(persisted['s-1']?.episodeId, 'e-1');
      expect(persisted['s-1']?.episodeName, 'Pilot');
    });

    test('clear drops the scope and the persisted document', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 's-1',
            blockId: 'b-1',
            episodeId: 'e-1',
            episodeNumber: 1,
          );
      await settlePersistence();

      container.read(activeEpisodeProvider.notifier).clear();
      expect(container.read(activeEpisodeProvider), isNull);
      await settlePersistence();
      final persisted = await container.read(
        activeEpisodePersistedProvider.future,
      );
      expect(persisted, isEmpty);
    });

    test('a store failure leaves the in-memory scope intact', () async {
      platform.failAll = true;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 's-1',
            blockId: 'b-1',
            episodeId: 'e-1',
            episodeNumber: 1,
          );
      await settlePersistence();

      // Best-effort persistence: the failure never breaks the scope.
      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
    });
  });
}
