// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/auth/membership/season_membership.dart';
import 'package:frontend_flutter/core/problem_error.dart';

const _devConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.0.9:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
);

const _realConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.0.9:3000',
  oidcIss: 'https://idp.example',
  devAuthSub: '',
  oidcAudience: 'breakdown-api',
  oidcClientId: 'client',
  oidcRedirectUri: 'breakdown://redirect',
  devIdpInsecure: '',
);

SeasonMembershipDto _dto({
  bool hasRole = true,
  Set<Capability> caps = const {Capability.uploadContinuityPhotos},
}) => SeasonMembershipDto(
  seasonId: 'season-1',
  hasActiveCostumeRoleInSeason: hasRole,
  capabilities: caps,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves to the fetched membership (AsyncData)', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_realConfig),
        dioProvider.overrideWithValue(Dio()),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(_dto()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(membershipFetchProvider('season-1').future);
    final state = container.read(currentMembershipProvider('season-1'));
    expect(state.value, isNotNull);
    expect(state.value!.seasonId, 'season-1');
    expect(state.value!.canUploadContinuityPhotos, isTrue);
  });

  test('loading is NOT a denial (D3): state is AsyncLoading, no 403', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_realConfig),
        dioProvider.overrideWithValue(Dio()),
        membershipFetchProvider('season-1').overrideWith(
          (ref) => Future.delayed(
            const Duration(seconds: 1),
            () => Right<ProblemError, SeasonMembershipDto>(_dto()),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(currentMembershipProvider('season-1'));
    // While the fetch is pending the state is loading — the gated action
    // would be disabled with a spinner, never reported as forbidden.
    expect(state.isLoading, isTrue);
    expect(state, isNot(isA<AsyncError>()));
  });

  test(
    'fetch Err → AsyncError with the ProblemError (D3: error ≠ denial)',
    () async {
      const problem = ProblemError(code: 'season.not-found', status: 403);
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_realConfig),
          dioProvider.overrideWithValue(Dio()),
          membershipFetchProvider('season-1').overrideWith(
            (ref) async => Left<ProblemError, SeasonMembershipDto>(problem),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(currentMembershipProvider('season-1'));
      await container.read(membershipFetchProvider('season-1').future);
      final state = container.read(currentMembershipProvider('season-1'));
      expect(state, isA<AsyncError>());
      expect((state as AsyncError).error, same(problem));
    },
  );

  test(
    'dev-auth mode returns the permissive membership with NO network',
    () async {
      // A Dio that fails on any call — proves the permissive path never
      // issues a request (Task 5.1).
      final failingDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_devConfig),
          dioProvider.overrideWithValue(failingDio),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        membershipFetchProvider('season-1').future,
      );
      final dto = result.fold((e) => throw e, (d) => d);
      expect(dto.hasActiveCostumeRoleInSeason, isTrue);
      expect(dto.canUploadContinuityPhotos, isTrue);
      expect(dto.canAssignCostumes, isTrue);
      expect(dto.seasonId, 'season-1');
    },
  );

  test('resolved denial exposes capability=false via the DTO getter', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_realConfig),
        dioProvider.overrideWithValue(Dio()),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async => Right<ProblemError, SeasonMembershipDto>(
            _dto(hasRole: false, caps: const {}),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(membershipFetchProvider('season-1').future);
    final dto = container.read(currentMembershipProvider('season-1')).value!;
    // A RESOLVED denial (AsyncData with capability false) is the ONLY state
    // in which a gated action shows the 403 narrative (D3).
    expect(dto.canUploadContinuityPhotos, isFalse);
  });
}
