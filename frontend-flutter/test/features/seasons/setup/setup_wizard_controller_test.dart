// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/seasons_view.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_state.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_controller.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_state.dart';

import '../seasons_test_fakes.dart';
import 'setup_wizard_test_fakes.dart';

const _conflict = ProblemError(code: 'blocks.conflict', status: 409);
const _transport = ProblemError(code: 'transport.connectionError');

class _Fixture {
  _Fixture(
    this.container,
    this.sub,
    this.db,
    this.seasonRepo,
    this.blockRepo,
    this.episodeRepo,
    this.seasonsHolder,
  );

  final ProviderContainer container;

  /// Keeps the autoDispose wizard controller alive across the test's
  /// awaits (the screen's `ref.watch` plays this role in production).
  final ProviderSubscription<SetupWizardState> sub;
  final CacheDatabase db;
  final FakeSeasonRepository seasonRepo;
  final FakeBlockRepository blockRepo;
  final FakeEpisodeRepository episodeRepo;

  /// The seasons list projection the fetch seam serves.
  final ValueNotifier<Result<List<SeasonView>>> seasonsHolder;

  SetupWizardController get controller =>
      container.read(setupWizardControllerProvider.notifier);

  SetupWizardState get state => container.read(setupWizardControllerProvider);

  List<SeasonOverlay> get seasonOverlays =>
      container.read(seasonOverlaysProvider);
}

Future<_Fixture> _buildFixture({
  List<SeasonView>? seasons,
  bool signedIn = true,
}) async {
  final db = CacheDatabase(NativeDatabase.memory());
  final seasonRepo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
  final blockRepo = FakeBlockRepository(db);
  final episodeRepo = FakeEpisodeRepository(db);
  final holder = ValueNotifier<Result<List<SeasonView>>>(
    seasons == null
        ? const Left(ProblemError(code: 'transport.down'))
        : Right(seasons),
  );
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      seasonRepositoryProvider.overrideWithValue(seasonRepo),
      blockRepositoryProvider.overrideWithValue(blockRepo),
      episodeRepositoryProvider.overrideWithValue(episodeRepo),
      reconciliationSchedulerProvider.overrideWith(
        (ref) => const ImmediateReconciliationScheduler(),
      ),
      seasonsListFetchProvider.overrideWith((ref) async {
        final r = ref.watch(seasonRepositoryProvider);
        return r.fetchAndCacheList(() async => holder.value);
      }),
      // The wizard's seeds read the projection selector synchronously; a
      // constant view keeps the derivation deterministic.
      seasonsView.overrideWith(
        (ref) => SeasonsView(rows: seasons ?? const [], isStale: false),
      ),
      // The block/episode projections the settle-reconcile serves (empty
      // = projector lag; the overlays are then retained — irrelevant to
      // the assertions).
      blocksListFetchProvider.overrideWith((ref, seasonId) async {
        final r = ref.watch(blockRepositoryProvider);
        return r.listBySeason(seasonId);
      }),
      // The generated family flattens its parameters into one record.
      episodesListFetchProvider.overrideWith((ref, ids) async {
        final (blockId, seasonId) = ids;
        final r = ref.watch(episodeRepositoryProvider);
        return r.listByBlock(blockId);
      }),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  if (signedIn) {
    await container.read(authSessionControllerProvider.notifier).signIn();
  }
  // The screen's ref.watch keeps the autoDispose controller alive while
  // the wizard route is open; a test listener plays that role here.
  final sub = container.listen(setupWizardControllerProvider, (_, _) {});
  return _Fixture(
    container,
    sub,
    db,
    seasonRepo,
    blockRepo,
    episodeRepo,
    holder,
  );
}

