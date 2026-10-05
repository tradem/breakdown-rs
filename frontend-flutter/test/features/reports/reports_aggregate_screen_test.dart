// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Widget tests for the aggregated Soll-Ist report screens (issue #571):
// server-derived finality + day counts rendered verbatim, flag chips,
// zero-day empty report, scope-kind routing, PDF fetch → ready, and the
// locally denied membership state asserting zero requests.

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/reports/report_share.dart';
import 'package:frontend_flutter/features/reports/reports_aggregate_screen.dart';
import 'package:frontend_flutter/features/reports/reports_aggregate_state.dart';
import 'package:frontend_flutter/features/reports/reports_controller.dart';
import 'package:frontend_flutter/features/reports/widgets/reports_aggregate_entry.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';

import '../seasons/seasons_test_fakes.dart';

const _seasonScope = ReportsAggregateScope(
  kind: ReportAggregateScopeKind.season,
  id: 'season-1',
  seasonId: 'season-1',
  label: 'Staffel 1',
);

const _episodeScope = ReportsAggregateScope(
  kind: ReportAggregateScopeKind.episode,
  id: 'episode-1',
  seasonId: 'season-1',
  label: 'Episode 1',
);

SeasonMembershipDto _membership({required bool active}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = active
    ..capabilities.replace(const <String>[]),
);

AggregateSollIstDiffRow _row(
  String sceneId, {
  String? dayLabel,
  bool moved = false,
  bool missing = false,
  bool skipped = false,
  bool reshot = false,
}) => AggregateSollIstDiffRow(
  (b) => b
    ..sceneId = sceneId
    ..shootingDayId = 'day-1'
    ..shootingDayLabel = dayLabel
    ..missing = missing
    ..moved = moved
    ..reshotCandidate = reshot
    ..skipped = skipped,
);

AggregateSollIstReport _report({
  bool isFinal = false,
  int total = 2,
  int wrapped = 0,
  List<AggregateSollIstDiffRow>? rows,
}) => AggregateSollIstReport(
  (b) => b
    ..isFinal = isFinal
    ..totalShootingDays = total
    ..wrappedShootingDays = wrapped
    ..rows.replace(
      rows ??
          [
            _row('s-x', dayLabel: 'Tageins', moved: true),
            _row('s-y', dayLabel: 'Tagzwei', missing: true, reshot: true),
          ],
    ),
);

/// Repository fake: aggregate JSON fetches and aggregate PDF fetches are
/// scriptable; every call is counted so AUTHZ-GATE tests can assert zero
/// requests.
class _FakeAggregateRepository extends SceneShootRepository {
  _FakeAggregateRepository(super.api, super.cache);

  Result<AggregateSollIstReport>? nextSeason;
  Result<AggregateSollIstReport>? nextEpisode;
  Result<File>? nextPdf;

  int seasonCalls = 0;
  int episodeCalls = 0;
  int seasonPdfCalls = 0;
  int episodePdfCalls = 0;

