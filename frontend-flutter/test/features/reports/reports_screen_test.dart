// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Widget tests + goldens (`flutter-reports` 2.4): idle/fetching/error/ready
// card states, flag chips, finality, denial narrative, strict-reject error
// state, and ALL locally denied membership states — `AsyncLoading`,
// `AsyncError`, and unknown capability string — each asserting zero report
// requests. Goldens across {light,dark} × {android,macOS} (macOS via
// `debugDefaultTargetPlatformOverride` on Linux — the repo's golden
// convention, no Apple hardware needed). Semantic finders throughout
// (never `find.byType` alone for layout).

import 'dart:async';
import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/report_models.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/reports/report_share.dart';
import 'package:frontend_flutter/features/reports/reports_controller.dart';
import 'package:frontend_flutter/features/reports/reports_screen.dart';
import 'package:frontend_flutter/features/reports/reports_state.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';

import '../seasons/seasons_test_fakes.dart';

const _scope = ReportDayScope(dayId: 'day-1', seasonId: 'season-1');

ShootingDayView _day() => ShootingDayView(
  (b) => b
    ..id = 'day-1'
    ..episodeId = 'episode-1'
    ..orderKey = 'a0'
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..label = 'Day 1'
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = 1,
);

SeasonMembershipDto _membership({
  required bool active,
  List<String> caps = const [],
}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = active
    ..capabilities.replace(caps),
);

SollIstDiffRow _row(
  String sceneId, {
  int? sceneNumber,
  bool moved = false,
  bool missing = false,
  bool skipped = false,
  bool reshot = false,
}) => SollIstDiffRow(
  (b) => b
    ..sceneId = sceneId
    ..sceneNumber = sceneNumber
    ..missing = missing
    ..moved = moved
    ..reshotCandidate = reshot
    ..skipped = skipped,
);

SollIstReport _report({bool isFinal = true}) => SollIstReport(
  (b) => b
    ..isFinal = isFinal
    ..rows.replace([
      _row('s-moved', sceneNumber: 1, moved: true),
      _row('s-missing', sceneNumber: 2, missing: true),
      _row('s-skipped', sceneNumber: 3, skipped: true),
      _row('s-reshot', sceneNumber: 4, reshot: true),
    ]),
);

DispoRow _dispo(String sceneId) => DispoRow(
  (b) => b
    ..sceneId = sceneId
    ..plannedOrder = 'a0',
);

ShootDayRow _shootRow(String sceneId) => ShootDayRow(
  (b) => b
    ..sceneId = sceneId
    ..status = SceneShootStatus.shot
    ..continuityPhotoIds.replace(const <String>[])
    ..notes.replace(const <SerializedNote>[]),
);

/// Repository fake: JSON report fetches and PDF fetches are scriptable;
/// every call is counted so AUTHZ-GATE tests can assert zero requests.
class _FakeReportsRepository extends SceneShootRepository {
  _FakeReportsRepository(super.api, super.cache);

  Result<SollIstReport>? nextSollIst;
  Result<List<DispoRow>>? nextDispo;
  Result<List<ShootDayRow>>? nextShootDay;
  Result<File>? nextPdf;
  Completer<Result<File>>? pdfGate;

  int sollIstCalls = 0;
  int dispoCalls = 0;
  int shootDayCalls = 0;
  int dispoPdfCalls = 0;
  int shootDayPdfCalls = 0;
  int plannedPdfCalls = 0;

  int get pdfCalls => dispoPdfCalls + shootDayPdfCalls + plannedPdfCalls;
  int get jsonCalls => sollIstCalls + dispoCalls + shootDayCalls;

