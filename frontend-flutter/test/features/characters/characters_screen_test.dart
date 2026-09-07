// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 widget + controller tests for `CharactersScreen` and
// `CharacterDetailScreen` (Task 5.3): list/create per spec scenarios (409
// conflict, unknown category strict-reject, optimistic rollback), prefilled
// full-replacement editors, and goldens {light,dark}×{android,macos}.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/characters/character_detail_screen.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/characters/characters_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(code: 'concurrency.conflict', status: 409);

CharacterView _character(
  String id, {
  String name = 'Ada',
  String categoryWire = 'main_cast',
  int version = 1,
}) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = name
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      categoryWire,
    )!
    ..measurements.replace(
      CharacterMeasurements(
        (m) => m
          ..height = '180'
          ..weight = '70'
          ..chest = '90'
          ..waist = '80'
          ..hips = '90'
          ..shoeSize = '42'
          ..hatSize = 'M',
      ),
    )
    ..contact.replace(
      ContactInfo(
        (c) => c
          ..email = 'ada@example.com'
          ..phone = '123',
      ),
    )
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-1'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeCharacterRepository extends CharacterRepository {
  _FakeCharacterRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  int createCalls = 0;
  int contactCalls = 0;
  int measurementsCalls = 0;

  @override
  Future<Result<IdVersionResponse>> create(CreateCharacterRequest request) {
    createCalls++;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right(
        IdVersionResponse(
          (b) => b
            ..id = 'ch-new-$createCalls'
            ..version = 1,
        ),
      ),
    );
  }

  @override
  Future<Result<int>> updateContact(
    String id,
    UpdateContactInfoRequest request,
  ) {
    contactCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> updateMeasurements(
    String id,
    UpdateMeasurementsRequest request,
  ) {
    measurementsCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeCharacterRepository repo;
  late ValueNotifier<Result<List<CharacterView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<CharacterView> initialRows = const [],
    Result<List<CharacterView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeCharacterRepository(BreakdownApi(), CharacterCacheDao(db));
    holder = ValueNotifier<Result<List<CharacterView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        characterRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        charactersListFetchProvider('season-1').overrideWith((ref) async {
          final dao = CharacterCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            await dao.applySnapshotForSeason(
              'season-1',
              rows,
              DateTime.utc(2026, 1, 1),
            );
            return Right(rows);
          });
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: CharactersScreen(season: _season())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CharactersScreen states (5.3, semantic finders)', () {
    testWidgets('data: rows render with category chips', (tester) async {
      await setupContainer(
        initialRows: [
          _character('ch-1'),
          _character('ch-2', name: 'Bea', categoryWire: 'extra'),
        ],
      );
      await pumpScreen(tester);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Main cast'), findsOneWidget);
      expect(find.text('Extra'), findsOneWidget);
    });

    testWidgets('empty: honest empty state with create affordance', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      expect(find.byKey(const Key('characters-empty')), findsOneWidget);
    });

    testWidgets('error: fetch failure renders keyed copy + retry', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);
      expect(find.byKey(const Key('characters-error')), findsOneWidget);
      expect(find.byKey(const Key('characters-retry')), findsOneWidget);
    });

    testWidgets('create: dispatches season_id + category, overlays', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('character-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-character-name')),
        'Cleo',
      );
      await tester.tap(find.byKey(const Key('create-character-submit')));
      await _pumpFrames(tester);
      expect(repo.createCalls, 1);
      expect(find.byKey(const Key('overlay-ch-new-1')), findsOneWidget);
    });

    testWidgets('unknown category strictly rejects (no guessed meaning)', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      final result = await container
          .read(charactersControllerProvider('season-1').notifier)
          .create(name: 'X', categoryWire: 'lead');
      expect(result.isLeft(), isTrue);
      expect(repo.createCalls, 0);
      result.match(
        (err) => expect(err.code, 'character.unknown_category'),
        (_) => fail('expected Left'),
      );
    });
  });

  group('CharacterDetailScreen editors (5.3)', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CharacterDetailScreen(season: _season(), characterId: 'ch-1'),
          ),
        ),
      );
      await _pumpFrames(tester, n: 20);
    }

    testWidgets('editors prefill from the read DTO', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpDetail(tester);
      expect(find.text('Ada'), findsWidgets);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.byKey(const Key('character-category-ch-1')), findsOneWidget);
    });

    testWidgets('contact save dispatches full replacement', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpDetail(tester);
      await tester.enterText(
        find.byKey(const Key('character-phone-ch-1')),
        '555',
      );
      await tester.tap(find.byKey(const Key('character-contact-save-ch-1')));
      await _pumpFrames(tester);
      expect(repo.contactCalls, 1);
    });

    testWidgets('409 conflict renders keyed copy, offers refresh', (
      tester,
    ) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpDetail(tester);
      repo.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('character-contact-save-ch-1')));
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });
  });

  group('CharactersScreen goldens (5.3, data state)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      TargetPlatform? platform,
    }) async {
      try {
        if (platform != null) {
          debugDefaultTargetPlatformOverride = platform;
        }
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: CharactersScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(CharactersScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpGolden(
        tester,
        golden: 'characters_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpGolden(
        tester,
        golden: 'characters_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpGolden(
        tester,
        golden: 'characters_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpGolden(
        tester,
        golden: 'characters_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });

  group('CharactersScreen extras (8.3)', () {
    testWidgets('create sheet category change dispatches guest', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('character-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-character-name')),
        'Gus',
      );
      await tester.tap(find.byKey(const Key('create-character-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-character-submit')));
      await _pumpFrames(tester);
      expect(repo.createCalls, 1);
    });

    testWidgets('command error dismisses', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpScreen(tester);
      container
          .read(charactersCommandErrorProvider('season-1').notifier)
          .set(const ProblemError(code: 'transport.x'));
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('character-command-error-banner')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('character-command-error-dismiss')),
      );
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('character-command-error-banner')),
        findsNothing,
      );
    });

    testWidgets('measurements save + 409 copy', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CharacterDetailScreen(season: _season(), characterId: 'ch-1'),
          ),
        ),
      );
      await _pumpFrames(tester, n: 20);
      await tester.enterText(
        find.byKey(const Key('character-measure-height-ch-1')),
        '181',
      );
      await tester.tap(
        find.byKey(const Key('character-measurements-save-ch-1')),
      );
      await _pumpFrames(tester);
      expect(repo.measurementsCalls, 1);
      repo.nextWrite = const Left(_conflict);
      await tester.tap(
        find.byKey(const Key('character-measurements-save-ch-1')),
      );
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('detail settled-missing renders not-found, not spinner', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CharacterDetailScreen(
              season: _season(),
              characterId: 'ch-gone',
            ),
          ),
        ),
      );
      await _pumpFrames(tester, n: 20);
      expect(find.byKey(const Key('character-detail-gone')), findsOneWidget);
      expect(find.byKey(const Key('character-loading')), findsNothing);
    });

    testWidgets('detail fetch error renders retry view', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CharacterDetailScreen(season: _season(), characterId: 'ch-1'),
          ),
        ),
      );
      await _pumpFrames(tester, n: 20);
      expect(find.byKey(const Key('character-detail-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('character-detail-retry')));
      await _pumpFrames(tester);
    });

    testWidgets('controller refresh clears and reconciles', (tester) async {
      await setupContainer(initialRows: [_character('ch-1')]);
      await pumpScreen(tester);
      final controller = container.read(
        charactersControllerProvider('season-1').notifier,
      );
      // Refresh reconciles the initial projection into the retained rows.
      await controller.refresh();
      await _pumpFrames(tester);
      expect(
        container
            .read(charactersControllerProvider('season-1'))
            .cachedRows
            .map((row) => row.id),
        ['ch-1'],
      );
      // A later projection (renamed upstream) reconciles the same way.
      // No scheduler tick is needed: with no overlays the pass is a
      // single refetch, not a bounded retry.
      holder.value = Right([_character('ch-1', name: 'Ada Updated')]);
      await controller.reconcile();
      await _pumpFrames(tester);
      expect(
        container
            .read(charactersControllerProvider('season-1'))
            .cachedRows
            .map((row) => row.name),
        ['Ada Updated'],
      );
      expect(
        container.read(charactersControllerProvider('season-1')).commandError,
        isNull,
      );
    });
  });
}
