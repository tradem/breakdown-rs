// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/shell/active_scope_chip.dart';
import 'package:frontend_flutter/features/shell/planning_location.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../../support/fake_secure_storage.dart';

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = id
    ..number = number
    ..projectId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block(String id, {int number = 3, String seasonId = 'season-1'}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

/// Flushes the fire-and-forget persistence/backfill chains: frame pumps
/// advance fake-async time and drain microtasks (no wall clock —
/// deterministic-tests rule; Future.delayed does not settle inside
/// testWidgets).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  late CacheDatabase db;
  late FakeSecureStoragePlatform platform;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  /// Pumps the chip with a [blockRepositoryProvider] backed by the real
  /// Drift cache (seed via [seedCache]) and the fake secure-storage store.
  Future<void> pumpChip(
    WidgetTester tester, {
    required ProviderContainer container,
    PlanningLocation? location,
    void Function(String seasonId)? onOpenPicker,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ActiveScopeChip(
              location: location,
              // Leaf widget — the picker seam is injected.
              onOpenPicker: onOpenPicker ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('ActiveScopeChip arms', () {
    testWidgets('no scope → hidden', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpChip(tester, container: container);
      expect(find.byKey(const Key('active-scope-chip')), findsNothing);
    });

    testWidgets('scoped with number → visible with the block label', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-1', blockNumber: 3);
      await settle(tester);
      await pumpChip(tester, container: container);
      expect(find.byKey(const Key('active-scope-chip')), findsOneWidget);
      expect(find.text('Filter: Block 3'), findsOneWidget);
    });

    testWidgets(
      'foreign season → the chip says so instead of the foreign label',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(activeBlockProvider.notifier)
            .set(seasonId: 'season-1', blockId: 'b-1', blockNumber: 3);
        await settle(tester);
        // Navigating season 2: the scope's season differs.
        await pumpChip(
          tester,
          container: container,
          location: PlanningLocation.season(_season('season-2', number: 2)),
        );
        expect(find.byKey(const Key('active-scope-chip')), findsOneWidget);
        expect(
          find.text('Filter gilt hier nicht – andere Season'),
          findsOneWidget,
        );
        expect(find.text('Filter: Block 3'), findsNothing);
      },
    );

    testWidgets('label-less scope degrades to "unknown", then the cache-only '
        'backfill writes the number back', (tester) async {
      // Seed the Drift cache with the picked block (label source).
      final dao = BlockCacheDao(db);
      await dao.applySnapshotForSeason('season-1', [
        _block('b-1', number: 5),
      ], DateTime.utc(2026, 1, 1));
      final container = ProviderContainer(
        overrides: [
          blockRepositoryProvider.overrideWithValue(
            BlockRepository(BreakdownApi(), dao),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Old persisted shape restored label-less.
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-1');
      await settle(tester);
      await pumpChip(tester, container: container);
      await tester.pump();
      await settle(tester);
      await tester.pump();
      // Backfilled: the real label (written back into the scope).
      expect(container.read(activeBlockProvider)?.blockNumber, 5);
      expect(find.text('Filter: Block 5'), findsOneWidget);
    });

    testWidgets('a second, DIFFERENT label-less scope backfills too '
        '(guard resets per scope pair)', (tester) async {
      // Regression for the CodeRabbit finding on #565: the backfill guard
      // must compare against the current (season, block) pair, not only
      // "was attempted once ever" — otherwise a later label-less scope B
      // would show "unknown" forever.
      final dao = BlockCacheDao(db);
      await dao.applySnapshotForSeason('season-1', [
        _block('b-1', number: 5),
        _block('b-2', number: 7),
      ], DateTime.utc(2026, 1, 1));
      final container = ProviderContainer(
        overrides: [
          blockRepositoryProvider.overrideWithValue(
            BlockRepository(BreakdownApi(), dao),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpChip(tester, container: container);

      // Scope A (label-less) → backfilled from the cache.
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-1');
      await settle(tester);
      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(container.read(activeBlockProvider)?.blockNumber, 5);
      expect(find.text('Filter: Block 5'), findsOneWidget);

      // Scope B (also label-less, different pair) → its OWN attempt.
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-2');
      await settle(tester);
      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(container.read(activeBlockProvider)?.blockNumber, 7);
      expect(find.text('Filter: Block 7'), findsOneWidget);
    });

    testWidgets('label-less scope with an empty cache stays "unknown"', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          blockRepositoryProvider.overrideWithValue(
            BlockRepository(BreakdownApi(), BlockCacheDao(db)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-1');
      await settle(tester);
      await pumpChip(tester, container: container);
      await tester.pump();
      await settle(tester);
      await tester.pump();
      // Degradation is explicit — never a silent unfiltered look.
      expect(find.text('Filter: Block unbekannt'), findsOneWidget);
    });

    testWidgets('tap opens the block picker for the scope season', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-1', blockNumber: 3);
      await settle(tester);
      final opened = <String>[];
      await pumpChip(tester, container: container, onOpenPicker: opened.add);
      await tester.tap(find.byKey(const Key('active-scope-chip')));
      expect(opened, ['season-1']);
    });
  });

  group('ScopeChipPickerScreen (chip tap → picker → changeable scope)', () {
    testWidgets('resolves candidates via the blocks fetch seam; the pick '
        'sets the sticky scope and pops back', (tester) async {
      final container = ProviderContainer(
        overrides: [
          blocksListFetchProvider('season-1').overrideWith(
            (ref) async => Right<ProblemError, List<BlockView>>([
              _block('b-1', number: 1),
              _block('b-2', number: 2),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ScopeChipPickerScreen(seasonId: 'season-1'),
                      ),
                    ),
                    key: const Key('open-picker'),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('open-picker')));
      await settle(tester);
      expect(find.byKey(const Key('block-scope-picker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('block-scope-pick-b-2')));
      await tester.pump();
      expect(
        container.read(activeBlockProvider),
        const ActiveScope(seasonId: 'season-1', blockId: 'b-2', blockNumber: 2),
      );
      // Popped back — after the pop animation no scope picker remains.
      for (var i = 0; i < 12; i++) {
        await tester.pump();
      }
      expect(find.byKey(const Key('block-scope-picker')), findsNothing);
    });
  });
}
