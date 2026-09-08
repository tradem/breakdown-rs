// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/features/blocks/active_block_gate.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';

BlockView _block(String id, {int number = 1, String seasonId = 'season-1'}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId
        ..seriesId = 'series-1'
        ..startDate = '2026-01-01'
        ..endDate = '2026-01-31'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

const _offline = ProblemError(code: 'transport.connectionError');

/// Container with the blocks list fetch faked to [result].
///
/// Pins the auto-dispose resolution chain with a listener (same pattern as
/// `blocks_view_stale_test.dart`): without it the provider is disposed
/// between awaits and every re-read rebuilds from `AsyncLoading`.
ProviderContainer gateContainer(Result<List<BlockView>> result) {
  final container = ProviderContainer(
    overrides: [
      blocksListFetchProvider('season-1').overrideWith((ref) async => result),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(
    blockScopeResolutionProvider('season-1'),
    (_, _) {},
  );
  addTearDown(sub.close);
  return container;
}

/// Settles the faked fetch and flushes the resolution chain.
///
/// Turn budget (analytical, not wall-clock): fetch-complete → resolution
/// rebuild (single-block path schedules its deferred scope set) → set →
/// resolution rebuild to ready. Each arrow is an event-loop turn with
/// microtasks draining between turns; five turns bound the chain with
/// slack. No wall-clock assertion is made (deterministic-tests rule).
Future<void> settleFetch(ProviderContainer container) async {
  await container.read(blocksListFetchProvider('season-1').future);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('blockScopeResolution', () {
    test('reuses the matching sticky scope without fetching', () {
      final container = gateContainer(
        Right<ProblemError, List<BlockView>>([_block('b-1')]),
      );
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'block-9');
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      expect(resolution, isA<AsyncData<BlockScopeResolution>>());
      final value = (resolution as AsyncData<BlockScopeResolution>).value;
      expect(value.scope, isNotNull);
      expect(value.scope!.blockId, 'block-9');
      expect(value.candidates, isNull);
    });

    test('ignores a sticky scope from another season', () async {
      final container = gateContainer(
        Right<ProblemError, List<BlockView>>([_block('b-1')]),
      );
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-other', blockId: 'block-9');
      await settleFetch(container);
      // Single block of season-1 is auto-picked, replacing the foreign scope.
      expect(container.read(activeBlockProvider)?.blockId, 'b-1');
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      final value = (resolution as AsyncData<BlockScopeResolution>).value;
      expect(value.scope!.blockId, 'b-1');
    });

    test('auto-picks the only block and resolves ready', () async {
      final container = gateContainer(
        Right<ProblemError, List<BlockView>>([_block('b-1')]),
      );
      await settleFetch(container);
      expect(container.read(activeBlockProvider)?.blockId, 'b-1');
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      expect(resolution, isA<AsyncData<BlockScopeResolution>>());
      expect(
        (resolution as AsyncData<BlockScopeResolution>).value.scope!.blockId,
        'b-1',
      );
    });

    test('multi-block season yields the picker candidates', () async {
      final container = gateContainer(
        Right<ProblemError, List<BlockView>>([
          _block('b-1', number: 1),
          _block('b-2', number: 2),
        ]),
      );
      await settleFetch(container);
      // Nothing auto-set — the user picks once (remembered).
      expect(container.read(activeBlockProvider), isNull);
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      final value = (resolution as AsyncData<BlockScopeResolution>).value;
      expect(value.scope, isNull);
      expect(value.candidates!.map((b) => b.id), ['b-1', 'b-2']);
    });

    test('block-less season resolves empty (hint, no requests)', () async {
      final container = gateContainer(
        const Right<ProblemError, List<BlockView>>([]),
      );
      await settleFetch(container);
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      final value = (resolution as AsyncData<BlockScopeResolution>).value;
      expect(value.scope, isNull);
      expect(value.candidates, isNull);
      expect(value.isEmpty, isTrue);
    });

    test('fetch Err surfaces as AsyncError (retry surface)', () async {
      final container = gateContainer(const Left(_offline));
      // A fetch `Left` is a value (not a future error): the future
      // completes normally and the gate maps it to `AsyncError`.
      await container.read(blocksListFetchProvider('season-1').future);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final resolution = container.read(
        blockScopeResolutionProvider('season-1'),
      );
      expect(resolution, isA<AsyncError<BlockScopeResolution>>());
      final error = (resolution as AsyncError<BlockScopeResolution>).error;
      expect((error as ProblemError).code, 'transport.connectionError');
    });
  });

  group('BlockScopePickerScaffold', () {
    testWidgets('tap sets the sticky scope (remembered pick)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: BlockScopePickerScaffold(
              title: 'Costumes',
              seasonId: 'season-1',
              candidates: [_block('b-1', number: 1), _block('b-2', number: 2)],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('block-scope-pick-b-2')));
      await tester.pump();
      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 'season-1', blockId: 'b-2'),
      );
    });
  });
}
