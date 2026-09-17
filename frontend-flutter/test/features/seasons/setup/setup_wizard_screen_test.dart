// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_view.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_controller.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_screen.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_state.dart';

import '../seasons_test_fakes.dart';
import 'setup_wizard_test_fakes.dart';

const _conflict = ProblemError(code: 'blocks.conflict', status: 409);

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate dispatch spinner may be on screen).
Future<void> pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// A season-create fake whose command can be held in flight (a pending
/// completer) so the dispatching phase is observable and deterministic —
/// never wall-clock gated (AGENTS.md §6).
class _GatedSeasonRepository extends FakeSeasonRepository {
  _GatedSeasonRepository(super.api, super.cache);

  Completer<Result<IdVersionResponse>>? gate;

  @override
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) async {
    final g = gate;
    if (g != null) return g.future;
    return super.create(request);
  }
}

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

SeasonView _season(String id, int number, {String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _Fixture {
  _Fixture(
    this.container,
    this.db,
    this.seasonRepo,
    this.blockRepo,
    this.episodeRepo,
    this.seasonsHolder,
  );

  final ProviderContainer container;
  final CacheDatabase db;
  final _GatedSeasonRepository seasonRepo;
  final FakeBlockRepository blockRepo;
  final FakeEpisodeRepository episodeRepo;
  final ValueNotifier<Result<List<SeasonView>>> seasonsHolder;

  SetupWizardState get state => container.read(setupWizardControllerProvider);
}

Future<_Fixture> _buildFixture({
  List<SeasonView>? seasons,
  bool aiConfigAvailable = false,
}) async {
  final db = CacheDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final seasonRepo = _GatedSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
  final blockRepo = FakeBlockRepository(db);
  final episodeRepo = FakeEpisodeRepository(db);
  final holder = ValueNotifier<Result<List<SeasonView>>>(
    seasons == null
        ? const Left<ProblemError, List<SeasonView>>(
            ProblemError(code: 'transport.down'),
          )
        : Right<ProblemError, List<SeasonView>>(seasons),
  );
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      seasonRepositoryProvider.overrideWithValue(seasonRepo),
      blockRepositoryProvider.overrideWithValue(blockRepo),
      episodeRepositoryProvider.overrideWithValue(episodeRepo),
      // Deterministic settle-reconcile (no wall-clock, AGENTS.md §6).
      reconciliationSchedulerProvider.overrideWith(
        (ref) => const ImmediateReconciliationScheduler(),
      ),
      seasonsListFetchProvider.overrideWith((ref) async {
        final r = ref.watch(seasonRepositoryProvider);
        return r.fetchAndCacheList(() async => holder.value);
      }),
      // The screen's initState seeds the smart default from this view.
      seasonsView.overrideWith(
        (ref) => SeasonsView(rows: seasons ?? const [], isStale: false),
      ),
      blocksListFetchProvider.overrideWith((ref, seasonId) async {
        final r = ref.watch(blockRepositoryProvider);
        return r.listBySeason(seasonId);
      }),
      episodesListFetchProvider.overrideWith((ref, ids) async {
        final (blockId, seasonId) = ids;
        final r = ref.watch(episodeRepositoryProvider);
        return r.listByBlock(blockId);
      }),
      // The completion CTA's AI-configuration read (design D4) —
      // overridden directly; the config screen's own tests cover the read.
      wizardAiConfigAvailableProvider.overrideWithValue(aiConfigAvailable),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authSessionControllerProvider.notifier).signIn();
  return _Fixture(container, db, seasonRepo, blockRepo, episodeRepo, holder);
}

Future<void> _pumpWizard(
  WidgetTester tester,
  _Fixture ctx, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ctx.container,
      child: MaterialApp(
        theme: theme ?? AppThemes.light(),
        home: const SetupWizardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Season step (task 4.1)', () {
    testWidgets('smart default is seeded from the projection (max+1)', (
      tester,
    ) async {
      final ctx = await _buildFixture(
        seasons: [_season('s1', 1), _season('s2', 2)],
      );
      await _pumpWizard(tester, ctx);

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('wizard-number-field')))
            .controller!
            .text,
        '3',
      );
      // Live preview of the resulting title.
      expect(find.text('Season 3'), findsOneWidget);
      expect(find.text('Schritt 1 von 3'), findsOneWidget);
    });

    testWidgets('name entry updates the live preview', (tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);

      await tester.enterText(find.byKey(const Key('wizard-name-field')), 'X');
      await tester.pump();
      expect(find.text('Season 1 · X'), findsOneWidget);
    });

    testWidgets('invalid number disables Weiter with the inline copy', (
      tester,
    ) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);

      await tester.enterText(find.byKey(const Key('wizard-number-field')), '0');
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wizard-next')))
            .onPressed,
        isNull,
      );
      // Inline validation copy keyed per error code (never a platform
      // exception surface).
      expect(find.textContaining('größer als 0'), findsOneWidget);
    });
  });

  group('Blocks step (task 4.2)', () {
    Future<_Fixture> onBlocks(WidgetTester tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      return ctx;
    }

    testWidgets('renders the default draft and the template chips', (
      tester,
    ) async {
      await onBlocks(tester);

      expect(find.byKey(const Key('wizard-block-draft-0')), findsOneWidget);
      expect(
        find.byKey(const Key('wizard-apply-template-4x8')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('wizard-apply-template-3x6')),
        findsOneWidget,
      );
      expect(find.text('Schritt 2 von 3'), findsOneWidget);
    });

    testWidgets('derived series numbers render read-only per draft', (
      tester,
    ) async {
      // The screen seeds the derived base after the first frame; script
      // the series blocks projection to 3/5 → the first free number is 6.
      final ctx = await _buildFixture(seasons: [_season('s1', 1, title: 'S1')]);
      ctx.blockRepo.listBySeasonResult = Right([
        _blockView('b1', number: 3, seasonId: 's1'),
        _blockView('b2', number: 5, seasonId: 's2'),
      ]);
      await _pumpWizard(tester, ctx);
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      // Read-only headline numbers, derived from the projection (never a
      // field).
      expect(find.byKey(const Key('wizard-block-number-0')), findsOneWidget);
      expect(find.text('Block 6'), findsOneWidget);
    });

    testWidgets('applying a template expands four editable drafts', (
      tester,
    ) async {
      await onBlocks(tester);

      await tester.tap(find.byKey(const Key('wizard-apply-template-4x8')));
      await tester.pumpAndSettle();

      // The default draft + four template drafts (8 episodes each).
      for (var i = 0; i <= 4; i++) {
        expect(find.byKey(Key('wizard-block-draft-$i')), findsOneWidget);
      }
      // The drafts stay individually editable afterwards.
      await tester.enterText(
        find.byKey(const Key('wizard-draft-title-2')),
        'Nacht',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('wizard-draft-title-2')),
            )
            .controller!
            .text,
        'Nacht',
      );
    });

    testWidgets('draft removal keeps the wizard on the Blocks step', (
      tester,
    ) async {
      final ctx = await onBlocks(tester);

      await tester.tap(find.byKey(const Key('wizard-remove-draft-0')));
      await tester.pumpAndSettle();

      expect(ctx.state.blocks, isEmpty);
      // The inline noBlocks copy renders; Weiter is disabled.
      expect(find.byKey(const Key('wizard-blocks-error')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wizard-next')))
            .onPressed,
        isNull,
      );
      // Adding a draft re-enables the step.
      await tester.tap(find.byKey(const Key('wizard-add-draft')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wizard-next')))
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('wizard-blocks-error')), findsNothing);
    });

    testWidgets('a zero episode count disables Weiter with the inline copy', (
      tester,
    ) async {
      await onBlocks(tester);

      await tester.enterText(
        find.byKey(const Key('wizard-episode-count-0')),
        '0',
      );
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wizard-next')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('größer als 0'), findsOneWidget);
    });
  });

  group('Review + dispatch (tasks 3.2/4.3)', () {
    testWidgets('summary renders season + blocks + total episodes', (
      tester,
    ) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      // Two steps: Season → Blocks → Review (the seeded drafts ride along).
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wizard-review-summary')), findsOneWidget);
      expect(find.text('Block 1 · '), findsNothing); // read-only, no field
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('8 Episoden in 2 Blöcke'), findsOneWidget);
      expect(find.text('Schritt 3 von 3'), findsOneWidget);
    });

    testWidgets('confirm starts the dispatch and settles on completion', (
      tester,
    ) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      // Two steps: Season → Blocks → Review (the seeded drafts ride along).
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      // Hold the season create in flight (deterministic gate) so the
      // in-flight dispatching phase is observable (immediate fakes would
      // otherwise settle within one frame).
      final gate = Completer<Result<IdVersionResponse>>();
      ctx.seasonRepo.gate = gate;

      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 4);

      // The dispatch view rendered with per-command progress; the cancel
      // affordance is disabled (no app-bar back).
      expect(find.byKey(const Key('wizard-dispatch-view')), findsOneWidget);
      expect(find.text('Season wird erstellt…'), findsOneWidget);
      expect(
        find.text('0 / 11'),
        findsOneWidget,
      ); // The season create is still in flight.
      expect(find.byKey(const Key('wizard-back')), findsNothing);

      gate.complete(
        Right<ProblemError, IdVersionResponse>(
          IdVersionResponse(
            (b) => b
              ..id = 'n1'
              ..version = 1,
          ),
        ),
      );
      // Immediate fakes settle quickly; the completion screen renders.
      await pumpFrames(tester, n: 24);
      expect(find.byKey(const Key('wizard-completion')), findsOneWidget);
      expect(find.text('Season 1 angelegt'), findsOneWidget);
      expect(find.text('2 Blöcke · 8 Episoden'), findsOneWidget);
      expect(ctx.state.phase, SetupWizardPhase.completed);
    });

    testWidgets('back during dispatch is blocked (PopScope canPop false)', (
      tester,
    ) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      // Two steps: Season → Blocks → Review (the seeded drafts ride along).
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      // Hold the season create in flight (deterministic gate).
      final gate = Completer<Result<IdVersionResponse>>();
      ctx.seasonRepo.gate = gate;

      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 4);

      // The wizard route is not poppable while the sequence is in flight;
      // no discard dialog exists to confirm. (The PopScope widget is
      // generic — `PopScope<Object>` — so the finder must match by type
      // predicate, not runtimeType.)
      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScope.canPop, isFalse);

      gate.complete(
        Right<ProblemError, IdVersionResponse>(
          IdVersionResponse(
            (b) => b
              ..id = 'n1'
              ..version = 1,
          ),
        ),
      );
      await pumpFrames(tester, n: 24);
    });
  });

  group('Completion (task 4.4)', () {
    Future<_Fixture> pumpToCompletion(
      WidgetTester tester, {
      required bool aiConfigAvailable,
    }) async {
      final ctx = await _buildFixture(aiConfigAvailable: aiConfigAvailable);
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      // Two steps: Season → Blocks → Review (the seeded drafts ride along).
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 24);
      return ctx;
    }

    testWidgets('renders the AI-import CTA when a configuration exists', (
      tester,
    ) async {
      await pumpToCompletion(tester, aiConfigAvailable: true);

      expect(
        find.byKey(const Key('wizard-completion-import-cta')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wizard-completion-ai-info')), findsNothing);
    });

    testWidgets('renders the prerequisite info card without a configuration', (
      tester,
    ) async {
      await pumpToCompletion(tester, aiConfigAvailable: false);

      expect(
        find.byKey(const Key('wizard-completion-import-cta')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('wizard-completion-ai-info')),
        findsOneWidget,
      );
      expect(find.textContaining('KI-Konfiguration nötig'), findsOneWidget);
    });

    testWidgets('partial failure renders the created-so-far summary and '
        'retry', (tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      // Two steps: Season → Blocks → Review (the seeded drafts ride along).
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();

      // The FIRST block create fails with a 409.
      ctx.blockRepo.createResults.add(
        Left<ProblemError, IdVersionResponse>(_conflict),
      );
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 8);

      expect(
        find.byKey(const Key('wizard-completion-partial-title')),
        findsOneWidget,
      );
      expect(find.text('Teilweise erstellt'), findsOneWidget);
      // Created-so-far summary: the season (its episodes never started).
      expect(find.text('0 Blöcke · 0 Episoden'), findsOneWidget);
      // The localized problem-code copy (keyed on code, never detail).
      expect(find.textContaining('existiert bereits'), findsOneWidget);
      // In-session retry affordance.
      expect(find.byKey(const Key('wizard-retry')), findsOneWidget);

      // Retry completes the remaining commands (the fake now defaults to
      // Ok).
      await tester.tap(find.byKey(const Key('wizard-retry')));
      await pumpFrames(tester, n: 24);
      expect(ctx.state.phase, SetupWizardPhase.completed);
      expect(find.byKey(const Key('wizard-completion')), findsOneWidget);
    });
  });

  group('Goldens (task 6.1: steps + completion light/dark, validation, '
      'error)', () {
    /// Navigates to the review step with a 2×4 plan and dispatches
    /// (un-gated — immediate fakes settle).
    Future<void> toCompletion(
      WidgetTester tester,
      _Fixture ctx, {
      required ThemeData theme,
    }) async {
      await _pumpWizard(tester, ctx, theme: theme);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 24);
    }

    Future<void> goldenShot(
      WidgetTester tester,
      String name, {
      required bool dark,
    }) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/wizard_${name}_${dark ? 'dark' : 'light'}.png',
        ),
      );
    }

    for (final dark in [false, true]) {
      testWidgets('season step ($dark)', (tester) async {
        final ctx = await _buildFixture(
          seasons: [_season('s1', 1), _season('s2', 2)],
        );
        await _pumpWizard(
          tester,
          ctx,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
        await goldenShot(tester, 'season', dark: dark);
      });

      testWidgets('blocks step ($dark)', (tester) async {
        final ctx = await _buildFixture();
        await _pumpWizard(
          tester,
          ctx,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
        await tester.tap(find.byKey(const Key('wizard-next')));
        await tester.pumpAndSettle();
        await goldenShot(tester, 'blocks', dark: dark);
      });

      testWidgets('review step ($dark)', (tester) async {
        final ctx = await _buildFixture();
        await _pumpWizard(
          tester,
          ctx,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
        ctx.container
            .read(setupWizardControllerProvider.notifier)
            .removeBlockAt(0);
        ctx.container
            .read(setupWizardControllerProvider.notifier)
            .applyTemplate(count: 2, episodesPerBlock: 4);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('wizard-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('wizard-next')));
        await tester.pumpAndSettle();
        await goldenShot(tester, 'review', dark: dark);
      });

      testWidgets('completion with the AI CTA ($dark)', (tester) async {
        final ctx = await _buildFixture(aiConfigAvailable: true);
        await toCompletion(
          tester,
          ctx,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
        await goldenShot(tester, 'completion_cta', dark: dark);
      });

      testWidgets('completion with the prerequisite info card ($dark)', (
        tester,
      ) async {
        final ctx = await _buildFixture();
        await toCompletion(
          tester,
          ctx,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
        await goldenShot(tester, 'completion_ai_info', dark: dark);
      });
    }

    testWidgets('validation state (invalid number, light)', (tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      await tester.enterText(find.byKey(const Key('wizard-number-field')), '0');
      await tester.pump();
      await goldenShot(tester, 'season_invalid', dark: false);
    });

    testWidgets('dispatch in flight (light)', (tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      final gate = Completer<Result<IdVersionResponse>>();
      ctx.seasonRepo.gate = gate;
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 3);
      await goldenShot(tester, 'dispatch', dark: false);
      gate.complete(
        Right<ProblemError, IdVersionResponse>(
          IdVersionResponse(
            (b) => b
              ..id = 'n1'
              ..version = 1,
          ),
        ),
      );
      await pumpFrames(tester, n: 12);
    });

    testWidgets('partial failure state (light)', (tester) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .removeBlockAt(0);
      ctx.container
          .read(setupWizardControllerProvider.notifier)
          .applyTemplate(count: 2, episodesPerBlock: 4);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      ctx.blockRepo.createResults.add(
        Left<ProblemError, IdVersionResponse>(_conflict),
      );
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 8);
      await goldenShot(tester, 'partial_failure', dark: false);
      await pumpFrames(tester, n: 4);
    });
  });

  group('Progress indicator (task 4.5)', () {
    testWidgets('announces "Schritt x von 3" semantically per step', (
      tester,
    ) async {
      final ctx = await _buildFixture();
      await _pumpWizard(tester, ctx);

      expect(find.text('Schritt 1 von 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      expect(find.text('Schritt 2 von 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      expect(find.text('Schritt 3 von 3'), findsOneWidget);
      // The progress header leaves on the settled phases.
      await tester.tap(find.byKey(const Key('wizard-confirm')));
      await pumpFrames(tester, n: 24);
      expect(find.text('Schritt 3 von 3'), findsNothing);
    });
  });
}
