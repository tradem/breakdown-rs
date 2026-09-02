// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_state.dart';

import 'seasons_test_fakes.dart';

void main() {
  group('SeasonsScreenState.rows merge (D2: projected ∪ overlays by id)', () {
    test('empty state renders no rows', () {
      const state = SeasonsScreenState(
        projected: AsyncValue<List<SeasonView>>.loading(),
      );
      expect(state.rows, isEmpty);
    });

    test('projected rows render as authoritative rows', () {
      final state = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a'), season('b')]),
        cachedRows: [season('a'), season('b')],
      );
      final rows = state.rows;
      expect(rows, hasLength(2));
      expect(rows[0], isA<ProjectedSeasonRow>());
      expect((rows[0] as ProjectedSeasonRow).season.id, 'a');
    });

    test('optimistic overlays follow the projected rows', () {
      final state = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a')]),
        cachedRows: [season('a')],
        overlays: const [
          SeasonOverlay(
            id: 'x',
            name: 'New',
            number: 2,
            status: OverlayStatus.acknowledged,
          ),
        ],
      );
      final rows = state.rows;
      expect(rows, hasLength(2));
      expect(rows.first, isA<ProjectedSeasonRow>());
      expect(rows.last, isA<OptimisticSeasonRow>());
    });

    test('a projected row with the same id wins over its overlay (dedupe)', () {
      // Belt-and-braces for reconciliation: even if an overlay survived a
      // refetch that already projected its id, the merge shows only the
      // authoritative projected row.
      final state = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('x', title: 'New')]),
        cachedRows: [season('x', title: 'New')],
        overlays: const [
          SeasonOverlay(
            id: 'x',
            name: 'New',
            number: 2,
            status: OverlayStatus.reconciling,
          ),
        ],
      );
      final rows = state.rows;
      expect(rows, hasLength(1));
      expect(rows.single, isA<ProjectedSeasonRow>());
    });

    test('loading projection exposes no authoritative rows', () {
      const state = SeasonsScreenState(
        projected: AsyncValue<List<SeasonView>>.loading(),
      );
      expect(state.projected.isLoading, isTrue);
      expect(state.projected.value, isNull);
    });
  });

  group('SeasonOverlay', () {
    test('copyWith moves status and carries a stale warning', () {
      const base = SeasonOverlay(
        id: 'x',
        name: 'New',
        number: 2,
        status: OverlayStatus.acknowledged,
      );
      final stale = base.copyWith(
        status: OverlayStatus.stale,
        warning: 'still catching up',
      );
      expect(stale.id, 'x');
      expect(stale.name, 'New');
      expect(stale.number, 2);
      expect(stale.status, OverlayStatus.stale);
      expect(stale.warning, 'still catching up');
    });

    test(
      'copyWith(clearWarning:) drops the warning and keeps the new status',
      () {
        const base = SeasonOverlay(
          id: 'x',
          name: 'New',
          number: 2,
          status: OverlayStatus.stale,
          warning: 'still catching up',
        );
        final cleared = base.copyWith(
          status: OverlayStatus.reconciling,
          clearWarning: () {},
        );
        // clearWarning takes precedence over the carried warning.
        expect(cleared.warning, isNull);
        expect(cleared.status, OverlayStatus.reconciling);
        expect(cleared.id, 'x');
        expect(cleared.name, 'New');
        expect(cleared.number, 2);
      },
    );

    test('value equality by all fields', () {
      const a = SeasonOverlay(id: 'x', status: OverlayStatus.reconciling);
      const b = SeasonOverlay(id: 'x', status: OverlayStatus.reconciling);
      const c = SeasonOverlay(id: 'x', status: OverlayStatus.stale);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('createErrorCopy maps stable problem codes to client copy', () {
    test('conflict code gets the conflict narrative (never detail text)', () {
      const err = ProblemError(
        code: 'seasons.conflict',
        detail: 'localized server text',
        status: 409,
      );
      expect(createErrorCopy(err), contains('already exists'));
      expect(createErrorCopy(err), isNot(contains('localized server text')));
    });

    test('authz denial gets the sign-in narrative', () {
      expect(
        createErrorCopy(const ProblemError(code: 'authz.denied')),
        contains('sign in'),
      );
    });

    test('transport codes get the network narrative', () {
      expect(
        createErrorCopy(const ProblemError(code: 'transport.connectionError')),
        contains('Network problem'),
      );
    });

    test('unknown codes surface a generic copy carrying the code', () {
      expect(
        createErrorCopy(const ProblemError(code: 'season.weird')),
        contains('season.weird'),
      );
    });
  });

  group('SeasonsScreenState.copyWith (D2 ephemeral overlay state)', () {
    final base = SeasonsScreenState(
      projected: AsyncData<List<SeasonView>>([season('a')]),
      cachedRows: [season('a')],
      overlays: const [
        SeasonOverlay(id: 'x', status: OverlayStatus.acknowledged),
      ],
    );

    test(
      'preserves commandError (not a copyWith param) and isStale default',
      () {
        final withErr = SeasonsScreenState(
          projected: AsyncData<List<SeasonView>>([season('a')]),
          cachedRows: [season('a')],
          commandError: const ProblemError(code: 'season.conflict'),
        ).copyWith(cachedRows: [season('b')]);
        expect(withErr.isStale, isFalse);
        expect(withErr.commandError?.code, 'season.conflict');
      },
    );

    test('replaces projected / cachedRows / overlays / isStale', () {
      final next = base.copyWith(
        projected: const AsyncLoading<List<SeasonView>>(),
        cachedRows: [season('b')],
        isStale: true,
        overlays: const [SeasonOverlay(id: 'y', status: OverlayStatus.stale)],
      );
      expect(next.projected, isA<AsyncLoading>());
      expect(next.cachedRows, hasLength(1));
      expect(next.cachedRows.single.id, 'b');
      expect(next.isStale, isTrue);
      expect(next.overlays, hasLength(1));
      expect(next.overlays.single.id, 'y');
      // commandError is carried unchanged (copyWith has no such param).
      expect(next.commandError, isNull);
    });
  });

  group('SeasonsScreenState equality / hashCode / toString', () {
    SeasonsScreenState make([List<SeasonView> rows = const []]) =>
        SeasonsScreenState(
          projected: AsyncData<List<SeasonView>>(rows),
          cachedRows: rows,
        );

    test('equal when every field matches (== true branch)', () {
      // Compare a state to its own copyWith(): copyWith preserves the exact
      // projected/cachedRows instances, so every == check in
      // SeasonsScreenState.== resolves true (Dart List equality is
      // identity-based, so two distinct list literals would NOT be ==).
      final a = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a')]),
        cachedRows: [season('a')],
      );
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when cachedRows differ', () {
      expect(make([season('a')]), isNot(make([season('b')])));
    });

    test('not equal when overlays differ', () {
      final a = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a')]),
        cachedRows: [season('a')],
        overlays: const [
          SeasonOverlay(id: 'x', status: OverlayStatus.acknowledged),
        ],
      );
      expect(a, isNot(a.copyWith(overlays: const [])));
    });

    test('not equal when isStale differs', () {
      final a = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a')]),
        cachedRows: [season('a')],
        isStale: true,
      );
      expect(a, isNot(a.copyWith(isStale: false)));
    });

    test('toString renders row and overlay counts', () {
      final s = SeasonsScreenState(
        projected: AsyncData<List<SeasonView>>([season('a')]),
        cachedRows: [season('a')],
        overlays: const [
          SeasonOverlay(id: 'x', status: OverlayStatus.acknowledged),
        ],
      );
      expect(s.toString(), contains('overlays: 1'));
    });
  });

  group('SeasonOverlay equality / hashCode / toString', () {
    test('equal instances share a stable hashCode', () {
      const a = SeasonOverlay(
        id: 'x',
        name: 'N',
        number: 1,
        status: OverlayStatus.acknowledged,
      );
      const b = SeasonOverlay(
        id: 'x',
        name: 'N',
        number: 1,
        status: OverlayStatus.acknowledged,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('distinct ids are not equal', () {
      const a = SeasonOverlay(id: 'x', status: OverlayStatus.acknowledged);
      const b = SeasonOverlay(id: 'y', status: OverlayStatus.acknowledged);
      expect(a, isNot(b));
    });

    test('toString renders id and status', () {
      const a = SeasonOverlay(id: 'x', status: OverlayStatus.stale);
      expect(a.toString(), contains('x'));
      expect(a.toString(), contains('stale'));
    });
  });
}