EpisodeView _episodeView(String id, {required int number, String? blockId}) =>
    EpisodeView(
      (b) => b
        ..id = id
        ..number = number
        ..blockId = blockId ?? 'block-1'
        ..seriesId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

BlockView _blockView(String id, {required int number, String? seasonId}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId ?? 'season-1'
        ..seriesId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

SeasonView _season(String id, int number) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Flushes the fire-and-forget settle reconciliation (microtask-only —
/// the fixture uses the immediate scheduler, no wall-clock waits).
Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupWizardController transitions (task 2.2)', () {
    test('build seeds one default draft on the Season step', () async {
      final ctx = await _buildFixture();
      expect(ctx.state.step, SetupWizardStep.season);
      expect(ctx.state.phase, SetupWizardPhase.editing);
      expect(ctx.state.blocks, hasLength(1));
      expect(ctx.state.blocks.single.episodeCount, 8);
    });

    test('seedSeasonNumber applies the smart default (max+1)', () async {
      final ctx = await _buildFixture(
        seasons: [_season('s1', 1), _season('s2', 2)],
      );
      // The screen passes the already-loaded projection rows.
      ctx.controller.seedSeasonNumber([_season('s1', 1), _season('s2', 2)]);
      expect(ctx.state.seasonNumber, 3);
    });

    test('seedSeasonNumber with an empty projection defaults to 1', () async {
      final ctx = await _buildFixture();
      ctx.controller.seedSeasonNumber(const []);
      expect(ctx.state.seasonNumber, 1);
    });

    test('next/back walk the steps linearly', () async {
      final ctx = await _buildFixture();
      expect(ctx.controller.next(), isNull);
      expect(ctx.state.step, SetupWizardStep.blocks);
      expect(ctx.controller.next(), isNull);
      expect(ctx.state.step, SetupWizardStep.review);
      ctx.controller.back();
      expect(ctx.state.step, SetupWizardStep.blocks);
      ctx.controller.back();
      expect(ctx.state.step, SetupWizardStep.season);
    });

    test('zero drafts block forward navigation with noBlocks (spec)', () async {
      final ctx = await _buildFixture();
      ctx.controller.next(); // → blocks
      while (ctx.state.blocks.isNotEmpty) {
        ctx.controller.removeBlockAt(0);
      }
      expect(ctx.controller.next(), WizardFieldError.noBlocks);
      expect(ctx.state.step, SetupWizardStep.blocks);
    });

    test('editing guards: a non-editing phase ignores mutations', () async {
      var ctx = await _buildFixture();
      ctx.controller.setSeasonName('Test');
      ctx.controller.removeBlockAt(0);
      ctx.controller.applyTemplate(count: 1, episodesPerBlock: 4);
      // Drive into a NON-editing phase for real: the first block create
      // fails → partial failure (created refs retained).
      ctx.blockRepo.createResults.add(
        Left<ProblemError, IdVersionResponse>(_conflict),
      );
      await ctx.controller.submit(seriesId: 'series-1');
      await _flush();
      expect(ctx.state.phase, SetupWizardPhase.partialFailure);
      // The guard: field mutations in a non-editing phase are no-ops.
      ctx.controller.setSeasonName('Ignored');
      expect(ctx.state.seasonName, 'Test');
    });

    test('applyTemplate appends editable drafts (spec: 4 × 8)', () async {
      final ctx = await _buildFixture();
      ctx.controller.applyTemplate(count: 4, episodesPerBlock: 8);
      expect(ctx.state.blocks, hasLength(5)); // 1 default + 4 template
      expect(
        ctx.state.blocks.sublist(1).every((b) => b.episodeCount == 8),
        isTrue,
      );
      // Each stays individually editable afterwards.
      ctx.controller.setBlockTitle(2, 'Second');
      ctx.controller.setBlockEpisodeCount(2, 3);
      expect(ctx.state.blocks[2].title, 'Second');
      expect(ctx.state.blocks[2].episodeCount, 3);
    });

    test('removeBlockAt updates the draft list', () async {
      final ctx = await _buildFixture();
      ctx.controller.removeBlockAt(0);
      expect(ctx.state.blocks, isEmpty);
      // Out-of-range removal is a no-op (never throws — no platform
      // exception surfaces).
      ctx.controller.removeBlockAt(9);
      expect(ctx.state.blocks, isEmpty);
    });

    test(
      'seedDerivedNumbers derives series-scoped block + episode numbers',
      () async {
        final ctx = await _buildFixture(
          seasons: [_season('s1', 1), _season('s2', 2)],
        );
        // Both seasons belong to the series; blocks 3 and 5 exist, and
        // block b1 already holds episodes 7 and 9 → the first free
        // series-scoped numbers are block 6 / episode 10.
        ctx.blockRepo.listBySeasonResult = Right([
          _blockView('b1', number: 3, seasonId: 's1'),
          _blockView('b2', number: 5, seasonId: 's2'),
        ]);
        ctx.episodeRepo.listByBlockResult = Right([
          _episodeView('e1', number: 7, blockId: 'b1'),
          _episodeView('e2', number: 9, blockId: 'b1'),
        ]);

        await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');

        expect(ctx.state.nextBlockNumber, 6);
        expect(ctx.state.nextEpisodeNumber, 10);
        expect(ctx.blockRepo.listBySeasonCalls, 2);
        // The series' episodes derive in ONE live series-scoped read
        // (issue #455 derive repair: `GET /v1/episodes?series_id=…`), not
        // a per-block walk.
        expect(ctx.episodeRepo.listBySeriesCalls, 1);
        expect(ctx.episodeRepo.listByBlockCalls, 0);
      },
    );

    test('seedDerivedNumbers with a failed fetch degrades to base 1', () async {
      final ctx = await _buildFixture();
      ctx.blockRepo.listBySeasonResult =
          const Left<ProblemError, List<BlockView>>(
            ProblemError(code: 'transport.down'),
          );
      await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');
      expect(ctx.state.nextBlockNumber, 1);
      expect(ctx.state.nextEpisodeNumber, 1);
    });

    test('issue #455: a FAILED series episode-base read degrades to base 1 '
        '(Err branch of the live listBySeries derivation)', () async {
      final ctx = await _buildFixture(seasons: [_season('s1', 1)]);
      ctx.blockRepo.listBySeasonResult = Right([
        _blockView('b1', number: 3, seasonId: 's1'),
      ]);
      // The series' episodes read fails (e.g. no block membership yet at
      // wizard open): the derivation must degrade honestly to episode
      // base 1 — never fabricate a number that could 409.
      ctx.episodeRepo.listBySeriesResult =
          const Left<ProblemError, List<EpisodeView>>(
            ProblemError(code: 'transport.down'),
          );

      await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');

      expect(ctx.state.nextBlockNumber, 4);
      expect(ctx.state.nextEpisodeNumber, 1);
    });

    test('issue #455: boot-time seasonsView being EMPTY (retained snapshot in '
        'the boot window) does not skew the derivation — it reads the live '
        'fetch, not seasonsView', () async {
      final ctx = await _buildFixture();
      // The controller test harness serves an EMPTY `seasonsView` (the
      // old derivation read it), but the live fetch sees two seasons
      // with blocks — the derivation must reflect the LIVE projection.
      ctx.seasonsHolder.value = Right([_season('s1', 1), _season('s2', 2)]);
      ctx.blockRepo.listBySeasonResult = Right([
        _blockView('b1', number: 9, seasonId: 's1'),
      ]);
      ctx.episodeRepo.listByBlockResult = Right([
        _episodeView('e1', number: 5, blockId: 'b1'),
      ]);

      await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');

      // Derived from the LIVE fetch (block 9 / episode 5), not from an
      // empty boot-time seasonsView.
      expect(ctx.state.nextBlockNumber, 10);
      expect(ctx.state.nextEpisodeNumber, 6);
    });

    test(
      'issue #455: seedDerivedNumbers re-derives on demand (repeatable) — '
      'numbers update when the series accumulates state between runs',
      () async {
        final ctx = await _buildFixture();
        // First run: no blocks (empty series) → base 1.
        await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');
        expect(ctx.state.nextBlockNumber, 1);
        expect(ctx.state.numbersSeeded, isTrue);

        // Concurrent harness seeding lands block 7 before the dispatch;
        // a repeated derivation sees it and advances the plan.
        ctx.blockRepo.listBySeasonResult = Right([
          _blockView('b7', number: 7, seasonId: 's1'),
        ]);
        ctx.seasonsHolder.value = Right([_season('s1', 1)]);
        await ctx.controller.seedDerivedNumbers(seriesId: 'series-1');
        expect(ctx.state.nextBlockNumber, 8);
      },
    );

    test('reset restores the initial state (reopen starts fresh)', () async {
      final ctx = await _buildFixture();
      ctx.controller.setSeasonNumber(9);
      ctx.controller.setSeasonName('Sommer');
      ctx.controller.applyTemplate(count: 2, episodesPerBlock: 6);
      ctx.controller.reset();
      expect(ctx.state.seasonNumber, 1);
      expect(ctx.state.seasonName, '');
      expect(ctx.state.blocks, hasLength(1));
    });
  });

  group('SetupWizardController dispatch (tasks 3.1/3.2)', () {
    _Fixture seededTwoByFour(_Fixture ctx) {
      // The controller opens with one default draft; drop it so the plan
      // is exactly the template's 2 × 4.
      ctx.controller.removeBlockAt(0);
      ctx.controller.applyTemplate(count: 2, episodesPerBlock: 4);
      return ctx;
    }

    test('happy path: season → blocks → episodes complete; ids flow from '
        'responses (CQRS boundary)', () async {
      var ctx = await _buildFixture();
      ctx = seededTwoByFour(ctx);

      await ctx.controller.submit(seriesId: 'series-7');
      await _flush();

      expect(ctx.state.phase, SetupWizardPhase.completed);
      // 1 season + 2 blocks + 8 episodes = 11 commands, all acked.
      expect(ctx.state.dispatchDone, 11);
      expect(ctx.state.dispatchTotal, 11);
      // The season create carried the form mapping.
      final seasonReq = ctx.seasonRepo.lastCreateRequest!;
      expect(seasonReq.seriesId, 'series-7');
      expect(seasonReq.number, 1);
      // Ids flow EXCLUSIVELY from the responses: the season id in the
      // block payloads is the fake season create's assigned id.
      final seasonId = ctx.state.createdSeason!.id;
      expect(seasonId, 'n1');
      for (final req in ctx.blockRepo.lastCreateRequests) {
        expect(req.seasonId, seasonId);
        expect(req.seriesId, 'series-7');
      }
      for (var i = 0; i < ctx.episodeRepo.lastCreateRequests.length; i++) {
        final req = ctx.episodeRepo.lastCreateRequests[i];
        expect(req.blockId, 'nb${i < 4 ? 1 : 2}');
        // Plan-sequential series-scoped numbers: 1..4 for block 1, 5..8
        // for block 2.
        expect(req.number, i + 1);
      }
      // The created-so-far summary lists the created structure.
      expect(ctx.state.createdBlocks, hasLength(2));
      expect(ctx.state.createdBlocks[0].episodesCreated, 4);
      expect(ctx.state.createdBlocks[1].episodesCreated, 4);
      // The season overlay was inserted for the seasons screen.
      expect(ctx.seasonOverlays.any((o) => o.id == 'n1'), isTrue);
    });

    test('issue #455: submit re-derives numbers from the live projection '
        'BEFORE the first command (concurrent harness writes cannot 409 the '
        'first block create)', () async {
      var ctx = await _buildFixture();
      ctx = seededTwoByFour(ctx);
      // The wizard opened and derived base 1; by submit time the series
      // accumulated block 12 in season s1 (same series-7 the dispatch
      // targets). The submit-time re-derive must dispatch at block 13,
      // NOT the stale 1.
      ctx.blockRepo.listBySeasonResult = Right([
        _blockView('b12', number: 12, seasonId: 's1'),
      ]);
      final s1 = SeasonView(
        (b) => b
          ..id = 's1'
          ..number = 1
          ..seriesId = 'series-7'
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      );
      ctx.seasonsHolder.value = Right([s1]);

      await ctx.controller.submit(seriesId: 'series-7');
      await _flush();

      expect(ctx.state.phase, SetupWizardPhase.completed);
      // The first block create was at number 13 (the fresh derivation),
      // not the stale 1.
      expect(ctx.blockRepo.lastCreateRequests.first.number, 13);
      expect(ctx.state.nextBlockNumber, 13);
    });

    test(
      'block create conflict stops the sequence (partial failure)',
      () async {
        var ctx = await _buildFixture();
        ctx = seededTwoByFour(ctx);
        ctx.blockRepo.createResults.add(
          Left<ProblemError, IdVersionResponse>(_conflict),
        );

        await ctx.controller.submit(seriesId: 'series-1');
        await _flush();

        expect(ctx.state.phase, SetupWizardPhase.partialFailure);
        expect(ctx.state.failure!.code, 'blocks.conflict');
        // Created-so-far: the season only (the first block create failed).
        expect(ctx.state.createdSeason, isNotNull);
        expect(ctx.state.createdBlocks, isEmpty);
        // Only ONE block create reached the network.
        expect(ctx.blockRepo.lastCreateRequests, hasLength(1));
      },
    );

    test(
      'episode create failure retains the created-so-far count (resume '
      'cursor) and retry finishes the remaining commands in-session',
      () async {
        var ctx = await _buildFixture();
        ctx = seededTwoByFour(ctx);
        // Block 1, episode 3 fails (2 acked episodes of block 1 exist).
        final episodeScript = <Result<IdVersionResponse>>[
          for (var i = 0; i < 2; i++)
            Right<ProblemError, IdVersionResponse>(
              IdVersionResponse(
                (b) => b
                  ..id = 'ne$i'
                  ..version = 1,
              ),
            ),
          Left<ProblemError, IdVersionResponse>(_transport),
        ];
        ctx.episodeRepo.createResults.addAll(episodeScript);

        await ctx.controller.submit(seriesId: 'series-1');
        await _flush();

        expect(ctx.state.phase, SetupWizardPhase.partialFailure);
        expect(ctx.state.failure!.code, 'transport.connectionError');
        // Created-so-far: season + block 1 (2 of its 4 episodes).
        expect(ctx.state.createdSeason!.id, 'n1');
        expect(ctx.state.createdBlocks.single.episodesCreated, 2);

        // Retry (in-session): continues from episode 3, no duplicate
        // re-dispatch of the acked commands.
        final seasonCreatesBefore = ctx.seasonRepo.createCalls;
        final blockCreatesBefore = ctx.blockRepo.lastCreateRequests.length;
        await ctx.controller.retryRemaining(seriesId: 'series-1');
        await _flush();

        expect(ctx.state.phase, SetupWizardPhase.completed);
        expect(ctx.seasonRepo.createCalls, seasonCreatesBefore);
        // The retry creates ONLY the block that was never created (the
        // sequence stopped at block 1's third episode).
        expect(
          ctx.blockRepo.lastCreateRequests,
          hasLength(blockCreatesBefore + 1),
        );
        // The resumed episode creates continue at number 3 (0-based index 2
        // of block 1), then block 1 episodes 4, then block 2's four.
        // The FAILED attempt (number 3) also reached the network — it is
        // recorded as request index 2; the resume starts after it.
        final resumedNumbers = ctx.episodeRepo.lastCreateRequests
            .sublist(3)
            .map((r) => r.number)
            .toList();
        // Plan-sequential series-scoped numbers: block 1's 3rd/4th episode
        // (3, 4), then block 2's four episodes (5..8) — recomputing the
        // derived numbers on retry reproduces the acked ones exactly.
        expect(resumedNumbers, [3, 4, 5, 6, 7, 8]);
        expect(ctx.state.dispatchDone, 11);
      },
    );

    test('signed-out submit is denied client-side; NOTHING dispatches '
        '(AUTHZ-GATE)', () async {
      var ctx = await _buildFixture(signedIn: false);
      ctx = seededTwoByFour(ctx);

      await ctx.controller.submit(seriesId: 'series-1');
      await _flush();

      expect(ctx.state.phase, SetupWizardPhase.partialFailure);
      expect(ctx.state.failure!.code, 'authz.denied');
      // No network call was ever issued.
      expect(ctx.seasonRepo.createCalls, 0);
      expect(ctx.blockRepo.lastCreateRequests, isEmpty);
      expect(ctx.episodeRepo.lastCreateRequests, isEmpty);
    });

    test(
      'retryRemaining outside the partial-failure phase is a no-op',
      () async {
        var ctx = await _buildFixture();
        ctx = seededTwoByFour(ctx);
        await ctx.controller.retryRemaining(seriesId: 'series-1');
        expect(ctx.state.phase, SetupWizardPhase.editing);
        expect(ctx.seasonRepo.createCalls, 0);
      },
    );
  });
}