  @override
  Future<Result<SollIstReport>> fetchSollIstReport(String id) async {
    sollIstCalls++;
    return nextSollIst ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<List<DispoRow>>> fetchDispoReport(String id) async {
    dispoCalls++;
    return nextDispo ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<List<ShootDayRow>>> fetchShootDayReport(String id) async {
    shootDayCalls++;
    return nextShootDay ?? const Left(ProblemError(code: 'transport.network'));
  }

  Future<Result<File>> _pdf() async {
    final gate = pdfGate;
    if (gate != null) return gate.future;
    return nextPdf ?? const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> dispoReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    dispoPdfCalls++;
    return _pdf();
  }

  @override
  Future<Result<File>> shootDayReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    shootDayPdfCalls++;
    return _pdf();
  }

  @override
  Future<Result<File>> plannedVsActualReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    plannedPdfCalls++;
    return _pdf();
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

/// Membership modes for the AUTHZ-GATE matrix (2.3/2.4): allowed, resolved
/// denial (empty caps), unknown capability string, loading
/// (never-resolving fetch), and fetch error.
enum MembershipMode { allowed, denied, unknownCap, loading, error }

void main() {
  late CacheDatabase db;
  late _FakeReportsRepository repo;
  late _FakeShare share;
  late Directory tempDir;
  late ValueNotifier<Result<SeasonMembershipDto>> membershipHolder;
  late ProviderContainer container;

  Future<void> setupContainer({
    MembershipMode membership = MembershipMode.allowed,
    Result<SollIstReport>? sollIst,
    Result<List<DispoRow>>? dispo,
    Result<List<ShootDayRow>>? shootDay,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeReportsRepository(BreakdownApi(), SceneShootCacheDao(db));
    repo.nextSollIst = sollIst ?? Right(_report());
    repo.nextDispo = dispo ?? Right(List.generate(12, (i) => _dispo('s-$i')));
    repo.nextShootDay =
        shootDay ?? Right(List.generate(10, (i) => _shootRow('s-$i')));
    share = _FakeShare();
    // Sync FS ops only: awaited dart:io deadlocks in the testWidgets
    // FakeAsync zone (even across pumps before the first pumpWidget).
    tempDir = Directory.systemTemp.createTempSync('reports-screen-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    membershipHolder = ValueNotifier<Result<SeasonMembershipDto>>(
      Right(
        _membership(active: true, caps: const ['upload_continuity_photos']),
      ),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        reportsTempDirProvider.overrideWith((ref) async => tempDir),
        reportShareServiceProvider.overrideWithValue(share),
        if (membership == MembershipMode.loading)
          membershipFetchProvider('season-1').overrideWith(
            (ref) => Completer<Result<SeasonMembershipDto>>().future,
          )
        else
          membershipFetchProvider('season-1').overrideWith((ref) async {
            switch (membership) {
              case MembershipMode.allowed:
                return membershipHolder.value;
              case MembershipMode.denied:
                return Right(_membership(active: false));
              case MembershipMode.unknownCap:
                return Right(
                  _membership(active: false, caps: const ['future_cap_x']),
                );
              case MembershipMode.error:
                return const Left(ProblemError(code: 'transport.network'));
              case MembershipMode.loading:
                return membershipHolder.value;
            }
          }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    TargetPlatform? platform,
  }) async {
    if (platform != null) {
      debugDefaultTargetPlatformOverride = platform;
    }
    tester.view.physicalSize = const Size(800, 1400);
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
          home: ReportsScreen(day: _day(), seasonId: 'season-1'),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  group('ReportsScreen states (2.1, semantic finders)', () {
    testWidgets('idle: rows, flag chips, finality, counts, fetch buttons', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);

      expect(find.byKey(const Key('soll-ist-report-screen')), findsOneWidget);
      // Planned/actual counts render as bare numbers (Gherkin parses ints).
      expect(find.byKey(const Key('soll-ist-planned')), findsOneWidget);
      expect(find.text('12', findRichText: true), findsWidgets);
      expect(find.text('10', findRichText: true), findsWidgets);
      // Every flag chip renders verbatim from the read DTO.
      expect(find.byKey(const Key('soll-ist-flag-moved')), findsOneWidget);
      expect(find.byKey(const Key('soll-ist-flag-missing')), findsOneWidget);
      expect(find.byKey(const Key('soll-ist-flag-skipped')), findsOneWidget);
      expect(find.byKey(const Key('soll-ist-flag-reshot')), findsOneWidget);
      expect(find.text('moved'), findsOneWidget);
      // Finality banner from the report DTO.
      expect(find.byKey(const Key('soll-ist-final')), findsOneWidget);
      // All three PDF cards idle with user-initiated fetch buttons.
      expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
      expect(
        find.byKey(const Key('report-pdf-fetch-shootDay')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('report-pdf-fetch-plannedVsActual')),
        findsOneWidget,
      );
      expect(repo.jsonCalls, 3);
    });

    testWidgets('fetching: progress shows; cancel returns to idle', (
      tester,
    ) async {
      await setupContainer();
      repo.pdfGate = Completer<Result<File>>();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
      await _pumpFrames(tester, n: 3);
      expect(
        find.byKey(const Key('report-pdf-progress-dispo')),
        findsOneWidget,
      );
      expect(repo.dispoPdfCalls, 1);

      await tester.tap(find.byKey(const Key('report-pdf-cancel-dispo')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
      repo.pdfGate!.complete(
        const Left(ProblemError(code: 'transport.network')),
      );
      await _pumpFrames(tester);
      // Late completion after cancel never resurrects an error card.
      expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
    });

    testWidgets(
      'superseded fetch: late completion of a cancelled request never '
      'resets the newer card',
      (tester) async {
        await setupContainer();
        final first = Completer<Result<File>>();
        final second = Completer<Result<File>>();
        await pumpScreen(tester);

        // 1. First fetch, gated.
        repo.pdfGate = first;
        await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
        await _pumpFrames(tester, n: 3);
        expect(repo.dispoPdfCalls, 1);

        // 2. Cancel → idle.
        await tester.tap(find.byKey(const Key('report-pdf-cancel-dispo')));
        await _pumpFrames(tester);
        expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);

        // 3. Refetch (a NEW token owns the card now).
        repo.pdfGate = second;
        await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
        await _pumpFrames(tester, n: 3);
        expect(repo.dispoPdfCalls, 2);
        expect(
          find.byKey(const Key('report-pdf-progress-dispo')),
          findsOneWidget,
        );

        // 4. The CANCELLED first request completes late with a staged file:
        // the superseded branch must delete the file silently and leave the
        // newer fetch's card untouched.
        final stale = File('${tempDir.path}/day-1-dispo.pdf')
          ..writeAsBytesSync([37, 80, 68, 70]);
        first.complete(Right(stale));
        await _pumpFrames(tester);
        expect(stale.existsSync(), isFalse);
        expect(
          find.byKey(const Key('report-pdf-progress-dispo')),
          findsOneWidget,
        );

        // 5. The CURRENT fetch completes → ready card with its own file.
        final current = File('${tempDir.path}/day-1-dispo.pdf')
          ..writeAsBytesSync([37, 80, 68, 70, 1]);
        second.complete(Right(current));
        await _pumpFrames(tester);
        expect(
          find.byKey(const Key('report-pdf-preview-dispo')),
          findsOneWidget,
        );
      },
    );

    testWidgets('error: code-keyed copy with retry', (tester) async {
      await setupContainer();
      repo.nextPdf = const Left(ProblemError(code: 'http.404'));
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('report-pdf-fetch-shootDay')));
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('report-pdf-error-shootDay')),
        findsOneWidget,
      );
      expect(find.textContaining('http.404'), findsOneWidget);
      expect(
        find.byKey(const Key('report-pdf-retry-shootDay')),
        findsOneWidget,
      );
      expect(repo.shootDayPdfCalls, 1);
    });

    testWidgets('ready: preview + share; share cleans the temp file', (
      tester,
    ) async {
      await setupContainer();
      final staged = File('${tempDir.path}/day-1-dispo.pdf')
        ..writeAsBytesSync([37, 80, 68, 70]);
      repo.nextPdf = Right(staged);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('report-pdf-preview-dispo')), findsOneWidget);
      expect(find.byKey(const Key('report-pdf-share-dispo')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-pdf-share-dispo')));
      await _pumpFrames(tester);
      expect(share.lastShared?.path, staged.path);
      expect(share.lastName, 'day-1-dispo.pdf');
      // Share is a save exit through the platform sheet: our temp copy is
      // deleted and the card returns to idle.
      expect(staged.existsSync(), isFalse);
      expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
    });

    testWidgets('strict-reject: unknown status renders the error state', (
      tester,
    ) async {
      await setupContainer(
        sollIst: const Left(ProblemError(code: 'report.unknown_status')),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-error')), findsOneWidget);
      expect(find.textContaining('unrecognized format'), findsOneWidget);
    });
  });

  group('AUTHZ-GATE matrix (2.3/2.4): zero report requests when denied', () {
    testWidgets('resolved denial shows the 403 narrative', (tester) async {
      await setupContainer(membership: MembershipMode.denied);
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-denied')), findsOneWidget);
      // The banner carries the 403 narrative (the Soll-Ist section error
      // view renders the same code-keyed copy — scope to the banner).
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-denied')),
          matching: find.textContaining('do not have access'),
        ),
        findsOneWidget,
      );
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
      // Fetch buttons are disabled while denied.
      final fetch = tester.widget<FilledButton>(
        find.byKey(const Key('report-pdf-fetch-dispo')),
      );
      expect(fetch.onPressed, isNull);
    });

    testWidgets('unknown capability string denies locally', (tester) async {
      await setupContainer(membership: MembershipMode.unknownCap);
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-denied')), findsOneWidget);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
    });

    testWidgets('membership loading denies locally', (tester) async {
      await setupContainer(membership: MembershipMode.loading);
      await pumpScreen(tester);

      // Pending: actions disabled, never the 403 narrative — and zero
      // report requests (the check never triggers a membership fetch).
      expect(find.byKey(const Key('reports-denied')), findsNothing);
      final fetch = tester.widget<FilledButton>(
        find.byKey(const Key('report-pdf-fetch-dispo')),
      );
      expect(fetch.onPressed, isNull);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
    });

    testWidgets('membership error denies locally with retry', (tester) async {
      await setupContainer(membership: MembershipMode.error);
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-denied')), findsOneWidget);
      expect(find.byKey(const Key('reports-denied-retry')), findsOneWidget);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
    });

    testWidgets('controller fetchPdf under denial issues zero requests', (
      tester,
    ) async {
      await setupContainer(membership: MembershipMode.denied);
      await pumpScreen(tester);

      await container
          .read(reportsControllerProvider(_scope).notifier)
          .fetchPdf(ReportPdfKind.dispo);
      await _pumpFrames(tester);
      expect(repo.pdfCalls, 0);
      expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
    });
  });

  group('ReportsScreen goldens ({light,dark} x {android,macOS})', () {
    Future<void> golden(
      WidgetTester tester,
      String name, {
      required Brightness brightness,
      TargetPlatform? platform,
    }) async {
      try {
        await pumpScreen(tester, brightness: brightness, platform: platform);
        expect(find.byKey(const Key('soll-ist-report-screen')), findsOneWidget);
        expect(find.text('Planned vs actual'), findsOneWidget);
        await expectLater(
          find.byType(ReportsScreen),
          matchesGoldenFile('goldens/reports_$name.png'),
        );
      } finally {
        // Reset before the test ends (foundation invariant check) — same
        // convention as the shooting-days goldens.
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('idle light android', (tester) async {
      await setupContainer();
      await golden(tester, 'idle_light_android', brightness: Brightness.light);
    });

    testWidgets('idle dark android', (tester) async {
      await setupContainer();
      await golden(tester, 'idle_dark_android', brightness: Brightness.dark);
    });

    testWidgets('idle light macos', (tester) async {
      await setupContainer();
      await golden(
        tester,
        'idle_light_macos',
        brightness: Brightness.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('idle dark macos', (tester) async {
      await setupContainer();
      await golden(
        tester,
        'idle_dark_macos',
        brightness: Brightness.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