  @override
  Future<Result<AggregateSollIstReport>> fetchSeasonSollIstReport(
    String seasonId,
  ) async {
    seasonCalls++;
    return nextSeason ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<AggregateSollIstReport>> fetchEpisodeSollIstReport(
    String episodeId,
  ) async {
    episodeCalls++;
    return nextEpisode ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> seasonSollIstReportPdf(
    String seasonId, {
    required Directory tempDir,
    required String scopeLabel,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    seasonPdfCalls++;
    return nextPdf ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> episodeSollIstReportPdf(
    String episodeId, {
    required Directory tempDir,
    required String scopeLabel,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    episodePdfCalls++;
    return nextPdf ?? const Left(ProblemError(code: 'transport.network'));
  }
}

class _FakeShare implements ReportShareService {
  File? lastShared;
  String? lastName;

  @override
  Future<Result<void>> sharePdf(File file, {required String fileName}) async {
    lastShared = file;
    lastName = fileName;
    return const Right<ProblemError, void>(null);
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

enum MembershipMode { allowed, denied }

void main() {
  late CacheDatabase db;
  late _FakeAggregateRepository repo;
  late _FakeShare share;
  late Directory tempDir;
  late ProviderContainer container;

  Future<void> setupContainer({
    MembershipMode membership = MembershipMode.allowed,
    Result<AggregateSollIstReport>? season,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeAggregateRepository(BreakdownApi(), SceneShootCacheDao(db));
    repo.nextSeason = season ?? Right(_report());
    repo.nextEpisode = season ?? Right(_report());
    share = _FakeShare();
    tempDir = Directory.systemTemp.createTempSync('aggregate-screen-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        reportsTempDirProvider.overrideWith((ref) async => tempDir),
        reportShareServiceProvider.overrideWithValue(share),
        membershipFetchProvider('season-1').overrideWith((ref) async {
          switch (membership) {
            case MembershipMode.allowed:
              return Right(_membership(active: true));
            case MembershipMode.denied:
              return Right(_membership(active: false));
          }
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    ReportsAggregateScope scope = _seasonScope,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          locale: const Locale('de'),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ReportsAggregateScreen(scope: scope),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  testWidgets('load: rows + flag chips + provisional day progress', (
    tester,
  ) async {
    await setupContainer();
    await pumpScreen(tester);

    expect(find.byKey(const Key('soll-ist-aggregate-screen')), findsOneWidget);
    // Server verdict + counts rendered verbatim (2 days, 0 wrapped).
    expect(
      find.byKey(const Key('aggregate-soll-ist-provisional')),
      findsOneWidget,
    );
    expect(
      find.text('Vorläufig – 0 von 2 Drehtagen abgeschlossen.'),
      findsOneWidget,
    );
    // Flag chips verbatim from the report DTO.
    expect(find.byKey(const Key('aggregate-flag-moved')), findsOneWidget);
    expect(find.byKey(const Key('aggregate-flag-missing')), findsOneWidget);
    expect(find.byKey(const Key('aggregate-flag-reshot')), findsOneWidget);
    // Day label from the server rows.
    expect(find.text('Tageins · Szenen-Nr: s-x'), findsOneWidget);
    // JSON fetch: the season route for the season scope.
    expect(repo.seasonCalls, 1);
    expect(repo.episodeCalls, 0);
  });

  testWidgets('final: all days wrapped ⇒ final banner', (tester) async {
    await setupContainer(
      season: Right(_report(isFinal: true, total: 2, wrapped: 2)),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('aggregate-soll-ist-final')), findsOneWidget);
    expect(
      find.byKey(const Key('aggregate-soll-ist-provisional')),
      findsNothing,
    );
  });

  testWidgets('empty: zero-day scope renders the empty copy', (tester) async {
    await setupContainer(
      season: Right(_report(total: 0, wrapped: 0, rows: [])),
    );
    await pumpScreen(tester);
    expect(find.text('Keine Szenen in diesem Bericht.'), findsOneWidget);
    // Still provisional: an empty scope is NEVER vacuously final (issue
    // #571 decision 2) and the client only renders the server's verdict.
    expect(
      find.byKey(const Key('aggregate-soll-ist-provisional')),
      findsOneWidget,
    );
  });

  testWidgets('episode scope uses the episode route', (tester) async {
    await setupContainer();
    await pumpScreen(tester, scope: _episodeScope);
    expect(repo.episodeCalls, 1);
    expect(repo.seasonCalls, 0);
  });

  testWidgets('denied membership: banner with ZERO report requests', (
    tester,
  ) async {
    await setupContainer(membership: MembershipMode.denied);
    await pumpScreen(tester);
    expect(find.byKey(const Key('aggregate-report-denied')), findsOneWidget);
    expect(find.byKey(const Key('aggregate-flag-moved')), findsNothing);
    expect(repo.seasonCalls, 0);
    expect(repo.episodeCalls, 0);
  });

  testWidgets('fetch error state surfaces the code-keyed copy', (tester) async {
    await setupContainer(
      season: const Left(ProblemError(code: 'transport.network')),
    );
    await pumpScreen(tester);
    expect(
      find.byKey(const Key('aggregate-report-error-text')),
      findsOneWidget,
    );
  });

  testWidgets('pdf fetch: ready card exposes preview + share', (tester) async {
    await setupContainer();
    final staged = File('${tempDir.path}/aggregate.pdf');
    // SYNC write: awaited dart:io deadlocks in the testWidgets FakeAsync
    // zone (same trap the day-scoped tests document).
    staged.writeAsBytesSync(const [1, 2, 3]);
    repo.nextPdf = Right(staged);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('aggregate-pdf-fetch')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('aggregate-pdf-preview')), findsOneWidget);
    expect(find.byKey(const Key('aggregate-pdf-share')), findsOneWidget);
    expect(repo.seasonPdfCalls, 1);
  });

  testWidgets('season entry action: labelled app-bar widget with key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Staffel 1'),
            actions: [
              SizedBox(
                width: 500,
                child: ReportsAggregateAppBarAction(
                  baseKey: 'reportsAggregateOpen',
                  roomForLabel: true,
                  onOpen: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byKey(const Key('reportsAggregateOpen')), findsOneWidget);
    // Visible label — the entry cannot regress to icon-only.
    expect(find.text('Soll-Ist gesamt'), findsOneWidget);
  });

  group('ReportsAggregateScreen goldens ({light,dark} x {android,macOS})', () {
    // 12 goldens over 3 semantics states × 4 combos (issue #571): rows +
    // provisional progress, the all-wrapped final banner, and the 403
    // denial narrative (zero requests). Semantic pre-conditions checked
    // BEFORE the pixel comparison so a wrong-but-stable render can never
    // be blessed as a golden.
    Future<void> golden(
      WidgetTester tester,
      String name, {
      required Brightness brightness,
      required TargetPlatform? platform,
      MembershipMode membership = MembershipMode.allowed,
      bool isFinal = false,
      void Function()? assertState,
    }) async {
      try {
        // The platform override drives the {android,macOS} half of the
        // grid, brightness drives the {light,dark} half FORWARD into the
        // renderer so a dark golden is a genuinely dark render.
        debugDefaultTargetPlatformOverride = platform;
        await setupContainer(
          membership: membership,
          season: Right(
            _report(isFinal: isFinal, total: 2, wrapped: isFinal ? 2 : 0),
          ),
        );
        await pumpScreen(tester, brightness: brightness);
        expect(
          find.byKey(const Key('soll-ist-aggregate-screen')),
          findsOneWidget,
        );
        assertState?.call();
        await expectLater(
          find.byType(ReportsAggregateScreen),
          matchesGoldenFile('goldens/reports_aggregate_$name.png'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    // Brightness/platform grid runner (repo golden convention).
    Future<void> grid(
      WidgetTester tester,
      String prefix,
      Future<void> Function(String name, Brightness, TargetPlatform?) run,
    ) async {
      await run(
        '${prefix}_light_android',
        Brightness.light,
        TargetPlatform.android,
      );
      await run(
        '${prefix}_dark_android',
        Brightness.dark,
        TargetPlatform.android,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await run(
        '${prefix}_light_macos',
        Brightness.light,
        TargetPlatform.macOS,
      );
      await run('${prefix}_dark_macos', Brightness.dark, TargetPlatform.macOS);
      debugDefaultTargetPlatformOverride = null;
    }

    void assertLoaded() {
      expect(
        find.byKey(const Key('aggregate-soll-ist-provisional')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('aggregate-flag-moved')), findsOneWidget);
    }

    testWidgets('loaded × 4', (tester) async {
      await grid(tester, 'loaded', (n, b, p) async {
        await golden(
          tester,
          n,
          brightness: b,
          platform: p,
          assertState: assertLoaded,
        );
      });
    });

    testWidgets('final × 4', (tester) async {
      void assertFinal() {
        expect(
          find.byKey(const Key('aggregate-soll-ist-final')),
          findsOneWidget,
        );
      }

      await grid(tester, 'final', (n, b, p) async {
        await golden(
          tester,
          n,
          brightness: b,
          platform: p,
          isFinal: true,
          assertState: assertFinal,
        );
      });
    });

    testWidgets('denied × 4', (tester) async {
      await grid(tester, 'denied', (n, b, p) async {
        await golden(
          tester,
          n,
          brightness: b,
          platform: p,
          membership: MembershipMode.denied,
          assertState: () => expect(
            find.byKey(const Key('aggregate-report-denied')),
            findsOneWidget,
          ),
        );
      });
    });
  });
}
