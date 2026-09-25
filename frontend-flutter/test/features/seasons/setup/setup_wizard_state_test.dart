// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_state.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';

/// Pure unit tier (task 2.1/2.3): the wizard state machine's validation
/// functions and the smart-default season number — no Flutter framework
/// imports, no providers, no widget pumping.

SeasonView _season(String id, int number) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('smartDefaultSeasonNumber (task 2.3)', () {
    test('empty list defaults to 1', () {
      expect(smartDefaultSeasonNumber(const []), 1);
    });

    test(
      'max+1 with existing seasons 1 and 2 (spec smart-default scenario)',
      () {
        expect(
          smartDefaultSeasonNumber([_season('s1', 1), _season('s2', 2)]),
          3,
        );
      },
    );

    test('gaps are NOT filled (max+1, never a hole)', () {
      expect(smartDefaultSeasonNumber([_season('s1', 1), _season('s5', 5)]), 6);
    });

    test('collision-free: numbers taken never suggested', () {
      final existing = [_season('a', 3), _season('b', 3), _season('c', 7)];
      final next = smartDefaultSeasonNumber(existing);
      expect(existing.every((s) => s.number != next), isTrue);
      expect(next, 8);
    });
  });

  group('validatePositiveCount (pure validation)', () {
    test('valid positive integers pass', () {
      expect(validatePositiveCount('1'), isNull);
      expect(validatePositiveCount(' 42 '), isNull);
    });

    test('every non-positive/non-integer input fails with the same code', () {
      for (final raw in ['', 'abc', '0', '-1', '1.5', '  ']) {
        expect(
          validatePositiveCount(raw),
          WizardFieldError.notPositiveNumber,
          reason: 'input "$raw"',
        );
      }
    });
  });

  group('validateHasBlocks (submit-time)', () {
    test('zero drafts fail', () {
      expect(validateHasBlocks(const []), WizardFieldError.noBlocks);
    });

    test('at least one draft passes', () {
      expect(validateHasBlocks(const [BlockDraft()]), isNull);
    });
  });

  group('wizardErrorCopyForField (code → inline copy)', () {
    test('each error code gets its own narrative', () {
      expect(
        wizardErrorCopyForField(
          AppLocalizationsDe(),
          WizardFieldError.notPositiveNumber,
        ),
        contains('größer als 0'),
      );
      expect(
        wizardErrorCopyForField(
          AppLocalizationsDe(),
          WizardFieldError.noBlocks,
        ),
        contains('Mindestens ein Block'),
      );
    });
  });

  group('wizardDispatchTotal (progress denominator)', () {
    test('season only', () {
      expect(wizardDispatchTotal(const []), 1);
    });

    test('1 + per block (1 block-create + n episode-creates)', () {
      expect(
        wizardDispatchTotal([
          const BlockDraft(episodeCount: 4),
          const BlockDraft(episodeCount: 4),
        ]),
        1 + 2 * (1 + 4),
      );
    });
  });

  group('wizardErrorCopy (command failure, keyed on stable code)', () {
    test('conflict narrative for the 409 season conflict', () {
      // The copy is asserted VERBATIM — a wrong mapping (e.g. the generic
      // fallback) must fail, not just "anything without the word detail".
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'seasons.conflict'),
        ),
        'Eine Season mit dieser Nummer existiert bereits.',
      );
    });

    test(
      'REAL wire code `season.number-already-exists` maps the same (443)',
      () {
        // Issue #443: the backend registry emits
        // `{context}.number-already-exists`; the legacy `*.conflict` aliases
        // never appear on the wire. The real code MUST hit the same copy.
        expect(
          wizardErrorCopy(
            AppLocalizationsDe(),
            const ProblemError(code: 'season.number-already-exists'),
          ),
          'Eine Season mit dieser Nummer existiert bereits.',
        );
      },
    );

    test(
      'REAL wire code `block.number-already-exists` names the SERIES scope',
      () {
        // Exactly the code the injected fault (and the real advisory
        // pre-check) returns — this mapping is what the Gherkin
        // partial-failure scenario asserts on device.
        expect(
          wizardErrorCopy(
            AppLocalizationsDe(),
            const ProblemError(code: 'block.number-already-exists'),
          ),
          'Ein Block mit dieser Nummer existiert bereits in der Serie.',
        );
      },
    );

    test(
      'REAL wire code `episode.number-already-exists` names the SERIES scope',
      () {
        expect(
          wizardErrorCopy(
            AppLocalizationsDe(),
            const ProblemError(code: 'episode.number-already-exists'),
          ),
          'Eine Episode mit dieser Nummer existiert bereits in der Serie.',
        );
      },
    );

    test('block conflict copy names the SERIES scope (never per season)', () {
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'blocks.conflict'),
        ),
        'Ein Block mit dieser Nummer existiert bereits in der Serie.',
      );
    });

    test('episode conflict copy names the SERIES scope (never per block)', () {
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'episodes.conflict'),
        ),
        'Eine Episode mit dieser Nummer existiert bereits in der Serie.',
      );
    });

    test('auth denial narrative', () {
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'authz.denied'),
        ),
        contains('melde dich an'),
      );
    });

    test('transport narrative for the transport.* namespace', () {
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'transport.connectionError'),
        ),
        contains('Netzwerkproblem'),
      );
    });

    test('unknown code falls back to a code-carrying generic', () {
      expect(
        wizardErrorCopy(
          AppLocalizationsDe(),
          const ProblemError(code: 'weird.failure'),
        ),
        contains('weird.failure'),
      );
    });
  });

  group('SetupWizardState initial shape', () {
    test(
      'defaults: season step, editing, no drafts (the controller seeds one)',
      () {
        const state = SetupWizardState();
        expect(state.step, SetupWizardStep.season);
        expect(state.phase, SetupWizardPhase.editing);
        // The STATE default is empty — the controller's build() seeds the
        // first draft (spec: the Blocks step always opens with one draft).
        expect(state.blocks, isEmpty);
        expect(state.isEditing, isTrue);
        expect(state.isDispatching, isFalse);
      },
    );

    test('the controller-seeded initial state holds one default draft', () {
      const state = SetupWizardState(blocks: <BlockDraft>[BlockDraft()]);
      expect(state.blocks, hasLength(1));
      expect(state.blocks.single.episodeCount, 8);
    });
  });
}
