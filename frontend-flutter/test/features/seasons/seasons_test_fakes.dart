// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: muse-spark (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/token_store.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';

/// Dev-auth parity config (permissive session, no IdP wiring needed).
const devAuthConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: 'series-1',
);

/// Real-OIDC config (with an empty [TokenStore] this is a signed-out
/// session — used to exercise the AUTHZ-GATE denial paths).
const realOidcConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: 'https://idp.example',
  devAuthSub: '',
  oidcAudience: 'breakdown-api',
  oidcClientId: 'client',
  oidcRedirectUri: 'breakdown://redirect',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: '',
);

SeasonView season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Repository fake: [create] is scriptable, every other call runs the real
/// (cache-backed) implementation so Drift-touch/untouched assertions are
/// meaningful.
class FakeSeasonRepository extends SeasonRepository {
  FakeSeasonRepository(super.api, super.cache);

  /// Scripted outcome for [create]. `null` = never configured (assert-able).
  Result<IdVersionResponse>? createResult;

  /// How many create commands reached the "network".
  int createCalls = 0;

  /// The last request that reached the "network" (payload assertions).
  CreateSeasonRequest? lastCreateRequest;

  /// Scripted outcome for [clearCache]. `null` = real DAO clear.
  Result<void>? clearCacheResult;

  /// How many cache clears ran (sign-out empties the cache exactly once).
  int clearCacheCalls = 0;

  @override
  Future<Result<void>> clearCache() {
    clearCacheCalls++;
    final scripted = clearCacheResult;
    if (scripted != null) return Future.value(scripted);
    return super.clearCache();
  }

  @override
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) {
    createCalls++;
    // Capture the submitted payload so the form-to-DTO mapping is assertable
    // (CodeRabbit review: a wrong field mapping would otherwise pass silently).
    lastCreateRequest = request;
    final result =
        createResult ??
        Right<ProblemError, IdVersionResponse>(
          IdVersionResponse(
            (b) => b
              ..id = 'n$createCalls'
              ..version = 1,
          ),
        );
    return Future.value(result);
  }
}

/// In-memory [TokenStore] fake; `null` tokens = signed out.
class FakeTokenStore implements TokenStore {
  FakeTokenStore(this.tokens);

  AuthTokens? tokens;

  /// When true, [clear] fails with `auth.token_store_clear_failed`
  /// (sign-out Err-path tests) instead of wiping.
  bool failClear = false;

  @override
  Future<Result<AuthTokens?>> read() async =>
      Right<ProblemError, AuthTokens?>(tokens);

  @override
  Future<Result<void>> save(AuthTokens tokens) async {
    this.tokens = tokens;
    return const Right<ProblemError, void>(null);
  }

  @override
  Future<Result<void>> clear() async {
    if (failClear) {
      return const Left(ProblemError(code: 'auth.token_store_clear_failed'));
    }
    tokens = null;
    return const Right<ProblemError, void>(null);
  }
}

/// Controllable reconciliation backoff (deterministic-tests rule): each
/// [tick] parks on a completer until the test calls [advanceAll].
class ManualReconciliationScheduler extends ReconciliationScheduler {
  final List<Completer<void>> _pending = [];

  /// Ticks that have been requested (attempt budget accounting).
  int ticks = 0;

  @override
  Future<void> tick(int attempt) {
    ticks++;
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  /// Completes every currently-parked tick.
  void advanceAll() {
    final pending = List.of(_pending);
    _pending.clear();
    for (final c in pending) {
      c.complete();
    }
  }
}

/// Scheduler fake that never actually waits (zero-delay ticks) — passes
/// through the full retry budget within the microtask queue.
class ImmediateReconciliationScheduler extends ReconciliationScheduler {
  const ImmediateReconciliationScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}
