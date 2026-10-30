// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_block.dart';
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

  // Issue #765: an episode belongs to exactly one block, so the episode
  // scope can never be written without establishing its block scope (the
  // `X-Active-Block` request header the block-scoped routes require).
  group('ActiveEpisode cascades the block scope (issue #765)', () {
    void setEpisode(
      ProviderContainer container, {
      String seasonId = 's-1',
      String blockId = 'b-1',
      String episodeId = 'e-1',
      int episodeNumber = 3,
      int? blockNumber,
    }) => container
        .read(activeEpisodeProvider.notifier)
        .set(
          seasonId: seasonId,
          blockId: blockId,
          episodeId: episodeId,
          episodeNumber: episodeNumber,
          blockNumber: blockNumber,
        );

    test('set establishes the block scope from the acted-on episode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeBlockProvider), isNull);

      setEpisode(container);

      // The bare id, no invented number: the block chip's cache-only
      // backfill resolves the label (never a fabricated one).
      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 's-1', blockId: 'b-1'),
      );
    });

    test('set carries the acted-on block number through the cascade', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      setEpisode(container, blockNumber: 4);

      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 's-1', blockId: 'b-1', blockNumber: 4),
      );
    });

    test('set keeps a matching block scope\'s resolved number', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 's-1', blockId: 'b-1', blockNumber: 5);

      // A pick without a number must never downgrade a known label back to
      // the chip's "unknown" narrative.
      setEpisode(container);

      expect(container.read(activeBlockProvider)?.blockNumber, 5);
      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
    });

    test('set COMPLETES a label-less matching block scope with the known '
        'number (no backfill wait)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // A label-less scope (pre-#548 persisted document shape) that already
      // names the right block: nothing to cascade, but the acted-on
      // `BlockView` number is authoritative DTO data the chip would otherwise
      // have to backfill from the Drift cache.
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 's-1', blockId: 'b-1');

      setEpisode(container, blockNumber: 4);

      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 's-1', blockId: 'b-1', blockNumber: 4),
      );
      // The write goes through `ActiveBlock.set`'s reverse guard with the SAME
      // block, so the episode that caused it survives.
      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
    });

    test(
      'set does not rewrite a matching scope\'s number with another one',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(activeBlockProvider.notifier)
            .set(seasonId: 's-1', blockId: 'b-1', blockNumber: 5);

        // A block id's number is stable: the first known number wins, so a
        // stale caller can never flip the label to a different block's number.
        setEpisode(container, blockNumber: 9);

        expect(container.read(activeBlockProvider)?.blockNumber, 5);
        expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
      },
    );

    test('set reconciles a foreign block scope to the episode block and the '
        'episode survives that reconciliation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 's-1', blockId: 'b-9', blockNumber: 9);

      // The forward cascade moves the block scope; the reverse guard in
      // `ActiveBlock.set` must NOT eat the episode that caused the move
      // (ordering contract: the episode is in place before the cascade).
      setEpisode(container);

      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 's-1', blockId: 'b-1'),
      );
      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
    });

    test('clearForForeignBlock drops the memory and the persisted document of '
        'its own season', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      setEpisode(container);
      await settlePersistence();
      expect(
        (await container.read(
          activeEpisodePersistedProvider.future,
        ))['s-1']?.episodeId,
        'e-1',
      );

      container
          .read(activeEpisodeProvider.notifier)
          .clearForForeignBlock(seasonId: 's-1', blockId: 'b-2');

      expect(container.read(activeEpisodeProvider), isNull);
      await settlePersistence();
      // Evicted, so a cold start cannot resurrect the stale pair.
      expect(
        await container.read(activeEpisodePersistedProvider.future),
        isEmpty,
      );
    });

    test('clearForForeignBlock is a no-op for the episode\'s own block', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      setEpisode(container);

      container
          .read(activeEpisodeProvider.notifier)
          .clearForForeignBlock(seasonId: 's-1', blockId: 'b-1');

      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
    });

    test(
      'clearForForeignBlock keeps ANOTHER season\'s persisted document',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        setEpisode(container, seasonId: 's-1');
        setEpisode(
          container,
          seasonId: 's-2',
          blockId: 'b-2',
          episodeId: 'e-2',
        );
        await settlePersistence();

        container
            .read(activeEpisodeProvider.notifier)
            .clearForForeignBlock(seasonId: 's-2', blockId: 'b-9');

        expect(container.read(activeEpisodeProvider), isNull);
        await settlePersistence();
        // Per-season memory is the season-switch path's concern ([discard]).
        final persisted = await container.read(
          activeEpisodePersistedProvider.future,
        );
        expect(persisted['s-1']?.episodeId, 'e-1');
        expect(persisted.containsKey('s-2'), isFalse);
      },
    );
  });
}
