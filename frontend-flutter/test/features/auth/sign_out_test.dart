// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/token_store.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/settings/api_base_override_store.dart';
import 'package:frontend_flutter/features/auth/login_screen.dart';
import 'package:frontend_flutter/features/auth/sign_out.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_state.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

import '../../auth/oidc_test_fakes.dart';
import '../seasons/seasons_test_fakes.dart';

AuthTokens _signedInTokens() => AuthTokens(
  accessToken: 'at-old',
  refreshToken: 'rt-old',
  idToken: testIdToken('user-1'),
);

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late FakeTokenStore tokens;
  late ProviderContainer container;

  /// Signed-in container (seeded store → restored session, seeded cache row):
  /// no network, no IdP — `signOut` never needs the OIDC client.
  void setupContainer({bool devAuth = false}) {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    tokens = FakeTokenStore(devAuth ? null : _signedInTokens());
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(
          devAuth ? devAuthConfig : realOidcConfig,
        ),
        tokenStoreProvider.overrideWithValue(tokens),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> seedCacheRow() async {
    final res = await repo.fetchAndCacheList(
      () async => Right([season('s1', number: 1, title: 'Seeded')]),
    );
    expect(res.isRight(), isTrue);
  }

  Future<AuthSession?> session() =>
      container.read(authSessionControllerProvider.future);

  group('signOut state machine (task 4.3)', () {
    test('Ok: tokens cleared, gate to login (cache: coordinator)', () async {
      setupContainer();
      expect(await session(), isNotNull);

      await container.read(authSessionControllerProvider.notifier).signOut();

      expect(await session(), isNull);
      expect(tokens.tokens, isNull);
    });

    test('token wipe Err: AsyncError, tokens intact, retry recovers', () async {
      setupContainer();
      tokens.failClear = true;

      await container.read(authSessionControllerProvider.notifier).signOut();

      final state = container.read(authSessionControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ProblemError>());
      expect(
        (state.error! as ProblemError).code,
        'auth.token_store_clear_failed',
      );
      expect(tokens.tokens, isNotNull);

      tokens.failClear = false;
      await container.read(authSessionControllerProvider.notifier).signOut();
      expect(await session(), isNull);
      expect(tokens.tokens, isNull);
    });

    test('dev-auth: no token wipe, back to Continue', () async {
      setupContainer(devAuth: true);
      await container.read(authSessionControllerProvider.notifier).signIn();
      expect((await session())?.sub, 'dev-user');

      await container.read(authSessionControllerProvider.notifier).signOut();

      expect(await session(), isNull);
    });
  });

  group('signOutEverywhere coordinator (task 4.2/4.3)', () {
    test('resets keepAlive UI/session state for the next session', () async {
      setupContainer();
      expect(await session(), isNotNull);
      // Stale UI state from the previous session.
      container
          .read(seasonOverlaysProvider.notifier)
          .add(
            const SeasonOverlay(id: 'o1', status: OverlayStatus.acknowledged),
          );
      container
          .read(seasonCommandErrorProvider.notifier)
          .set(const ProblemError(code: 'seasons.conflict'));
      container.read(seasonsPrevRowsProvider.notifier).set([season('s9')]);
      container
          .read(signInErrorProvider.notifier)
          .set(const ProblemError(code: 'oidc.timeout'));
      await seedCacheRow();

      await container.read(sessionResetProvider.notifier).signOut();

      expect(await session(), isNull);
      expect(tokens.tokens, isNull);
      expect(repo.clearCacheCalls, 1);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
      expect(container.read(seasonOverlaysProvider), isEmpty);
      expect(container.read(seasonCommandErrorProvider), isNull);
      expect(container.read(seasonsPrevRowsProvider), isEmpty);
      expect(container.read(seasonsControllerProvider).overlays, isEmpty);
      expect(container.read(signInErrorProvider), isNull);
    });

    test('token wipe Err: gate fails closed, cache still emptied', () async {
      setupContainer();
      await seedCacheRow();
      tokens.failClear = true;

      await container.read(sessionResetProvider.notifier).signOut();

      final state = container.read(authSessionControllerProvider);
      expect(state.hasError, isTrue);
      expect(
        (state.error! as ProblemError).code,
        'auth.token_store_clear_failed',
      );
      expect(tokens.tokens, isNotNull);
      expect(repo.clearCacheCalls, 1);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);

      // Retry re-attempts the token wipe first, then completes.
      tokens.failClear = false;
      await container.read(sessionResetProvider.notifier).signOut();
      expect(await session(), isNull);
      expect(tokens.tokens, isNull);
    });

    test('cache clear Err: AsyncError, retry recovers', () async {
      setupContainer();
      await seedCacheRow();
      repo.clearCacheResult = const Left(
        ProblemError(code: 'cache.clear_failed'),
      );

      await container.read(sessionResetProvider.notifier).signOut();

      final state = container.read(authSessionControllerProvider);
      expect(state.hasError, isTrue);
      expect((state.error! as ProblemError).code, 'cache.clear_failed');
      expect(tokens.tokens, isNull);

      repo.clearCacheResult = null;
      await container.read(sessionResetProvider.notifier).signOut();
      expect(await session(), isNull);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
    });
  });

  group('switchBackend (task 6.3)', () {
    late _OverridePlatform platform;

    void setupDevAuth() {
      platform = _OverridePlatform();
      _useOverridePlatform(platform);
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(repo),
          // Transport never issues requests here; satisfies fail-closed.
          pinnedSecurityContextProvider.overrideWithValue(SecurityContext()),
        ],
      );
      addTearDown(container.dispose);
    }

    test('Ok: persist, fence, rebuild base, clear, session kept', () async {
      setupDevAuth();
      await container.read(authSessionControllerProvider.notifier).signIn();
      await seedCacheRow();
      final dioBefore = container.read(apiDioProvider);

      final result = await container
          .read(sessionResetProvider.notifier)
          .switchBackend('https://dev.example:4000/');

      expect(result.isRight(), isTrue);
      // Persisted (canonical, no trailing slash).
      expect(
        platform.store[ApiBaseOverrideStore.key],
        'https://dev.example:4000',
      );
      // Generation fenced exactly once; Dio rebuilt against the new base.
      expect(container.read(cacheGenerationProvider), 1);
      expect(
        container.read(runtimeApiBaseProvider),
        'https://dev.example:4000',
      );
      final dioAfter = container.read(apiDioProvider);
      expect(identical(dioAfter, dioBefore), isFalse);
      expect(dioAfter.options.baseUrl, 'https://dev.example:4000');
      // Old rows gone; session untouched (tokens are IdP-scoped).
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
      expect((await session())?.sub, 'dev-user');
    });

    test('invalid URI: Left, nothing persisted or changed', () async {
      setupDevAuth();
      await container.read(authSessionControllerProvider.notifier).signIn();
      await seedCacheRow();

      final result = await container
          .read(sessionResetProvider.notifier)
          .switchBackend('http://evil.example/x');

      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        'settings.backend_uri_cleartext_rejected',
      );
      expect(platform.store.isEmpty, isTrue);
      expect(container.read(runtimeApiBaseProvider), isNull);
      expect(container.read(cacheGenerationProvider), 0);
      expect((await SeasonCacheDao(db).readAll()).length, 1);
    });

    test('persist failure: Left, base and cache untouched', () async {
      setupDevAuth();
      platform.failAll = true;
      await container.read(authSessionControllerProvider.notifier).signIn();

      final result = await container
          .read(sessionResetProvider.notifier)
          .switchBackend('https://dev.example:4000');

      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        'settings.override_write_failed',
      );
      expect(container.read(runtimeApiBaseProvider), isNull);
      expect(container.read(cacheGenerationProvider), 0);
    });

    test('cache clear failure: Left and session failed closed', () async {
      setupDevAuth();
      await container.read(authSessionControllerProvider.notifier).signIn();
      await seedCacheRow();
      repo.clearCacheResult = const Left(
        ProblemError(code: 'cache.clear_failed'),
      );

      final result = await container
          .read(sessionResetProvider.notifier)
          .switchBackend('https://dev.example:4000');

      expect(result.isLeft(), isTrue);
      final state = container.read(authSessionControllerProvider);
      expect(state.hasError, isTrue);
      expect((state.error! as ProblemError).code, 'cache.clear_failed');
    });
  });
}

/// In-memory secure-storage double for the override store used by
/// [SessionReset.switchBackend] (same pattern as the store's own tests).
class _OverridePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};
  bool failAll = false;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failAll) throw _fail('delete');
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    if (failAll) throw _fail('delete');
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failAll) throw _fail('read');
    return store[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    if (failAll) throw _fail('read');
    return Map.of(store);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failAll) throw _fail('write');
    store[key] = value;
  }

  Never _fail(String op) => throw StateError('secure storage $op failed');
}

void _useOverridePlatform(_OverridePlatform platform) {
  final previous = FlutterSecureStoragePlatform.instance;
  FlutterSecureStoragePlatform.instance = platform;
  addTearDown(() => FlutterSecureStoragePlatform.instance = previous);
}
