// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/auth/season_membership_provider.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';

SeasonMembershipDto _dto(String seasonId, List<String> capabilities) =>
    SeasonMembershipDto(
      (b) => b
        ..seasonId = seasonId
        ..hasActiveCostumeRoleInSeason = capabilities.isNotEmpty
        ..capabilities.replace(capabilities),
    );

void main() {
  group('strictParseMembership (D6 strict capabilities)', () {
    test('known capability set parses to Right', () {
      final res = strictParseMembership(
        Right(_dto('s', const ['upload_continuity_photos', 'assign_costumes'])),
      );
      expect(res.isRight(), isTrue);
    });

    test('empty capabilities parse to Right', () {
      expect(
        strictParseMembership(Right(_dto('s', const []))).isRight(),
        isTrue,
      );
    });

    test('unknown entry rejects the DTO with a stable code', () {
      final res = strictParseMembership(
        Right(_dto('s', const ['upload_continuity_photos', 'future_cap'])),
      );
      expect(res.isLeft(), isTrue);
      res.fold(
        (err) => expect(err.code, 'authz.membership.capability_unknown'),
        (_) => fail('expected Left'),
      );
    });

    test('fetch failures pass through unchanged', () {
      const err = ProblemError(code: 'season.not-found', status: 404);
      final res = strictParseMembership(
        const Left<ProblemError, SeasonMembershipDto>(err),
      );
      expect(res, const Left(err));
    });
  });

  group('seasonMembershipProvider (TTL-scoped, D6 display read)', () {
    test('serves the cache within TTL, refetches after expiry', () async {
      var now = DateTime.utc(2026, 1, 1);
      var fetches = 0;
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(Clock(() => now)),
          membershipFetchProvider('s1').overrideWith((ref) async {
            fetches++;
            return Right<ProblemError, SeasonMembershipDto>(
              _dto('s1', const ['upload_continuity_photos']),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      // Hold a subscription: the provider is auto-dispose, and a bare
      // `read(future)` without a listener disposes mid-flight.
      final sub = container.listen(seasonMembershipProvider('s1'), (_, _) {});
      addTearDown(sub.close);

      final first = await container.read(seasonMembershipProvider('s1').future);
      expect(first.isRight(), isTrue);
      expect(fetches, 1);

      // Within TTL: served from the cache, no network call.
      final second = await container.read(
        seasonMembershipProvider('s1').future,
      );
      expect(second.isRight(), isTrue);
      expect(fetches, 1);

      // Past the TTL: refetches (the provider revalidates the fetch
      // explicitly, so the read hits the network even if the auto-dispose
      // fetch element has not been timer-disposed yet).
      now = now.add(kMembershipTtl + const Duration(seconds: 1));
      final third = await container.refresh(
        seasonMembershipProvider('s1').future,
      );
      expect(third.isRight(), isTrue);
      expect(fetches, 2);
    });

    test(
      'strict rejection is cached too (no refetch storm on unknown caps)',
      () async {
        var fetches = 0;
        final container = ProviderContainer(
          overrides: [
            membershipFetchProvider('s1').overrideWith((ref) async {
              fetches++;
              return Right<ProblemError, SeasonMembershipDto>(
                _dto('s1', const ['nope_unknown']),
              );
            }),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(seasonMembershipProvider('s1'), (_, _) {});
        addTearDown(sub.close);

        final first = await container.read(
          seasonMembershipProvider('s1').future,
        );
        expect(
          first.fold((e) => e.code, (_) => 'right'),
          'authz.membership.capability_unknown',
        );
        await container.read(seasonMembershipProvider('s1').future);
        expect(fetches, 1);
      },
    );
  });
}
