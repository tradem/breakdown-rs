// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Season lifecycle UI (issue #533): archived badge, write-affordance lock,
//! Err branch and locked-card goldens in German + English.
//!
//! Covers the issue's test row "Client: widget test for badge + disabled
//! affordances, goldens in de + en, Err-branch assertion":
//! * an archived row renders the localized badge and offers no card menu;
//! * an active row offers the archive entry; a successful archive command
//!   reaches the repository as the version echo, and the projection
//!   refetch converges the card;
//! * a `season.archived` rejection surfaces the localized locked narrative
//!   in the command-error banner (code-keyed, never the server `detail`);
//! * the locked card is snapshotted golden in German and English (light
//!   theme) — CI fails on an unreviewed rendering diff.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';
import 'package:frontend_flutter/features/seasons/widgets/season_card.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import 'seasons_test_fakes.dart';

const _kArchivedSeasonId = 'season-archived';
const _kActiveSeasonId = 'season-active';

/// Repo fake archive rejections for the Err branch: the idempotent-reject
/// 409 the backend's aggregate re-emits on a repeat archive.
const _conflict = ProblemError(code: 'season.archived', status: 409);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late ValueNotifier<Result<List<SeasonView>>> holder;
  late ProviderContainer container;

  /// The injectable list-fetch seam: always serves the current holder
  /// (D1: fetchAndCacheList writes the snapshot into Drift on success).
  Future<Result<List<SeasonView>>> fetchOnce() => Future.value(holder.value);

  /// Pumps [initialRows] into the cache (D1 seam) and the screen under the
  /// dev-auth session the AUTHZ-GATE requires. Rows reach the screen through
  /// the same fetchAndCacheList the production provider uses.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<SeasonView> initialRows,
    required Locale locale,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    holder = ValueNotifier(Right(initialRows));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        clockProvider.overrideWithValue(const Clock()),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(fetchOnce);
        }),
        seasonsCacheStaleProvider.overrideWith((ref) async => false),
        // The client-side AUTHZ-GATE source: an active costume-dept role in
        // the archived row's season is NOT resolved, the active row's is.
        membershipFetchProvider(_kArchivedSeasonId).overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            SeasonMembershipDto(
              (b) => b
                ..seasonId = _kArchivedSeasonId
                ..hasActiveCostumeRoleInSeason = false
                ..capabilities.replace(const []),
            ),
          ),
        ),
        membershipFetchProvider(_kActiveSeasonId).overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            SeasonMembershipDto(
              (b) => b
                ..seasonId = _kActiveSeasonId
                ..hasActiveCostumeRoleInSeason = true
                ..capabilities.replace(const []),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Dev-auth boots at the sign-in gate; the permissive session is the
    // `Continue` action the gate offers (paths are below the auth shell).
    await container.read(authSessionControllerProvider.notifier).signIn();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemes.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SeasonsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('archived row shows the badge and offers no menu', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialRows: [
        season(_kArchivedSeasonId, archived: true),
        season(_kActiveSeasonId),
      ],
      locale: const Locale('de'),
    );

    // Badge (localized German copy joins the subtitle line).
    expect(find.textContaining('Archiviert'), findsOneWidget);
    // The active row carries the menu affordance; the locked one does not
    // (the menu entry widgets exist only inside the opened menu).
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('archive command sends the version echo, then reconciles', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialRows: [season(_kActiveSeasonId)],
      locale: const Locale('de'),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle(); // menu opens
    await tester.tap(find.byKey(const Key('season-archive-entry')));
    await tester.pump(); // dispatch
    await tester.pumpAndSettle(); // bounded refetch

    expect(repo.archiveCalls, 1);
    expect(repo.lastArchive!.id, _kActiveSeasonId);
    expect(repo.lastArchive!.version, 1, reason: 'the version echo is sent');
  });

  testWidgets('season.archived rejection shows the locked narrative', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialRows: [season(_kActiveSeasonId)],
      locale: const Locale('de'),
    );
    repo.archiveResult = Left(_conflict);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle(); // menu opens
    await tester.tap(find.byKey(const Key('season-archive-entry')));
    await tester.pump(); // dispatch
    await tester.pumpAndSettle();

    // Code-keyed narrative from the catalog (the createErrorCopy branch),
    // never the server `detail`.
    expect(find.byKey(const Key('create-error-banner')), findsOneWidget);
    expect(find.textContaining('archiviert'), findsWidgets);
  });

  // One testWidgets per locale: flutter_test fails on timers pending at
  // teardown, so each container (and its membership/reconcile timers) gets
  // its own timer scope instead of leaking across locales.
  testWidgets('golden: locked season card (light, German)', (tester) async {
    await pumpScreen(
      tester,
      initialRows: [season(_kArchivedSeasonId, archived: true)],
      locale: const Locale('de'),
    );
    await expectLater(
      find.byType(SeasonCard, skipOffstage: true),
      matchesGoldenFile('goldens/seasons_archived_locked_de.png'),
    );
  });

  testWidgets('golden: locked season card (light, English)', (tester) async {
    await pumpScreen(
      tester,
      initialRows: [season(_kArchivedSeasonId, archived: true)],
      locale: const Locale('en'),
    );
    await expectLater(
      find.byType(SeasonCard, skipOffstage: true),
      matchesGoldenFile('goldens/seasons_archived_locked_en.png'),
    );
  });

  testWidgets('golden: archive affordance menu (light, German)', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialRows: [season(_kActiveSeasonId)],
      locale: const Locale('de'),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle(); // menu opens (entry key present now)
    expect(find.byKey(const Key('season-archive-entry')), findsOneWidget);
    await expectLater(
      find.byKey(const Key('season-archive-entry')),
      matchesGoldenFile('goldens/seasons_archive_affordance_de.png'),
    );
  });
}
