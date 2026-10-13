// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Widget tests for the full-screen Create Scene page (issue #624): the
// quick-create sheet's "Neue Szene" entry pushes it for the active episode.
// It hosts the shared CreateSceneForm, so these tests cover the page's
// episode wiring, its submit dispatch, its inline failure banner and the
// client AUTHZ gate (no request without a resolved session).

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
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/scenes/create_scene_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');

class _FakeSceneRepository extends SceneRepository {
  _FakeSceneRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  CreateSceneRequest? lastCreateRequest;

  @override
  Future<Result<IdVersionResponse>> create(CreateSceneRequest request) {
    lastCreateRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n1'
            ..version = 1,
        ),
      ),
    );
  }
}

Future<void> pumpFrames(WidgetTester tester, {int n = 12}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeSceneRepository repo;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = _FakeSceneRepository(BreakdownApi(), SceneCacheDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<ProviderContainer> buildContainer({bool signedIn = true}) async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (signedIn) {
      await container.read(authSessionControllerProvider.notifier).signIn();
    }
    return container;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container, {
    String episodeId = 'episode-1',
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: CreateSceneScreen(episodeId: episodeId),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets('submits the create command for the page episode', (
    tester,
  ) async {
    final container = await buildContainer();
    await pumpPage(tester, container);

    await tester.enterText(
      find.byKey(const Key('create-scene-summary')),
      'Neue Szene',
    );
    await tester.tap(find.byKey(const Key('create-scene-submit')));
    await pumpFrames(tester);

    expect(repo.lastCreateRequest?.episodeId, 'episode-1');
    expect(find.byKey(const Key('create-scene-error-banner')), findsNothing);
  });

  testWidgets('a failed command surfaces the inline banner (Err branch)', (
    tester,
  ) async {
    final container = await buildContainer();
    repo.nextCreate = const Left(_networkDown);
    await pumpPage(tester, container);

    await tester.tap(find.byKey(const Key('create-scene-submit')));
    await pumpFrames(tester);

    expect(find.byKey(const Key('create-scene-error-banner')), findsOneWidget);
    // Stayed open — the page does not pop away its own error surface.
    expect(find.byKey(const Key('create-scene-submit')), findsOneWidget);
  });

  testWidgets('AUTHZ gate: no session, no request (deny before network)', (
    tester,
  ) async {
    final container = await buildContainer(signedIn: false);
    await pumpPage(tester, container);

    await tester.tap(find.byKey(const Key('create-scene-submit')));
    await pumpFrames(tester);

    expect(repo.lastCreateRequest, isNull);
    expect(find.byKey(const Key('create-scene-error-banner')), findsOneWidget);
  });
}
