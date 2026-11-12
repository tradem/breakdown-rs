// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 tests for the apply-stream AUTHZ-GATE (D6) and for the idle-close
// reconnect budget of `watchApplyProgress` (issue #762, CodeRabbit review of
// PR #798).
//
// The gate must mirror the backend's handler-internal gate on
// `GET /v1/ai-import/jobs/{id}/apply-events` BEFORE any request leaves the
// client: a denial issues **zero** stream calls (provable with a fake
// repository call count), and a still-pending membership disables the watch
// without ever rendering the 403 narrative.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';

const _jobId = 'job-apply-gate';
const _seasonId = 'season-1';

/// Repository fake: counts `watchApplyProgress` opens and replays a scripted
/// stream, so "the denial issued no request" is a call-count assertion.
class _FakeApplyRepository extends AiImportRepository {
  _FakeApplyRepository(super.api, super.cache);

  int watchCalls = 0;
  List<Result<ApplyProgressFrame>> frames = const [];

  @override
  Stream<Result<ApplyProgressFrame>> watchApplyProgress(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxJobWatchAttempts,
    int maxIdleReconnects = kMaxApplyIdleReconnects,
    Duration receiveTimeout = kSseReceiveTimeout,
    CancelToken? cancelToken,
  }) {
    watchCalls++;
    return Stream.fromIterable(frames);
  }
}

SeasonMembershipDto _membership({required bool costumeRole}) =>
    SeasonMembershipDto(
      (b) => b
        ..seasonId = _seasonId
        ..hasActiveCostumeRoleInSeason = costumeRole
        ..capabilities.replace(BuiltList<String>()),
    );

ApplyProgress _progress({int applied = 3, int total = 10}) {
  final startedAt = DateTime.utc(2026, 11, 2, 10);
  return ApplyProgress(
    (b) => b
      ..stage = ApplyStage.applying
      ..applied = applied
      ..total = total
      ..startedAt = startedAt
      ..updatedAt = startedAt.add(const Duration(seconds: 30)),
  );
}

void main() {
  late CacheDatabase db;
  late _FakeApplyRepository repo;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = _FakeApplyRepository(BreakdownApi(), AiImportJobsCacheDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer container({
    String? seasonId = _seasonId,
    bool costumeRole = true,
    Object? membershipThrows,
  }) {
    final c = ProviderContainer(
      overrides: [
        aiImportRepositoryProvider.overrideWithValue(repo),
        aiApplyJobSeasonIdProvider(_jobId)
            .overrideWith((ref) async => seasonId),
        membershipFetchProvider(_seasonId).overrideWith((ref) async {
          if (membershipThrows != null) throw membershipThrows;
          return Right(_membership(costumeRole: costumeRole));
        }),
      ],
    );
    addTearDown(() {
      try {
        c.dispose();
      } on StateError {
        // Already disposed by the test body — fine.
      }
    });
    return c;
  }

  /// First state of the run provider, read with a live subscription: an
  /// autoDispose provider must not be disposed between the listen and the
  /// `future` read (riverpod would throw "disposed during loading state").
  Future<AiApplyRunState> firstState(ProviderContainer c) async {
    final sub = c.listen(aiApplyRunProvider(_jobId), (_, _) {});
    addTearDown(sub.close);
    return c.read(aiApplyRunProvider(_jobId).future);
  }

  Future<ProblemError?> gateOf(ProviderContainer c) async {
    final sub = c.listen(aiApplyStreamGateProvider(_jobId), (_, _) {});
    addTearDown(sub.close);
    return c.read(aiApplyStreamGateProvider(_jobId).future);
  }

  test('a member with the season role lets the watch open', () async {
    repo.frames = [
      Right<ProblemError, ApplyProgressFrame>(
        ApplyProgressFrame(progress: _progress()),
      ),
    ];
    final c = container(costumeRole: true);
    final first = await firstState(c);
    expect(first, isA<AiApplyRunRunning>());
    expect(
      repo.watchCalls,
      1,
      reason: 'the gate allowed the stream and it opened exactly once',
    );
  });

  test('a non-member denial issues ZERO stream requests', () async {
    final c = container(costumeRole: false);
    final first = await firstState(c);
    expect(first, isA<AiApplyRunDenied>());
    final denied = first as AiApplyRunDenied;
    expect(denied.error.code, 'ai_import.forbidden');
    expect(denied.error.status, 403);
    expect(denied.isPending, isFalse);
    expect(
      repo.watchCalls,
      0,
      reason: 'the client mirror denies BEFORE the network call (D6)',
    );
  });

  test('an unresolved season scope is PENDING, never a denial', () async {
    final c = container(seasonId: null);
    final first = await firstState(c);
    expect(first, isA<AiApplyRunDenied>());
    final denied = first as AiApplyRunDenied;
    expect(denied.error.code, 'membership.pending');
    expect(denied.isPending, isTrue);
    expect(
      denied.error.status,
      isNull,
      reason: 'a pending gate is not an HTTP denial',
    );
    expect(repo.watchCalls, 0);
  });

  test(
    'a failed membership read is pending, never the 403 narrative',
    () async {
      final c = container(membershipThrows: StateError('transport down'));
      final first = await firstState(c);
      expect((first as AiApplyRunDenied).isPending, isTrue);
      expect(repo.watchCalls, 0);
    },
  );

  test('the gate provider itself answers allow/deny/pending', () async {
    expect(await gateOf(container(costumeRole: true)), isNull);
    expect(
      (await gateOf(container(costumeRole: false)))?.code,
      'ai_import.forbidden',
    );
    final pending = await gateOf(container(seasonId: null));
    expect(pending?.code, 'membership.pending');
    expect(pending?.status, isNull);
  });
}
