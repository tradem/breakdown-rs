// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit test: the look controller's pure state shaping (rows + version
// fence), the overlay clear condition and the problem-code → copy mapping.
// No Flutter imports beyond the generated catalogs (AGENTS.md test pyramid).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/outfit_repository.dart';
import 'package:frontend_flutter/features/outfits/outfits_controller.dart';
import 'package:frontend_flutter/features/outfits/outfits_state.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

OutfitView _outfit(
  String id, {
  int version = 1,
  String name = 'Look',
  String? variantOf,
  List<String> pieceIds = const [],
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
    ..pieceIds.replace(BuiltList<String>(pieceIds))
    ..pieces.replace(BuiltList<OutfitPieceView>(pieces))
    ..photos.replace(BuiltList<OutfitPhotoView>()),
);

void main() {
  group('outfits state rows + version fence', () {
    test('a projected row renders projected when no overlay exists', () {
      final state = OutfitsScreenState(
        projected: AsyncValue.data([_outfit('o-1')]),
        cachedRows: [_outfit('o-1')],
      );
      expect(state.rows.single, isA<ProjectedOutfitRow>());
    });

    test('an overlay holds the row while the fence is not passed', () {
      final projected = _outfit('o-1', version: 3);
      final state = OutfitsScreenState(
        projected: AsyncValue.data([projected]),
        cachedRows: [projected],
        overlays: [
          OutfitRowOverlay(
            id: 'o-1',
            overlay: _outfit('o-1', version: 4, name: 'OP'),
            acknowledgedVersion: 4,
            status: OverlayStatus.acknowledged,
          ),
        ],
      );
      final row = state.rows.single;
      expect(row, isA<OptimisticOutfitRow>());
      expect((row as OptimisticOutfitRow).overlay.overlay.name, 'OP');
      expect(state.rowById('o-1')?.name, 'OP');
    });

    test('the fence drops the overlay once the projection catches up', () {
      final projected = _outfit('o-1', version: 4, name: 'OP');
      final state = OutfitsScreenState(
        projected: AsyncValue.data([projected]),
        cachedRows: [projected],
        overlays: [
          OutfitRowOverlay(
            id: 'o-1',
            overlay: _outfit('o-1', version: 4, name: 'OP'),
            acknowledgedVersion: 4,
            status: OverlayStatus.reconciling,
          ),
        ],
      );
      expect(state.rows.single, isA<ProjectedOutfitRow>());
      expect(
        shouldClearOutfitOverlay(projection: projected, acknowledgedVersion: 4),
        isTrue,
      );
      expect(
        shouldClearOutfitOverlay(
          projection: _outfit('o-1', version: 3),
          acknowledgedVersion: 4,
        ),
        isFalse,
      );
    });

    test('a create-path overlay (absent from the projection) appends', () {
      final state = OutfitsScreenState(
        projected: AsyncValue.data([_outfit('o-1')]),
        cachedRows: [_outfit('o-1')],
        overlays: [
          OutfitRowOverlay(
            id: 'o-2',
            overlay: _outfit('o-2', name: 'Neu'),
            acknowledgedVersion: 1,
            status: OverlayStatus.acknowledged,
          ),
        ],
      );
      expect(state.rows.length, 2);
      expect(state.rows.last, isA<OptimisticOutfitRow>());
      expect(state.rowById('o-2')?.name, 'Neu');
      expect(state.rowById('missing'), isNull);
    });

    test('notFound is only the *.not-found error of a deleted parent', () {
      final missing = OutfitsScreenState(
        projected: AsyncValue.error(
          const ProblemError(code: 'character.not-found'),
          StackTrace.empty,
        ),
      );
      expect(missing.notFound?.code, 'character.not-found');
      final other = OutfitsScreenState(
        projected: AsyncValue.error(
          const ProblemError(code: 'transport.unknown'),
          StackTrace.empty,
        ),
      );
      expect(other.notFound, isNull);
    });
  });

  group('outfit overlay helpers', () {
    final base = _outfit('o-1', version: 2, pieceIds: ['p-1']);

    test('rename and notes overlays replace the field only', () {
      expect(applyOutfitRenameOptimistic(base, 'OP').name, 'OP');
      expect(applyOutfitRenameOptimistic(base, 'OP').version, 2);
      expect(applyOutfitNotesOptimistic(base, 'Notiz').notes, 'Notiz');
    });

    test('adding a held piece is a no-op (ids stay unique)', () {
      final piece = OutfitPieceView(
        (b) => b
          ..pieceId = 'p-1'
          ..position = 0
          ..name = 'Hemd'
          ..categoryName = 'Oberteil',
      );
      expect(applyOutfitAddPieceOptimistic(base, piece), same(base));
      final other = OutfitPieceView(
        (b) => b
          ..pieceId = 'p-2'
          ..position = 1
          ..name = 'Weste'
          ..categoryName = 'Jacke',
      );
      expect(
        applyOutfitAddPieceOptimistic(base, other).pieces.map((p) => p.pieceId),
        ['p-2'],
      );
    });

    test('removing a piece drops exactly that row', () {
      final withTwo = applyOutfitAddPieceOptimistic(
        base,
        OutfitPieceView(
          (b) => b
            ..pieceId = 'p-2'
            ..position = 1
            ..name = 'Weste',
        ),
      );
      expect(
        applyOutfitRemovePieceOptimistic(
          withTwo,
          'p-1',
        ).pieces.map((p) => p.pieceId),
        ['p-2'],
      );
    });

    test('remove keeps pieceIds in step so a re-add in the same window is '
        'not suppressed', () {
      final projected = _outfit(
        'o-1',
        version: 2,
        pieceIds: ['p-1'],
        pieces: [
          OutfitPieceView(
            (b) => b
              ..pieceId = 'p-1'
              ..position = 0
              ..name = 'Hemd',
          ),
        ],
      );
      final removed = applyOutfitRemovePieceOptimistic(projected, 'p-1');
      expect(removed.pieces, isEmpty);
      expect(removed.pieceIds, isEmpty);

      // The add guard reads `pieceIds` too: a stale id would make the re-add
      // a silent no-op until the projection caught up.
      final reAdded = applyOutfitAddPieceOptimistic(
        removed,
        OutfitPieceView(
          (b) => b
            ..pieceId = 'p-1'
            ..position = 0
            ..name = 'Hemd',
        ),
      );
      expect(reAdded.pieces.map((p) => p.pieceId), ['p-1']);
      expect(reAdded.pieceIds.length, removed.pieceIds.length);
      expect(reAdded.pieceIds.contains('p-1'), isFalse);
    });
  });

  group('outfitErrorCopy', () {
    final l10n = AppLocalizationsEn();

    test('maps the version conflict to the refresh narrative', () {
      expect(
        outfitErrorCopy(
          l10n,
          const ProblemError(code: 'concurrency.version-mismatch'),
        ),
        l10n.pieceErrorChanged,
      );
    });

    test('maps a denial to the outfit 403 narrative', () {
      for (final code in ['outfit.forbidden', 'domain.forbidden']) {
        expect(
          outfitErrorCopy(l10n, ProblemError(code: code)),
          l10n.outfitErrorForbidden,
        );
      }
    });

    test('maps a vanished look and a vanished garment distinctly', () {
      expect(
        outfitErrorCopy(l10n, const ProblemError(code: 'outfit.not-found')),
        l10n.outfitDetailGone,
      );
      expect(
        outfitErrorCopy(l10n, const ProblemError(code: 'piece.not-found')),
        l10n.pieceErrorDetailNotFound,
      );
    });

    test('transport failures use the network narrative, others fall back', () {
      expect(
        outfitErrorCopy(l10n, const ProblemError(code: 'transport.unknown')),
        l10n.costumeCategoryErrorNetwork,
      );
      expect(
        outfitErrorCopy(l10n, const ProblemError(code: 'outfit.validation')),
        l10n.outfitDetailGone,
      );
      expect(
        outfitErrorCopy(l10n, const ProblemError(code: 'weird.code')),
        l10n.outfitErrorGeneric('weird.code'),
      );
    });

    test('the photo surface routes to the photo copy', () {
      expect(
        outfitCommandErrorCopy(
          l10n,
          const OutfitCommandFailure(
            OutfitCommandSurface.photo,
            ProblemError(code: 'photo.not-found'),
          ),
        ),
        l10n.photoErrorGeneric('photo.not-found'),
      );
    });
  });
}
