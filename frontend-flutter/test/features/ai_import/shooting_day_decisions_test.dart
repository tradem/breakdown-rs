// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// Tier-1 pure tests for the issue #706 frontend continuation: the
// byte-for-byte day group-ref mirror (`draftShootingDayGroupRef`), the
// day-decision state (accept-all default, one decision per group on the
// wire, honest edit distance), and the planned→actual link eligibility
// predicate (`canLinkShootingDayInto` / `eligibleLinkTargets`).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_state.dart';

DraftShootingDay _day({int? number, String? label}) => DraftShootingDay(
  (b) => b
    ..number = number
    ..label = label,
);

PreviewRow _row(
  String ref, {
  int? dayNumber,
  String? dayLabel,
  DraftEpisode? episode,
}) => PreviewRow(
  draftRef: ref,
  label: 'Row $ref',
  episode: episode,
  shootingDay: dayNumber == null && dayLabel == null
      ? null
      : _day(number: dayNumber, label: dayLabel),
);

ShootingDayView _view(
  String id, {
  String episodeId = 'ep-1',
  bool archived = false,
  DateTime? wrappedAt,
  String orderKey = '!',
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..orderKey = orderKey
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1
    ..wrappedAt = wrappedAt,
);

void main() {
  group('draftShootingDayGroupRef — mirrors DraftShootingDay::group_key', () {
    test('the day number is the identity (`day:<n>`)', () {
      expect(
        draftShootingDayGroupRef(_day(number: 1, label: 'Tag 1')),
        'day:1',
      );
    });

    test('a label-only day groups by its TRIMMED label (`day-l:<label>`)', () {
      expect(
        draftShootingDayGroupRef(_day(label: '  Drehtag A  ')),
        'day-l:Drehtag A',
      );
    });

    test('a day with neither number nor label cannot be grouped', () {
      expect(draftShootingDayGroupRef(_day()), isNull);
      expect(draftShootingDayGroupRef(_day(label: '   ')), isNull);
    });

    test('the display label keeps the verbatim marker; `Tag <n>` is the '
        'fallback', () {
      expect(
        draftShootingDayLabel(_day(number: 2, label: ' 2. Spieltag ')),
        '2. Spieltag',
      );
      expect(draftShootingDayLabel(_day(number: 3)), 'Tag 3');
      expect(draftShootingDayLabel(_day()), '');
    });
  });

  group('AiApplyState — day decisions (issue #706)', () {
    test('dayRefs: first-appearance order, deduped, ungroupable days '
        'excluded', () {
      final state = AiApplyState(
        rows: [
          _row('d1', dayNumber: 1),
          _row('d2', dayNumber: 2),
          _row('d3', dayNumber: 1), // same day again — no new ref
          _row('d4'), // no day metadata — unscheduled flow
          _row('d5', dayLabel: 'Nacht'),
        ],
      );
      expect(state.dayRefs, ['day:1', 'day:2', 'day-l:Nacht']);
      expect(state.shootingDayOfGroup('day:2')?.number, 2);
      expect(state.shootingDayOfGroup('day:9'), isNull);
    });

    test('the default decision is ACCEPTED (extraction-as-extracted) and '
        'is not an edit', () {
      final state = AiApplyState(rows: [_row('d1', dayNumber: 1)]);
      expect(state.dayAccepted('day:1'), isTrue);
      expect(state.acceptAsIs, isTrue);
      expect(state.editDistance, 0);
    });

    test('buildShootingDays sends ONE decision per group — accepted default '
        'and explicit rejection both travel', () {
      final state = AiApplyState(
        rows: [_row('d1', dayNumber: 1), _row('d2', dayNumber: 2)],
      );
      final decisions = state.buildShootingDays();
      expect(decisions, hasLength(2));
      expect(decisions.map((d) => d.dayRef).toSet(), {'day:1', 'day:2'});
      expect(decisions.every((d) => d.accepted), isTrue);

      final rejected = AiApplyState(
        rows: state.rows,
        dayDecisions: const {'day:2': false},
      );
      final wire = rejected.buildShootingDays();
      expect(wire.singleWhere((d) => d.dayRef == 'day:2').accepted, isFalse);
      expect(wire.singleWhere((d) => d.dayRef == 'day:1').accepted, isTrue);
    });

    test('a toggled day is an EDIT: accept_as_is must not be claimed over a '
        'day group the reviewer rejected', () {
      final state = AiApplyState(
        rows: [_row('d1', dayNumber: 1), _row('d2', dayNumber: 2)],
        dayDecisions: const {'day:1': false},
      );
      expect(state.editDistance, 1);
      expect(state.acceptAsIs, isFalse);
      // Reverting restores the zero-edit review.
      final restored = AiApplyState(
        rows: state.rows,
        dayDecisions: const {'day:1': true},
      );
      expect(restored.editDistance, 0);
      expect(restored.acceptAsIs, isTrue);
    });

    test('a preview without day metadata builds an EMPTY day list (the '
        'request stays byte-identical to the pre-#706 client)', () {
      final state = AiApplyState(rows: [_row('d1')]);
      expect(state.dayRefs, isEmpty);
      expect(state.buildShootingDays(), isEmpty);
    });
  });

  group('canLinkShootingDayInto / eligibleLinkTargets (planned→actual)', () {
    test('the source itself, another episode, archived and wrapped days are '
        'never eligible', () {
      final source = _view('d-ai');
      expect(canLinkShootingDayInto(source, _view('d-ai')), isFalse);
      expect(
        canLinkShootingDayInto(source, _view('other', episodeId: 'ep-2')),
        isFalse,
      );
      expect(
        canLinkShootingDayInto(source, _view('d-arch', archived: true)),
        isFalse,
      );
      expect(
        canLinkShootingDayInto(
          source,
          _view('d-wrapped', wrappedAt: DateTime.utc(2026, 1, 1)),
        ),
        isFalse,
      );
      expect(canLinkShootingDayInto(source, _view('d-1')), isTrue);
    });

    test('eligibleLinkTargets preserves server order and filters only the '
        'ineligible', () {
      final source = _view('d-ai', orderKey: 'a');
      final targets = eligibleLinkTargets(source, [
        _view('d-ai', orderKey: 'a'),
        _view('d-1', orderKey: 'b'),
        _view('d-arch', orderKey: 'c', archived: true),
        _view('d-wrapped', orderKey: 'd', wrappedAt: DateTime.utc(2026, 1, 1)),
        _view('d-2', orderKey: 'e'),
        _view('other-ep', orderKey: 'f', episodeId: 'ep-2'),
      ]);
      expect(targets.map((d) => d.id), ['d-1', 'd-2']);
    });
  });
}
