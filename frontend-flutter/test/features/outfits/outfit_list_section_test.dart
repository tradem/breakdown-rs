// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-2 widget tests: the character detail's look section — rows, variant
// marker, empty state, create dialog validation and the client-side
// AUTHZ-GATE denial proof (request counter stays at zero).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/outfit_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/outfits/outfit_list_section.dart';
import 'package:frontend_flutter/features/outfits/outfit_detail_screen.dart';
import 'package:frontend_flutter/features/outfits/outfits_controller.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../seasons/seasons_test_fakes.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..projectId = 'proj-1'
    ..number = 1
    ..title = 'Staffel 1'
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CharacterView _character() => CharacterView(
  (b) => b
    ..id = 'char-1'
    ..seasonId = 'season-1'
    ..name = 'Anna'
    ..category = CharacterCategory.mainCast
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

OutfitPieceView _piece(String id, int position, {String? category}) =>
    OutfitPieceView(
      (b) => b
        ..pieceId = id
        ..position = position
        ..name = 'Kleidungsstück $id'
        ..categoryName = category,
    );

OutfitView _outfit(
  String id, {
  String name = 'Look',
  int version = 1,
  String? variantOf,
  List<OutfitPieceView> pieces = const [],
}) => OutfitView(
  (b) => b
    ..id = id
    ..characterId = 'char-1'
    ..name = name
    ..notes = ''
    ..variantOf = variantOf
    ..seasonId = 'season-1'
    ..version = version
    ..updatedAt = DateTime.utc(2026, 10, 27)
    ..pieceIds.replace(BuiltList<String>(pieces.map((p) => p.pieceId)))
    ..pieces.replace(BuiltList<OutfitPieceView>(pieces))
    ..photos.replace(BuiltList<OutfitPhotoView>()),
);

SeasonMembershipDto _membership({required bool costumeRole}) =>
    SeasonMembershipDto(
      (b) => b
        ..seasonId = 'season-1'
        ..hasActiveCostumeRoleInSeason = costumeRole
        ..capabilities.replace(
          costumeRole
              ? BuiltList<String>(['assign_costumes'])
              : BuiltList<String>(),
        ),
    );

/// Fake repository: records the dispatched commands, never touches the
/// network.
class _FakeOutfitRepository extends OutfitRepository {
  _FakeOutfitRepository(super.api, super.cache);

  final List<({String seasonId, String name})> createCalls = [];
  int reads = 0;

  @override
  Future<Result<List<OutfitView>>> listByCharacter(
    String characterId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    reads++;
    return Right<ProblemError, List<OutfitView>>(const <OutfitView>[]);
  }

  @override
  Future<Result<({List<OutfitView> rows, bool stale})>> readCachedFresh(
    String characterId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) async => const Right<ProblemError, ({List<OutfitView> rows, bool stale})>((
    rows: <OutfitView>[],
    stale: false,
  ));

  @override
  Future<Result<IdVersionResponse>> create({
    required String characterId,
    required String name,
    List<String> pieceIds = const [],
  }) async {
    createCalls.add((seasonId: characterId, name: name));
    return Right<ProblemError, IdVersionResponse>(
      IdVersionResponse(
        (b) => b
          ..id = 'outfit-new'
          ..version = 1,
      ),
    );
  }
}

/// Manual scheduler: the reconciliation backoff never sleeps in tests.
class _ManualScheduler extends ReconciliationScheduler {
  @override
  Future<void> tick(int attempt) async {}
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeOutfitRepository repo;
  late ProviderContainer container;

  void setup({List<OutfitView> rows = const [], bool costumeRole = true}) {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeOutfitRepository(BreakdownApi(), OutfitCacheDao(db));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        outfitRepositoryProvider.overrideWithValue(repo),
        // The detail route builds the fitting-photo surface; a bare
        // BreakdownApi keeps the pinned-TLS bootstrap out of the widget tier.
        outfitPhotoRepositoryProvider.overrideWithValue(
          PhotoRepository(BreakdownApi()),
        ),
        // The detail route arms the bounded variant watch; an empty stream
        // keeps the widget tier free of pending timers.
        outfitPhotoWatchProvider('char-1', 'outfit-new').overrideWith(
          (ref) => const Stream<PhotoWatchEvent<OutfitView>>.empty(),
        ),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => _ManualScheduler(),
        ),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right(_membership(costumeRole: costumeRole)),
        ),
        outfitsListFetchProvider('char-1').overrideWith(
          (ref) async => Right<ProblemError, List<OutfitView>>(rows),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                OutfitListSection(season: _season(), character: _character()),
              ],
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  setUp(() {});

  group('OutfitListSection', () {
    testWidgets('renders the character\'s looks with piece count + variant '
        'marker', (tester) async {
      setup(
        rows: [
          _outfit(
            'o-1',
            name: 'Alltagslook Tag 1',
            pieces: [_piece('p-1', 0), _piece('p-2', 1)],
          ),
          _outfit(
            'o-2',
            name: 'Alltagslook Tag 2',
            variantOf: 'o-1',
            pieces: [_piece('p-1', 0)],
          ),
        ],
      );
      await pumpSection(tester);

      expect(find.byKey(const Key('outfit-row-o-1')), findsOneWidget);
      expect(find.text('Alltagslook Tag 1'), findsOneWidget);
      expect(find.textContaining('2 Kleidungsstücke'), findsOneWidget);
      // The variant row carries the lineage marker.
      expect(find.textContaining('Variante'), findsOneWidget);
    });

    testWidgets('empty state offers creation, never a spinner', (tester) async {
      setup();
      await pumpSection(tester);

      expect(find.byKey(const Key('outfit-list-empty-char-1')), findsOneWidget);
      expect(find.byKey(const Key('outfit-create-char-1')), findsOneWidget);
    });

    testWidgets('a denial renders the narrative and disables creation, '
        'issuing no command', (tester) async {
      setup(costumeRole: false);
      await pumpSection(tester);

      expect(find.byKey(const Key('outfit-denied-narrative')), findsOneWidget);
      final create = tester.widget<TextButton>(
        find.byKey(const Key('outfit-create-char-1')),
      );
      expect(create.onPressed, isNull);
      // No look command left the client: the fake never saw a create.
      expect(repo.createCalls, isEmpty);
    });

    testWidgets('the create dialog keeps save disabled while the name is '
        'blank', (tester) async {
      setup();
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('outfit-create-char-1')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('outfit-name-field')), findsOneWidget);
      final saveBefore = tester.widget<FilledButton>(
        find.byKey(const Key('outfit-name-save')),
      );
      expect(saveBefore.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('outfit-name-field')), '  ');
      await _pumpFrames(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('outfit-name-save')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('outfit-name-field')),
        'Alltagslook',
      );
      await _pumpFrames(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('outfit-name-save')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('goldens render the look list for both themes and platforms', (
      tester,
    ) async {
      setup(
        rows: [
          _outfit(
            'o-1',
            name: 'Alltagslook Tag 1',
            pieces: [_piece('p-1', 0), _piece('p-2', 1)],
          ),
          _outfit(
            'o-2',
            name: 'Alltagslook Tag 2',
            variantOf: 'o-1',
            pieces: [_piece('p-1', 0)],
          ),
        ],
      );
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
          final modeName = mode == ThemeMode.light ? 'light' : 'dark';
          final platformName = platform == TargetPlatform.android
              ? 'android'
              : 'macos';
          try {
            debugDefaultTargetPlatformOverride = platform;
            tester.view.physicalSize = const Size(800, 1200);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  locale: const Locale('de'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: ThemeData.light(),
                  darkTheme: ThemeData.dark(),
                  themeMode: mode,
                  home: Scaffold(
                    body: ListView(
                      children: [
                        OutfitListSection(
                          season: _season(),
                          character: _character(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await expectLater(
              find.byType(OutfitListSection),
              matchesGoldenFile(
                'goldens/outfit_list_${modeName}_$platformName.png',
              ),
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        }
      }
    });

    testWidgets('creating dispatches the command with the character id', (
      tester,
    ) async {
      setup();
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('outfit-create-char-1')));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('outfit-name-field')),
        'Alltagslook',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('outfit-name-save')));
      await _pumpFrames(tester, n: 12);

      expect(repo.createCalls.single.name, 'Alltagslook');
      expect(repo.createCalls.single.seasonId, 'char-1');
    });
  });
}
