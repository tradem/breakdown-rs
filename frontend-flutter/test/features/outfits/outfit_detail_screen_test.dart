// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests: the look detail — ordered garments, rename, notes,
// add/remove garment, variant fork, and the AUTHZ-GATE denial proof.

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
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/outfit_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/outfits/outfit_detail_screen.dart';
import 'package:frontend_flutter/features/outfits/outfits_controller.dart';
import 'package:frontend_flutter/features/outfits/outfits_state.dart';
import 'package:frontend_flutter/features/pieces/pieces_controller.dart';
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

OutfitPieceView _outfitPiece(
  String id,
  int position, {
  String? category = 'Oberteil',
}) => OutfitPieceView(
  (b) => b
    ..pieceId = id
    ..position = position
    ..name = 'Stück $id'
    ..categoryName = category,
);

OutfitView _outfit({
  String id = 'o-1',
  String name = 'Alltagslook',
  String notes = '',
  int version = 4,
  String? variantOf,
  List<OutfitPieceView> pieces = const [],
}) => OutfitView(
  (b) => b
    ..id = id
    ..characterId = 'char-1'
    ..name = name
    ..notes = notes
    ..variantOf = variantOf
    ..seasonId = 'season-1'
    ..version = version
    ..updatedAt = DateTime.utc(2026, 10, 27)
    ..pieceIds.replace(BuiltList<String>(pieces.map((p) => p.pieceId)))
    ..pieces.replace(BuiltList<OutfitPieceView>(pieces))
    ..photos.replace(BuiltList<OutfitPhotoView>()),
);

