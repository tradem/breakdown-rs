// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-4 integration smoke (`flutter-reports` 4.1, on device/emulator,
// dev-auth): fetch → preview → share with a faked share sheet; the failure
// path leaves no partial artifacts. Runs against scriptable fakes (no
// backend needed): the device exercises the real screen, controller,
// temp-file staging, pdfrx preview rendering and the share seam. Run via
// `flutter test integration_test/reports_smoke_test.dart` against a
// device/emulator; not part of the headless `flutter test` pass.

import 'dart:convert';
import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/reports/report_share.dart';
import 'package:frontend_flutter/features/reports/reports_controller.dart';
import 'package:frontend_flutter/features/reports/reports_screen.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';

/// Minimal valid one-page PDF (letter-sized, one text object) — pdfrx opens
/// it on device without any bundled asset.
List<int> _tinyPdfBytes() {
  const objects = <String>[
    '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n',
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n',
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R'
        '/Resources<</Font<</F1 5 0 R>>>>>>endobj\n',
    '4 0 obj<</Length 44>>stream\nBT /F1 24 Tf 72 720 Td (Breakdown) Tj ET\n'
        'endstream endobj\n',
    '5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n',
  ];
  final buffer = StringBuffer('%PDF-1.4\n')..write(objects.join());
  // xref table (offsets are not validated by lenient viewers, but keep the
  // structure present so strict parsers still find the trailer).
  buffer
    ..writeln('xref')
    ..writeln('0 6')
    ..writeln('0000000000 65535 f ')
    ..writeln('trailer<</Size 6/Root 1 0 R>>')
    ..writeln('startxref')
    ..writeln('0')
    ..writeln('%%EOF');
  return latin1.encode(buffer.toString());
}

SeasonMembershipDto _membership() => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(['assign_costumes', 'upload_continuity_photos']),
);

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

SollIstReport _report() => SollIstReport(
  (b) => b
    ..isFinal = true
    ..rows.replace([
      SollIstDiffRow(
        (b) => b
          ..sceneId = 's-1'
          ..sceneNumber = 1
          ..missing = false
          ..moved = false
          ..reshotCandidate = false
          ..skipped = false,
      ),
    ]),
);

/// Scriptable report backend: JSON + PDF fetch counters, scriptable results.
class _E2eReportsRepository extends SceneShootRepository {
  _E2eReportsRepository(super.api, super.cache);

  int pdfCalls = 0;
  int sollIstCalls = 0;

  /// Optional script overriding the dispo PDF fetch (failure path).
  Future<Result<File>> Function()? scriptDispoPdf;

  @override
  Future<Result<SollIstReport>> fetchSollIstReport(String id) async {
    sollIstCalls++;
    return Right(_report());
  }

  @override
  Future<Result<List<DispoRow>>> fetchDispoReport(String id) async =>
      const Right([]);

  @override
  Future<Result<List<ShootDayRow>>> fetchShootDayReport(String id) async =>
      const Right([]);

  @override
  Future<Result<File>> dispoReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    pdfCalls++;
    final script = scriptDispoPdf;
    if (script != null) return script();
    onReceiveProgress?.call(4, 4);
    final file = File('${tempDir.path}/day-1-dispo.pdf');
    await file.writeAsBytes(_tinyPdfBytes(), flush: true);
    return Right(file);
  }
}

class _E2eShare implements ReportShareService {
  File? lastShared;

  @override
  Future<Result<void>> sharePdf(File file, {required String fileName}) async {
    lastShared = file;
    return const Right(null);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const devConfig = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    defaultSeriesId: 'series-e2e',
  );

  late CacheDatabase db;
  late _E2eReportsRepository repo;
  late _E2eShare share;
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    db = CacheDatabase();
    repo = _E2eReportsRepository(BreakdownApi(), SceneShootCacheDao(db));
    share = _E2eShare();
    tempDir = await Directory.systemTemp.createTemp('reports-e2e-');
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        reportsTempDirProvider.overrideWith((ref) async => tempDir),
        reportShareServiceProvider.overrideWithValue(share),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => Right(_membership())),
      ],
    );
    await container.read(authSessionControllerProvider.notifier).signIn();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemes.light(),
          home: ReportsScreen(day: _day(), seasonId: 'season-1'),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('fetch → preview → share happy path; temp cleaned', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byKey(const Key('soll-ist-report-screen')), findsOneWidget);
    expect(find.byKey(const Key('soll-ist-final')), findsOneWidget);

    // Fetch (user-initiated) → ready card.
    await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.pdfCalls, 1);
    expect(find.byKey(const Key('report-pdf-preview-dispo')), findsOneWidget);

    // In-app preview opens the real pdfrx viewer.
    await tester.tap(find.byKey(const Key('report-pdf-preview-dispo')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('report-pdf-viewer')), findsOneWidget);

    // Preview closed without sharing → staged temp copy deleted (D3).
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(File('${tempDir.path}/day-1-dispo.pdf').existsSync(), isFalse);
    expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);

    // Share path: staged → faked platform sheet → temp deleted, idle.
    await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('report-pdf-share-dispo')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(share.lastShared, isNotNull);
    expect(File('${tempDir.path}/day-1-dispo.pdf').existsSync(), isFalse);
    expect(find.byKey(const Key('report-pdf-fetch-dispo')), findsOneWidget);
  });

  testWidgets('failure path: error card, no partial artifacts', (tester) async {
    // Script the fetch to fail AFTER staging a partial file: the fake
    // deletes it before returning Err, mirroring the cache layer's abort
    // cleanup; the smoke asserts nothing is left behind.
    final failing = _E2eReportsRepository(
      BreakdownApi(),
      SceneShootCacheDao(db),
    );
    failing.scriptDispoPdf = () async {
      final partial = File('${tempDir.path}/day-1-dispo.pdf');
      await partial.writeAsBytes([0x25, 0x50]);
      await partial.delete();
      return const Left(ProblemError(code: 'http.503'));
    };
    final failContainer = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(failing),
        reportsTempDirProvider.overrideWith((ref) async => tempDir),
        reportShareServiceProvider.overrideWithValue(share),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => Right(_membership())),
      ],
    );
    await failContainer.read(authSessionControllerProvider.notifier).signIn();
    addTearDown(failContainer.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: failContainer,
        child: MaterialApp(
          theme: AppThemes.light(),
          home: ReportsScreen(day: _day(), seasonId: 'season-1'),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const Key('report-pdf-fetch-dispo')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('report-pdf-error-dispo')), findsOneWidget);
    // Failure path leaves no partial artifacts in the temp directory.
    expect(await tempDir.list().toList(), isEmpty);
  });
}
