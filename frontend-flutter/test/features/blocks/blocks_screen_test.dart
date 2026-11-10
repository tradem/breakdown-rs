// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/blocks/create_block_sheet.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_screen.dart';
import 'package:frontend_flutter/features/shell/cast_tab_screen.dart';
import 'package:frontend_flutter/features/shell/production_overview_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';

import '../seasons/seasons_test_fakes.dart';
import '../ai_import/jobs_screen_test.dart' show FakeJobsRepository;

const _networkDown = ProblemError(code: 'transport.connectionError');
const _gone = ProblemError(code: 'season.not-found', status: 404);

/// The container's pinned clock: the create form's pickers open on this day,
/// so every assertion stays deterministic instead of reading the wall clock
/// (deterministic-tests rule, issue #833 review).
final DateTime _pinnedNow = DateTime(2026, 6, 15);

BlockView _block(
  String id, {
  int number = 1,
  String? startDate = '2026-01-01',
  String? endDate = '2026-01-31',
}) => BlockView(
  (b) => b
    ..id = id
    ..number = number
    ..seasonId = 'season-1'
    ..projectId = 'series-1'
    ..startDate = startDate
    ..endDate = endDate
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonView _season({String? title = 'Season One'}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = 'season-1'
    ..number = 1
    ..projectId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonMembershipDto _membership({
  bool hasRole = true,
  List<String>? capabilities,
}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = hasRole
    ..capabilities.replace(
      capabilities ??
          (hasRole ? const ['upload_continuity_photos'] : const <String>[]),
    ),
);

/// Repository fake: create is scriptable (the fetch path below is
/// holder-driven through the fetch-provider override, exactly like the
/// seasons screen tests).
class _FakeBlockRepository extends BlockRepository {
  _FakeBlockRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  int creates = 0;

  /// The last dispatched command payload (issue #833: the picked days must
  /// reach the wire shape unchanged).
  CreateBlockRequest? lastRequest;

  @override
  Future<Result<IdVersionResponse>> create(CreateBlockRequest request) {
    creates++;
    lastRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n$creates'
            ..version = 1,
        ),
      ),
    );
  }
}

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen).
Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() async {
    // The app bootstraps `intl` date symbols during composition
    // (lib/app.dart). Tests asserting locale-formatted dates and rendering
    // picked days do the same, so they exercise the production formatter
    // instead of its `MaterialLocalizations` fallback (issues #832/#833).
    await initializeDateFormatting('en');
  });

  late CacheDatabase db;
  late _FakeBlockRepository repo;
  late ValueNotifier<Result<List<BlockView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<BlockView> initialRows = const [],
    Result<List<BlockView>>? initialFetch,
    SeasonMembershipDto? membership,
    List<String>? membershipCapabilities,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
    holder = ValueNotifier<Result<List<BlockView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        blockRepositoryProvider.overrideWithValue(repo),
        // Pinned clock (deterministic-tests rule): the create form's date
        // pickers open on "today", so the dispatched day must not depend on
        // when the suite runs (issue #833 review).
        clockProvider.overrideWith((ref) => Clock.fixed(_pinnedNow)),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        blocksListFetchProvider('season-1').overrideWith((ref) async {
          final dao = BlockCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<BlockView>>(err),
            (rows) async {
              await dao.applySnapshotForSeason(
                'season-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<BlockView>>(rows);
            },
          );
        }),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            membership ?? _membership(capabilities: membershipCapabilities),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester, {SeasonView? season}) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: BlocksScreen(season: season ?? _season())),
      ),
    );
    // Settle the route / FAB entrance animations; the screen itself has no
    // indeterminate animation until a create is in flight.
    await tester.pumpAndSettle();
  }

  group('BlocksScreen states (6.1, semantic finders)', () {
    testWidgets('data: renders projected rows', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpScreen(tester);

      expect(find.text('Block 2'), findsOneWidget);
      expect(find.byKey(const Key('block-b1')), findsOneWidget);
    });

    // Issue #840: the AppBar title is composed by `seasonDisplayLabel`, so a
    // blank season title falls back to the number — the old inline
    // `title ?? blockSeasonNumber(...)` rendered an empty AppBar.
    testWidgets('AppBar falls back to the number on an empty season title', (
      tester,
    ) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpScreen(tester, season: _season(title: ''));
      expect(find.text('Season 1'), findsOneWidget);
    });

    testWidgets('AppBar falls back to the number on a blank season title', (
      tester,
    ) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpScreen(tester, season: _season(title: '   '));
      expect(find.text('Season 1'), findsOneWidget);
    });

    testWidgets('AppBar keeps the number-plus-name form for a titled season', (
      tester,
    ) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpScreen(tester, season: _season(title: 'Dreharbeiten'));
      expect(find.text('1 · Dreharbeiten'), findsOneWidget);
    });

    testWidgets('empty: plain-language state with create CTA', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-empty')), findsOneWidget);
      expect(find.byKey(const Key('blocks-empty-create')), findsOneWidget);
    });

    testWidgets('error: retry affordance, keyed on code', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
    });

    testWidgets('stale: retained rows stay visible with a banner', (
      tester,
    ) async {
      await setupContainer();
      // Seed last-good rows straight into Drift, then fail the fetch.
      await BlockCacheDao(db).applySnapshotForSeason('season-1', [
        _block('b1'),
      ], DateTime.utc(2026, 1, 1));
      holder.value = const Left(_networkDown);
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-stale-banner')), findsOneWidget);
      expect(find.byKey(const Key('block-b1')), findsOneWidget);
    });

    testWidgets('overlay: created row syncs, then reconciles', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('block-add-fab')));
      // Bounded settle for the sheet entrance (600ms fake time): the
      // overlay spinner created later would hang pumpAndSettle, and a
      // mid-animation tap would miss the button.
      await _pumpFrames(tester, n: 60);
      await tester.enterText(find.byKey(const Key('create-block-number')), '4');
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      // Optimistic overlay with progress affordance (no frozen frames).
      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);

      // Projection catches up → drive the parked bounded pass (manual
      // scheduler + frames, seasons pattern): the create-time pass parked
      // on a backoff tick, so a bare `refresh()` would join it and wait
      // forever without `advanceAll`.
      holder.value = Right([_block('n1', number: 4)]);
      for (var i = 0; i < kMaxReconcileAttempts * 4; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 2);
        if (find.byKey(const Key('block-n1')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const Key('block-n1')), findsOneWidget);
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
    });

    testWidgets('404: narrative with back affordance, no stale rows', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_gone));
      await pumpScreen(tester);

      expect(find.byKey(const Key('blocks-not-found')), findsOneWidget);
      expect(find.textContaining('season.not-found'), findsOneWidget);
      expect(find.byKey(const Key('blocks-not-found-back')), findsOneWidget);
    });
  });

  group('create-block form date pickers (issue #833)', () {
    /// Opens the create form and settles its entrance animation with bounded
    /// frames (the sheet/dialog route, never the overlay spinner).
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('block-add-fab')));
      await _pumpFrames(tester, n: 60);
    }

    /// Accepts the day the picker opens on (its initial date) — no calendar
    /// navigation, so the test does not hunt for a specific day cell.
    Future<void> acceptInitialDay(WidgetTester tester, Key pickKey) async {
      await tester.tap(find.byKey(pickKey));
      // The date-picker dialog is a static surface (no indeterminate
      // progress indicator), so settling here is safe and deterministic.
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('OK'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the days are picker controls, never typed format strings', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);
      await openForm(tester);

      // The free-text `YYYY-MM-DD` fields are gone; both days start empty
      // and the empty state is not an error.
      expect(find.byKey(const Key('create-block-start')), findsNothing);
      expect(find.byKey(const Key('create-block-end')), findsNothing);
      expect(find.byKey(const Key('create-block-start-pick')), findsOneWidget);
      expect(find.byKey(const Key('create-block-end-pick')), findsOneWidget);
      expect(find.text('Pick date'), findsNWidgets(2));
      expect(find.text('No date'), findsNWidgets(2));
      // No clear affordance until a day is set.
      expect(find.byKey(const Key('create-block-start-clear')), findsNothing);
      expect(find.byKey(const Key('create-block-end-clear')), findsNothing);
    });

    testWidgets('picked days dispatch as Date(y, m, d)', (tester) async {
      await setupContainer();
      await pumpScreen(tester);
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('create-block-number')), '4');

      await acceptInitialDay(tester, const Key('create-block-start-pick'));
      await acceptInitialDay(tester, const Key('create-block-end-pick'));
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      // The pickers open on the container's pinned clock day, and the wire
      // value carries no time component.
      final request = repo.lastRequest;
      expect(request, isNotNull);
      expect(request!.number, 4);
      expect(request.projectId, 'series-1');
      expect(request.seasonId, 'season-1');
      expect(request.startDate, Date(2026, 6, 15));
      expect(request.endDate, Date(2026, 6, 15));
      expect(repo.creates, 1);
    });

    testWidgets('a picked day can be cleared again', (tester) async {
      await setupContainer();
      await pumpScreen(tester);
      await openForm(tester);

      await acceptInitialDay(tester, const Key('create-block-start-pick'));
      // The picked day renders as text (locale-formatted), the other stays
      // empty — the value is read-only, never an input field.
      expect(find.text('No date'), findsOneWidget);
      expect(find.byKey(const Key('create-block-start-clear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-block-start-clear')));
      await _pumpFrames(tester);

      expect(find.text('No date'), findsNWidgets(2));
      expect(find.byKey(const Key('create-block-start-clear')), findsNothing);
    });

    testWidgets('each pick and clear control names its bound for screen '
        'readers', (tester) async {
      // Disposed inside the body: the framework verifies semantics handles
      // before any `addTearDown` callback runs.
      final semantics = tester.ensureSemantics();
      try {
        await setupContainer();
        await pumpScreen(tester);
        await openForm(tester);

        // Both rows render the same visible label, so the accessible name is
        // the only thing telling the two controls apart (issue #833 review).
        expect(find.text('Pick date'), findsNWidgets(2));
        expect(find.bySemanticsLabel('Pick start date'), findsOneWidget);
        expect(find.bySemanticsLabel('Pick end date'), findsOneWidget);
        expect(find.bySemanticsLabel('Clear start date'), findsNothing);

        await acceptInitialDay(tester, const Key('create-block-start-pick'));
        await acceptInitialDay(tester, const Key('create-block-end-pick'));

        expect(find.bySemanticsLabel('Clear start date'), findsOneWidget);
        expect(find.bySemanticsLabel('Clear end date'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('a day outside the old 2000–2100 window stays selectable', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('create-block-number')), '7');

      await tester.tap(find.byKey(const Key('create-block-start-pick')));
      await tester.pumpAndSettle();
      // Input mode: the pickers' bounds follow the wire contract (ISO-8601
      // four-digit years), not an unspecified planning horizon (issue #833
      // review).
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        ),
        '01/15/1995',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('OK'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jan 15, 1995'), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      expect(repo.lastRequest!.startDate, Date(1995, 1, 15));
      expect(repo.lastRequest!.endDate, isNull);
    });

    testWidgets('end before start is refused with a field message, no '
        'dispatch', (tester) async {
      await setupContainer();
      await pumpScreen(tester);
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('create-block-number')), '2');

      // End = today, then start = day 3 of the following month: an inverted
      // span built through the pickers only (a calendar cell is the only way
      // to move the selection, and day 3 always exists).
      await acceptInitialDay(tester, const Key('create-block-end-pick'));
      await tester.tap(find.byKey(const Key('create-block-start-pick')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('3'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('OK'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('create-block-date-order-error')),
        findsOneWidget,
      );
      expect(
        find.text('The end date is before the start date.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('create-block-submit')));
      await _pumpFrames(tester);

      expect(repo.creates, 0);
      expect(repo.lastRequest, isNull);
      expect(
        find.byKey(const Key('create-block-date-order-error')),
        findsOneWidget,
      );
    });

    testWidgets('the pure range guard matches the backend model', (
      tester,
    ) async {
      // Both bounds optional: no guard case, a legal span, equal bounds.
      expect(blockDateOrderValid(null, null), isTrue);
      expect(blockDateOrderValid(DateTime(2026, 11, 4), null), isTrue);
      expect(blockDateOrderValid(null, DateTime(2026, 11, 4)), isTrue);
      expect(
        blockDateOrderValid(DateTime(2026, 11, 4), DateTime(2026, 11, 4)),
        isTrue,
      );
      expect(
        blockDateOrderValid(DateTime(2026, 11, 5), DateTime(2026, 11, 4)),
        isFalse,
      );
      // The wire value drops the time component (never a timezone shift).
      expect(blockWireDate(null), isNull);
      expect(blockWireDate(DateTime(2026, 11, 4, 23, 59)), Date(2026, 11, 4));
    });
  });

  group('membership chip (6.3, D6 display-only)', () {
    testWidgets('renders the localized role statement, never the capability '
        'wire names', (tester) async {
      await setupContainer(initialRows: [_block('b1')]);
      await pumpScreen(tester);

      expect(find.byKey(const Key('membership-chip')), findsOneWidget);
      expect(find.text('Costume role'), findsOneWidget);
      // Issue #832: `capabilities` are protocol identifiers
      // (`upload_continuity_photos`, …) and must never reach the user.
      expect(find.textContaining('upload_continuity_photos'), findsNothing);
    });

    testWidgets('renders the same role statement when the vector is empty', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_block('b1')],
        membershipCapabilities: const <String>[],
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('membership-chip')), findsOneWidget);
      expect(find.text('Costume role'), findsOneWidget);
    });

    testWidgets('renders the explicit no-role chip otherwise', (tester) async {
      await setupContainer(
        initialRows: [_block('b1')],
        membership: _membership(hasRole: false),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('membership-chip-none')), findsOneWidget);
      expect(find.text('No role in this season'), findsOneWidget);
    });
  });

  group('hierarchy navigation spine (5.1, D1)', () {
    /// Container serving the seasons list AND the pushed child screens:
    /// holder-driven seasons projection plus trivial child fetches.
    Future<void> setupNavContainer() async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final seasonRepo = FakeSeasonRepository(
        BreakdownApi(),
        SeasonCacheDao(db),
      );
      repo = _FakeBlockRepository(BreakdownApi(), BlockCacheDao(db));
      final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season()]),
      );
      scheduler = ManualReconciliationScheduler();
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(seasonRepo),
          blockRepositoryProvider.overrideWithValue(repo),
          aiImportRepositoryProvider.overrideWithValue(
            FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db)),
          ),
          aiImportJobsFetchProvider.overrideWith(
            (ref) async => Right(<AiImportJob>[]),
          ),
          costumeCategoryRepositoryProvider.overrideWithValue(
            CostumeCategoryRepository(
              BreakdownApi(),
              CostumeCategoryCacheDao(db),
            ),
          ),
          reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
          seasonsListFetchProvider.overrideWith((ref) async {
            final r = ref.watch(seasonRepositoryProvider);
            return r.fetchAndCacheList(() async => seasonsHolder.value);
          }),
          blocksListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          membershipFetchProvider('season-1').overrideWith(
            (ref) async =>
                Right<ProblemError, SeasonMembershipDto>(_membership()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
    }

    /// The production overview (issue #610: the re-homed Planen
    /// destination) for the container's active season.
    Future<void> pumpProduction(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ProductionOverviewScreen(season: _season())),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The Cast view (issue #610: the piece surface and the category
    /// vocabulary moved here from the dissolved Kleidung/Mehr
    /// destinations).
    Future<void> pumpCast(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastTabScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('production overview pushes BlocksScreen; back pops', (
      tester,
    ) async {
      await setupNavContainer();
      await pumpProduction(tester);
      expect(find.byKey(const Key('production-blocks-entry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('production-blocks-entry')));
      await _pumpFrames(tester, n: 30);
      expect(find.byType(BlocksScreen), findsOneWidget);

      await tester.pageBack();
      // Pop transition must finish: the dismissed route stays findable
      // until it does (both screens are static here, so settling is safe).
      await tester.pumpAndSettle();
      expect(find.byType(ProductionOverviewScreen), findsOneWidget);
      expect(find.byType(BlocksScreen), findsNothing);
    });

    testWidgets('the Cast view categories action pushes '
        'CostumeCategoriesScreen (issue #610: categories never with '
        'settings)', (tester) async {
      await setupNavContainer();
      // The active season is set the way the shell does: from the acted-on
      // DTO (the categories action is gated on the active season).
      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(_season());
      await pumpCast(tester);

      await tester.tap(find.byKey(const Key('cast-categories-action')));
      await _pumpFrames(tester, n: 30);
      expect(find.byType(CostumeCategoriesScreen), findsOneWidget);
    });
  });

  group('membership strict-parse error state (6.3)', () {
    testWidgets(
      'unknown capability surfaces the error chip, never a guessed policy',
      (tester) async {
        await setupContainer(
          initialRows: [_block('b1')],
          membershipCapabilities: const ['future_cap'],
        );
        await pumpScreen(tester);

        expect(find.byKey(const Key('membership-chip-error')), findsOneWidget);
        expect(
          find.textContaining('authz.membership.capability_unknown'),
          findsOneWidget,
        );
      },
    );
  });

  group('block tile time span (issue #832)', () {
    testWidgets('no dates: no subtitle line at all (no dash row)', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_block('b1', startDate: null, endDate: null)],
      );
      await pumpScreen(tester);

      final tile = tester.widget<ListTile>(find.byKey(const Key('block-b1')));
      expect(tile.subtitle, isNull);
      expect(find.byKey(const Key('block-span-b1')), findsNothing);
      expect(find.textContaining('–'), findsNothing);
    });

    testWidgets('start only: one honest single-ended phrase', (tester) async {
      await setupContainer(
        initialRows: [_block('b1', startDate: '2026-11-04', endDate: null)],
      );
      await pumpScreen(tester);

      expect(find.text('From Nov 4, 2026'), findsOneWidget);
      expect(find.textContaining('2026-11-04'), findsNothing);
    });

    testWidgets('end only: one honest single-ended phrase', (tester) async {
      await setupContainer(
        initialRows: [_block('b1', startDate: null, endDate: '2026-12-18')],
      );
      await pumpScreen(tester);

      expect(find.text('Until Dec 18, 2026'), findsOneWidget);
      expect(find.textContaining('2026-12-18'), findsNothing);
    });

    testWidgets('both set: locale-formatted range, never raw ISO', (
      tester,
    ) async {
      await setupContainer(initialRows: [_block('b1')]);
      await pumpScreen(tester);

      expect(find.text('Jan 1, 2026 – Jan 31, 2026'), findsOneWidget);
      expect(find.textContaining('2026-01-01'), findsNothing);
    });
  });

  group('BlocksScreen goldens (6.2, data state)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      TargetPlatform? platform,
    }) async {
      // Reset via finally (not addTearDown): the framework verifies debug
      // variables are unset before tearDowns run.
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
              home: BlocksScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(BlocksScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(initialRows: [_block('b1', number: 2)]);
      await pumpGolden(
        tester,
        golden: 'blocks_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });

  group('create-block form goldens (issue #833)', () {
    /// Renders the OPEN create-block form through the same platform split the
    /// production entry uses (`showCreateBlockSheet`): bottom sheet on
    /// Android, centered dialog on macOS.
    Future<void> pumpFormGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      required TargetPlatform platform,
    }) async {
      try {
        debugDefaultTargetPlatformOverride = platform;
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
              home: BlocksScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('block-add-fab')));
        // Bounded frames for the sheet/dialog route entrance only, so the
        // capture never lands mid-animation.
        await _pumpFrames(tester, n: 60);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden sheet light android', (tester) async {
      await setupContainer();
      await pumpFormGolden(
        tester,
        golden: 'blocks_create_sheet_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden sheet dark android', (tester) async {
      await setupContainer();
      await pumpFormGolden(
        tester,
        golden: 'blocks_create_sheet_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dialog light macos', (tester) async {
      await setupContainer();
      await pumpFormGolden(
        tester,
        golden: 'blocks_create_dialog_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dialog dark macos', (tester) async {
      await setupContainer();
      await pumpFormGolden(
        tester,
        golden: 'blocks_create_dialog_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
