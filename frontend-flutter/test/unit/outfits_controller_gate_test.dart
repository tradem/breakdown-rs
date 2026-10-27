// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit test: the look controller's client-side AUTHZ-GATE tri-state.
// A membership FETCH failure is pending ('membership.pending' — never a
// denial) and the failed provider state is dropped so the next command
// re-executes the fetch; a resolved `false` is 'domain.forbidden' (the code
// the server renders on every outfit route); an unresolvable scope stays
// pending instead of silently skipping the mirror. Every denial case proves
// the fake repository was never called.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
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
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/outfits/outfits_controller.dart';
import 'package:frontend_flutter/features/outfits/outfits_state.dart';

import '../features/seasons/seasons_test_fakes.dart';

OutfitView _outfit({String? seasonId = 'season-1', int version = 3}) =>
    OutfitView(
      (b) => b
        ..id = 'o-1'
        ..characterId = 'char-1'
        ..name = 'Alltagslook'
        ..notes = ''
        ..seasonId = seasonId
        ..version = version
        ..updatedAt = DateTime.utc(2026, 10, 27)
        ..pieceIds.replace(BuiltList<String>())
        ..pieces.replace(BuiltList<OutfitPieceView>())
        ..photos.replace(BuiltList<OutfitPhotoView>()),
    );

PieceView _piece(String id) => PieceView(
  (b) => b
    ..id = id
    ..name = 'Hemd'
    ..notes = ''
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
          BuiltList<String>(costumeRole ? ['assign_costumes'] : <String>[]),
        ),
    );

/// Counts every dispatched mutation; never touches the network.
class _CountingOutfitRepository extends OutfitRepository {
  _CountingOutfitRepository(super.api, super.cache);

  int mutations = 0;

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
  Future<Result<IdVersionResponse>> create({
    required String characterId,
    required String name,
    List<String> pieceIds = const [],
  }) async {
    mutations++;
    return Right<ProblemError, IdVersionResponse>(
      IdVersionResponse(
        (b) => b
          ..id = 'o-new'
          ..version = 1,
      ),
    );
  }

  @override
  Future<Result<IdVersionResponse>> createVariant(
    String sourceOutfitId, {
    String? name,
    List<String>? pieceIds,
    String? notes,
  }) async {
    mutations++;
    return Right<ProblemError, IdVersionResponse>(
      IdVersionResponse(
        (b) => b
          ..id = 'o-variant'
          ..version = 1,
      ),
    );
  }

  @override
  Future<Result<int>> addPiece(String id, AddOutfitPieceRequest request) async {
    mutations++;
    return Right<ProblemError, int>(request.version + 1);
  }

  @override
  Future<Result<int>> rename(String id, RenameOutfitRequest request) async {
    mutations++;
    return Right<ProblemError, int>(request.version + 1);
  }
}

class _NoopScheduler extends ReconciliationScheduler {
  @override
  Future<void> tick(int attempt) async {}
}

void main() {
  late CacheDatabase db;
  late _CountingOutfitRepository repo;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _CountingOutfitRepository(BreakdownApi(), OutfitCacheDao(db));
  });

  ProviderContainer makeContainer({
    required Result<SeasonMembershipDto> Function() membership,
    required OutfitView outfit,
    void Function()? onMembershipFetch,
  }) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        outfitRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => _NoopScheduler()),
        membershipFetchProvider('season-1').overrideWith((ref) async {
          onMembershipFetch?.call();
          return membership();
        }),
        outfitsListFetchProvider('char-1').overrideWith(
          (ref) async => Right<ProblemError, List<OutfitView>>([outfit]),
        ),
        outfitsViewProvider('char-1')
            .overrideWith((ref) => OutfitsView(rows: [outfit], isStale: false)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  OutfitsController controllerOf(ProviderContainer container) =>
      container.read(outfitsControllerProvider('char-1').notifier);

  group('look AUTHZ-GATE tri-state', () {
    test('a membership fetch failure is pending, not a denial', () async {
      final container = makeContainer(
        membership: () => const Left(ProblemError(code: 'transport.unknown')),
        outfit: _outfit(),
      );

      final result = await controllerOf(container)
          .addPiece(_outfit(), _piece('p-1'));

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()?.code, 'membership.pending');
      expect(repo.mutations, 0);
    });

    test('the failed membership state is dropped so the next command '
        're-fetches (retry-ability)', () async {
      var failing = true;
      var fetches = 0;
      final container = makeContainer(
        membership: () => failing
            ? const Left(ProblemError(code: 'transport.unknown'))
            : Right(_membership(costumeRole: true)),
        outfit: _outfit(),
        onMembershipFetch: () => fetches++,
      );
      final controller = controllerOf(container);

      final pending = await controller.addPiece(_outfit(), _piece('p-1'));
      expect(pending.getLeft().toNullable()?.code, 'membership.pending');
      expect(repo.mutations, 0);
      expect(fetches, 1);

      failing = false;
      final ok = await controller.addPiece(_outfit(), _piece('p-1'));
      expect(ok.isRight(), isTrue);
      expect(repo.mutations, 1);
      // The invalidation re-executed the fetch instead of replaying the
      // retained Left.
      expect(fetches, 2);
      await pumpEventQueue();
    });

    test('a resolved denial is domain.forbidden (the server code)', () async {
      final container = makeContainer(
        membership: () => Right(_membership(costumeRole: false)),
        outfit: _outfit(),
      );
      final controller = controllerOf(container);

      final renamed = await controller.rename(_outfit(), 'Neu');
      expect(renamed.getLeft().toNullable()?.code, 'domain.forbidden');

      final added = await controller.addPiece(_outfit(), _piece('p-1'));
      expect(added.getLeft().toNullable()?.code, 'domain.forbidden');

      final photo = await controller.uploadPhoto(
        outfit: _outfit(),
        bytes: Uint8List(0),
        contentType: 'image/jpeg',
      );
      expect(photo.getLeft().toNullable()?.code, 'domain.forbidden');

      expect(repo.mutations, 0);
    });

    test('an unresolvable scope stays pending instead of skipping the '
        'gate', () async {
      final container = makeContainer(
        membership: () => Right(_membership(costumeRole: true)),
        outfit: _outfit(seasonId: null),
      );

      final result = await controllerOf(container)
          .createVariant(_outfit(seasonId: null));

      expect(result.getLeft().toNullable()?.code, 'membership.pending');
      expect(repo.mutations, 0);
    });
  });
}