PieceView _piece(String id, {String name = 'Hemd', String? category}) =>
    PieceView(
      (b) => b
        ..id = id
        ..name = name
        ..notes = ''
        ..categoryId = category == null ? null : 'cat-1'
        ..categoryName = category
        ..updatedAt = DateTime.utc(2026, 10, 27)
        ..version = 1
        ..seasonIds.replace(BuiltList<String>(['season-1']))
        ..details.replace(BuiltList<PieceDetailView>())
        ..photos.replace(BuiltList<PiecePhotoView>()),
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

/// Records every dispatched look command; never touches the network.
class _RecordingOutfitRepository extends OutfitRepository {
  _RecordingOutfitRepository(super.api, super.cache);

  final List<({String id, String name, int version})> renames = [];
  final List<({String id, String notes, int version})> notes = [];
  final List<({String id, String pieceId, int version})> added = [];
  final List<({String id, String pieceId, int version})> removed = [];
  final List<String> variants = [];

  OutfitView? detail;

  @override
  Future<Result<List<OutfitView>>> listByCharacter(
    String characterId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => Right<ProblemError, List<OutfitView>>(const <OutfitView>[]);

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
  Future<Result<OutfitView>> get(String id) async => detail == null
      ? const Left(ProblemError(code: 'outfit.not-found'))
      : Right(detail!);

  @override
  Future<Result<int>> rename(String id, RenameOutfitRequest request) async {
    renames.add((id: id, name: request.name, version: request.version));
    return Right<ProblemError, int>(request.version + 1);
  }

  @override
  Future<Result<int>> updateNotes(
    String id,
    UpdateOutfitNotesRequest request,
  ) async {
    notes.add((id: id, notes: request.notes, version: request.version));
    return Right<ProblemError, int>(request.version + 1);
  }

  @override
  Future<Result<int>> addPiece(String id, AddOutfitPieceRequest request) async {
    added.add((id: id, pieceId: request.pieceId, version: request.version));
    return Right<ProblemError, int>(request.version + 1);
  }

  @override
  Future<Result<int>> removePiece(
    String id,
    String pieceId,
    int version,
  ) async {
    removed.add((id: id, pieceId: pieceId, version: version));
    return Right<ProblemError, int>(version + 1);
  }

  @override
  Future<Result<IdVersionResponse>> createVariant(
    String sourceOutfitId, {
    String? name,
    List<String>? pieceIds,
    String? notes,
  }) async {
    variants.add(sourceOutfitId);
    return Right<ProblemError, IdVersionResponse>(
      IdVersionResponse(
        (b) => b
          ..id = 'o-variant'
          ..version = 1,
      ),
    );
  }
}

class _NoopScheduler extends ReconciliationScheduler {
  @override
  Future<void> tick(int attempt) async {}
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _RecordingOutfitRepository repo;
  late ProviderContainer container;

  void setup({
    required OutfitView outfit,
    List<PieceView> seasonPieces = const [],
    bool costumeRole = true,
    // `true` = only the fetch seam is stubbed (the piece chain was never
    // watched — the Character → Looks → detail entry path).
    bool pieceFetchOnly = false,
  }) {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _RecordingOutfitRepository(BreakdownApi(), OutfitCacheDao(db));
    repo.detail = outfit;
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        outfitRepositoryProvider.overrideWithValue(repo),
        outfitPhotoRepositoryProvider.overrideWithValue(
          PhotoRepository(BreakdownApi()),
        ),
        reconciliationSchedulerProvider.overrideWith((ref) => _NoopScheduler()),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right(_membership(costumeRole: costumeRole)),
        ),
        outfitsListFetchProvider('char-1').overrideWith(
          (ref) async => Right<ProblemError, List<OutfitView>>([outfit]),
        ),
        outfitsViewProvider('char-1')
            .overrideWith((ref) => OutfitsView(rows: [outfit], isStale: false)),
        // The picked garments come from the season FETCH seam (the picker
        // awaits it); the projection override below only short-circuits the
        // controller chain for tests that do not exercise the lazy load.
        piecesListFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, List<PieceView>>(seasonPieces),
        ),
        if (!pieceFetchOnly)
          piecesViewProvider('season-1').overrideWith(
            (ref) => PiecesView(rows: seasonPieces, isStale: false),
          ),
        outfitPhotoWatchProvider('char-1', outfit.id).overrideWith(
          (ref) => const Stream<PhotoWatchEvent<OutfitView>>.empty(),
        ),
        outfitPhotoWatchProvider('char-1', 'o-variant').overrideWith(
          (ref) => const Stream<PhotoWatchEvent<OutfitView>>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    String outfitId = 'o-1',
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OutfitDetailScreen(
            season: _season(),
            characterId: 'char-1',
            outfitId: outfitId,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  group('OutfitDetailScreen', () {
    testWidgets('garments render in position order with layering allowed', (
      tester,
    ) async {
      setup(
        outfit: _outfit(
          pieces: [
            _outfitPiece('p-2', 1, category: 'Oberteil'),
            _outfitPiece('p-1', 0, category: 'Oberteil'),
            _outfitPiece('p-3', 2, category: 'Jacke'),
          ],
        ),
      );
      await pumpDetail(tester);

      final rows = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(ListTile),
            ),
          )
          .toList();
      final keys = rows
          .map((tile) => tile.key)
          .whereType<ValueKey<String>>()
          .map((k) => k.value)
          .where((v) => v.startsWith('outfit-piece-row-'))
          .toList();
      expect(keys, [
        'outfit-piece-row-p-1',
        'outfit-piece-row-p-2',
        'outfit-piece-row-p-3',
      ]);
    });

    testWidgets('rename dispatches the command with the version echo', (
      tester,
    ) async {
      setup(outfit: _outfit());
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('outfit-rename')));
      await _pumpFrames(tester);
      await tester.enterText(find.byKey(const Key('outfit-name-field')), 'OP');
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('outfit-name-save')));
      await _pumpFrames(tester, n: 20);

      expect(repo.renames.single.id, 'o-1');
      expect(repo.renames.single.name, 'OP');
      expect(repo.renames.single.version, 4);
    });

    testWidgets('notes save stays disabled until the text changes', (
      tester,
    ) async {
      setup(outfit: _outfit(notes: 'alt'));
      await pumpDetail(tester);

      final before = tester.widget<FilledButton>(
        find.byKey(const Key('outfit-notes-save')),
      );
      expect(before.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('outfit-notes-field')),
        'neu',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('outfit-notes-save')));
      await _pumpFrames(tester, n: 20);

      expect(repo.notes.single.notes, 'neu');
      expect(repo.notes.single.version, 4);
    });

    testWidgets('the add picker offers only garments the look does not hold', (
      tester,
    ) async {
      setup(
        outfit: _outfit(pieces: [_outfitPiece('p-1', 0)]),
        seasonPieces: [
          _piece('p-1', name: 'Hemd', category: 'Oberteil'),
          _piece('p-2', name: 'Weste', category: 'Jacke'),
        ],
      );
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('outfit-add-piece')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('outfit-pick-piece-p-1')), findsNothing);
      expect(find.byKey(const Key('outfit-pick-piece-p-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('outfit-pick-piece-p-2')));
      await _pumpFrames(tester, n: 20);

      expect(repo.added.single.pieceId, 'p-2');
      expect(repo.added.single.version, 4);
    });

    testWidgets('the add picker loads the garment projection when no piece '
        'surface was opened first', (tester) async {
      // Character → Looks → detail: the piece chain never ran, so the picker
      // must await the fetch seam instead of reading an empty projection.
      setup(
        outfit: _outfit(),
        seasonPieces: [
          _piece('p-7', name: 'Mantel', category: 'Jacke'),
          _piece('p-8', name: 'Hemd', category: 'Oberteil'),
        ],
        pieceFetchOnly: true,
      );
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('outfit-add-piece')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('outfit-pick-piece-empty')), findsNothing);
      expect(find.byKey(const Key('outfit-pick-piece-p-7')), findsOneWidget);
      expect(find.byKey(const Key('outfit-pick-piece-p-8')), findsOneWidget);

      await tester.tap(find.byKey(const Key('outfit-pick-piece-p-7')));
      await _pumpFrames(tester, n: 20);

      expect(repo.added.single.pieceId, 'p-7');
    });

    testWidgets('removing a garment confirms first, then echoes the version', (
      tester,
    ) async {
      setup(
        outfit: _outfit(
          pieces: [_outfitPiece('p-1', 0), _outfitPiece('p-2', 1)],
        ),
      );
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('outfit-piece-remove-p-1')));
      await _pumpFrames(tester);
      // Confirm-first: nothing is dispatched by the tap alone.
      expect(repo.removed, isEmpty);

      await tester.tap(
        find.byKey(const Key('outfit-remove-piece-confirm-p-1')),
      );
      await _pumpFrames(tester, n: 20);

      expect(repo.removed.single.pieceId, 'p-1');
      expect(repo.removed.single.version, 4);
    });

    testWidgets('a variant fork dispatches create-variant and opens the fork', (
      tester,
    ) async {
      setup(outfit: _outfit());
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('outfit-create-variant')));
      await _pumpFrames(tester, n: 20);

      expect(repo.variants.single, 'o-1');
    });

    testWidgets('the variant lineage names the source look', (tester) async {
      final source = _outfit(id: 'o-0', name: 'Alltagslook Tag 1');
      final variant = _outfit(
        id: 'o-1',
        name: 'Alltagslook Tag 2',
        variantOf: 'o-0',
      );
      setup(outfit: variant);
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          outfitRepositoryProvider.overrideWithValue(repo),
          outfitPhotoRepositoryProvider.overrideWithValue(
            PhotoRepository(BreakdownApi()),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => _NoopScheduler(),
          ),
          membershipFetchProvider(
            'season-1',
          ).overrideWith((ref) async => Right(_membership(costumeRole: true))),
          outfitsViewProvider('char-1').overrideWith(
            (ref) => OutfitsView(rows: [source, variant], isStale: false),
          ),
          outfitsListFetchProvider('char-1').overrideWith(
            (ref) async =>
                Right<ProblemError, List<OutfitView>>([source, variant]),
          ),
          outfitPhotoWatchProvider('char-1', 'o-1').overrideWith(
            (ref) => const Stream<PhotoWatchEvent<OutfitView>>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpDetail(tester);

      expect(find.byKey(const Key('outfit-variant-lineage')), findsOneWidget);
      expect(find.textContaining('Alltagslook Tag 1'), findsOneWidget);
    });

    testWidgets('goldens render the look detail for both themes and '
        'platforms', (tester) async {
      setup(
        outfit: _outfit(
          pieces: [
            _outfitPiece('p-1', 0, category: 'Oberteil'),
            _outfitPiece('p-2', 1, category: 'Jacke'),
          ],
          notes: 'Anprobe 12.10.',
        ),
      );
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
          final modeName = mode == ThemeMode.light ? 'light' : 'dark';
          final platformName = platform == TargetPlatform.android
              ? 'android'
              : 'macos';
          try {
            debugDefaultTargetPlatformOverride = platform;
            tester.view.physicalSize = const Size(800, 1600);
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
                  home: OutfitDetailScreen(
                    season: _season(),
                    characterId: 'char-1',
                    outfitId: 'o-1',
                  ),
                ),
              ),
            );
            await _pumpFrames(tester, n: 16);
            await expectLater(
              find.byType(OutfitDetailScreen),
              matchesGoldenFile(
                'goldens/outfit_detail_${modeName}_$platformName.png',
              ),
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        }
      }
    });

    testWidgets('a denial disables every write and dispatches nothing', (
      tester,
    ) async {
      setup(
        outfit: _outfit(pieces: [_outfitPiece('p-1', 0)]),
        costumeRole: false,
      );
      await pumpDetail(tester);

      expect(find.byKey(const Key('outfit-denied-narrative')), findsOneWidget);
      expect(find.byKey(const Key('outfit-rename')), findsNothing);
      expect(find.byKey(const Key('outfit-create-variant')), findsNothing);
      final addButton = tester.widget<TextButton>(
        find.byKey(const Key('outfit-add-piece')),
      );
      expect(addButton.onPressed, isNull);
      // A denied caller does not even get the remove affordance.
      expect(find.byKey(const Key('outfit-piece-remove-p-1')), findsNothing);
      expect(repo.renames, isEmpty);
      expect(repo.added, isEmpty);
      expect(repo.removed, isEmpty);
      expect(repo.variants, isEmpty);
    });
  });
}
