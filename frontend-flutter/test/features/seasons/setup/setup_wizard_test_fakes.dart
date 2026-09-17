// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/episode_repository.dart';

/// Repository fakes for the setup-wizard controller tests: `create` is
/// scriptable (Ok/Err branches), everything else is never touched by the
/// dispatch reduction (the wizard only dispatches create commands).
///
/// The fakes extend the real repositories so the dispatch's payload
/// assertions catch a wrong field mapping (season_id/block_id sourced
/// from the WRONG place would fail the id-flow assertions loudly).

/// Creates an in-memory Drift database for the fakes' DAO super args.
CacheDatabase wizardFakeDb() => CacheDatabase(NativeDatabase.memory());

class FakeBlockRepository extends BlockRepository {
  FakeBlockRepository(CacheDatabase db)
    : super(BreakdownApi(), BlockCacheDao(db));

  /// Scripted outcomes consumed in order; `null` = default Ok.
  final List<Result<IdVersionResponse>> createResults = [];

  int createCalls = 0;
  final List<CreateBlockRequest> lastCreateRequests = [];

  /// Scripted season-scoped blocks projection for [listBySeason] (the
  /// series-number derivation reads it). `null` = default empty projection.
  Result<List<BlockView>>? listBySeasonResult;

  int listBySeasonCalls = 0;

  @override
  Future<Result<List<BlockView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    listBySeasonCalls++;
    return listBySeasonResult ?? const Right<ProblemError, List<BlockView>>([]);
  }

  @override
  Future<Result<IdVersionResponse>> create(CreateBlockRequest request) {
    lastCreateRequests.add(request);
    final Result<IdVersionResponse> scripted;
    if (createResults.isEmpty) {
      createCalls++;
      scripted = Right<ProblemError, IdVersionResponse>(_ok('nb$createCalls'));
    } else {
      scripted = createResults.removeAt(0);
      if (scripted.isRight()) createCalls++;
    }
    return Future.value(scripted);
  }
}

class FakeEpisodeRepository extends EpisodeRepository {
  FakeEpisodeRepository(CacheDatabase db)
    : super(BreakdownApi(), EpisodeCacheDao(db));

  final List<Result<IdVersionResponse>> createResults = [];

  int createCalls = 0;
  final List<CreateEpisodeRequest> lastCreateRequests = [];

  /// Scripted block-scoped episodes projection for [listByBlock] (the
  /// episode-number derivation reads it). `null` = default empty.
  Result<List<EpisodeView>>? listByBlockResult;

  int listByBlockCalls = 0;

  @override
  Future<Result<List<EpisodeView>>> listByBlock(
    String blockId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    listByBlockCalls++;
    return listByBlockResult ??
        const Right<ProblemError, List<EpisodeView>>([]);
  }

  @override
  Future<Result<IdVersionResponse>> create(CreateEpisodeRequest request) {
    lastCreateRequests.add(request);
    final Result<IdVersionResponse> scripted;
    if (createResults.isEmpty) {
      createCalls++;
      scripted = Right<ProblemError, IdVersionResponse>(_ok('ne$createCalls'));
    } else {
      scripted = createResults.removeAt(0);
      if (scripted.isRight()) createCalls++;
    }
    return Future.value(scripted);
  }
}

IdVersionResponse _ok(String id) => IdVersionResponse(
  (b) => b
    ..id = id
    ..version = 1,
);
