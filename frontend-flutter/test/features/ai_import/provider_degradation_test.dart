// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 tests for the provider-degraded derivation (issue #822).
//
// The rule this file pins is the WHOLE rule: only the consecutive newest run of
// provider-attributed attempts counts, the threshold is two, a single provider
// failure stays a transient blip, and an intervening non-provider failure ends
// the window. Everything the two surfaces render (status banner, compact row)
// is a view of this one derivation, so a bug here is a bug on both.
import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_state.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

AiImportAttempt _attempt(
  int attemptNo, {
  String? code,
  DateTime? createdAt,
  JobStatus status = JobStatus.failed,
}) => AiImportAttempt(
  (b) => b
    ..attemptNo = attemptNo
    ..code = code
    ..retryable = true
    ..status = status
    ..createdAt = createdAt ?? DateTime.utc(2026, 11, 4, 7, 6),
);

AiImportJob _job({
  JobStatus status = JobStatus.failed,
  List<AiImportAttempt> attempts = const [],
  DateTime? nextAttemptAt,
}) => AiImportJob(
  (b) => b
    ..id = 'job-1'
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = DocumentKind.script
    ..sourceFormat = SourceFormat.pdf
    ..dedupKey = 'dedup'
    ..documentDigest = 'digest'
    ..sourceHandle = 'handle'
    ..retries = attempts.length
    ..maxRetries = 5
    ..nextAttemptAt = nextAttemptAt
    ..attempts.addAll(attempts)
    ..createdAt = DateTime.utc(2026, 11, 4, 6, 54)
    ..updatedAt = DateTime.utc(2026, 11, 4, 7, 6),
);

/// The three-attempt shape the issue observed live: three provider 503s over
/// ~17 minutes, newest first (the wire contract).
List<AiImportAttempt> _outage() => [
  _attempt(
    3,
    code: aiLlmProviderUnavailableCode,
    createdAt: DateTime.utc(2026, 11, 4, 7, 6),
  ),
  _attempt(
    2,
    code: aiLlmProviderUnavailableCode,
    createdAt: DateTime.utc(2026, 11, 4, 6, 58),
  ),
  _attempt(
    1,
    code: aiLlmProviderUnavailableCode,
    createdAt: DateTime.utc(2026, 11, 4, 6, 54),
  ),
];

void main() {
  test('two consecutive provider failures fire the degraded state', () {
    final next = DateTime.utc(2026, 11, 4, 7, 10);
    final degradation = aiProviderDegradation(
      _job(attempts: _outage().take(2).toList(), nextAttemptAt: next),
    );
    expect(degradation, isNotNull);
    expect(degradation!.failedAttempts, 2);
    expect(degradation.retryBudgetSpent, isFalse);
    expect(degradation.nextAttemptAt, next);
    // Newest first: `first` is the OLDEST of the run, `last` the newest.
    expect(degradation.firstFailureAt, DateTime.utc(2026, 11, 4, 6, 58));
    expect(degradation.lastFailureAt, DateTime.utc(2026, 11, 4, 7, 6));
  });

  test(
    'three consecutive provider failures report the full run and window',
    () {
      final degradation = aiProviderDegradation(_job(attempts: _outage()));
      expect(degradation!.failedAttempts, 3);
      expect(degradation.firstFailureAt, DateTime.utc(2026, 11, 4, 6, 54));
      expect(degradation.lastFailureAt, DateTime.utc(2026, 11, 4, 7, 6));
    },
  );

  test('a SINGLE provider failure stays a transient blip (no aggregate)', () {
    final degradation = aiProviderDegradation(
      _job(attempts: [_attempt(1, code: aiLlmProviderUnavailableCode)]),
    );
    expect(degradation, isNull);
  });

  test('the generic service code never fires the aggregate — it may be the '
      'mapping DB, the pricing read model or storage', () {
    final degradation = aiProviderDegradation(
      _job(
        attempts: [
          _attempt(2, code: 'domain.service-unavailable'),
          _attempt(1, code: 'domain.service-unavailable'),
        ],
      ),
    );
    expect(degradation, isNull);
  });

  test('an intervening non-provider failure ends the window before the '
      'threshold', () {
    // Newest first: one provider failure, then a storage/database failure.
    // The contiguous provider run is 1, so nothing aggregates.
    final degradation = aiProviderDegradation(
      _job(
        attempts: [
          _attempt(2, code: aiLlmProviderUnavailableCode),
          _attempt(1, code: 'domain.service-unavailable'),
        ],
      ),
    );
    expect(degradation, isNull);
  });

  test('the window counts only the head of the history, not older provider '
      'failures behind a foreign code', () {
    final degradation = aiProviderDegradation(
      _job(
        attempts: [
          _attempt(3, code: aiLlmProviderUnavailableCode),
          _attempt(2, code: 'domain.service-unavailable'),
          _attempt(1, code: aiLlmProviderUnavailableCode),
        ],
      ),
    );
    expect(degradation, isNull);
  });

  test('an attempt with NO code also ends the window', () {
    final degradation = aiProviderDegradation(
      _job(
        attempts: [
          _attempt(2, code: aiLlmProviderUnavailableCode),
          _attempt(1),
        ],
      ),
    );
    expect(degradation, isNull);
  });

  test('dead_letter marks the retry budget spent', () {
    final degradation = aiProviderDegradation(
      _job(status: JobStatus.deadLetter, attempts: _outage()),
    );
    expect(degradation!.retryBudgetSpent, isTrue);
    // A terminal job schedules no next attempt — nothing is invented.
    expect(degradation.nextAttemptAt, isNull);
  });

  test('a succeeded job keeps no degraded state, even with provider '
      'failures in its history', () {
    expect(
      aiProviderDegradation(
        _job(status: JobStatus.succeeded, attempts: _outage()),
      ),
      isNull,
    );
  });

  test('payload_unavailable is not a provider-attributed state', () {
    expect(
      aiProviderDegradation(
        _job(status: JobStatus.payloadUnavailable, attempts: _outage()),
      ),
      isNull,
    );
  });

  test('a running job (re-claimed retry) renders no banner', () {
    expect(
      aiProviderDegradation(
        _job(status: JobStatus.running, attempts: _outage()),
      ),
      isNull,
    );
  });

  test('the primitive form derives the same value as the DTO form', () {
    final job = _job(attempts: _outage());
    expect(
      aiProviderDegradationOf(
        attempts: job.attempts,
        status: job.status,
        nextAttemptAt: job.nextAttemptAt,
      ),
      aiProviderDegradation(job),
    );
    // ...and an absent history is honest absence, not a fabricated run.
    expect(
      aiProviderDegradationOf(
        attempts: null,
        status: JobStatus.failed,
        nextAttemptAt: null,
      ),
      isNull,
    );
  });

  test('the constants the wire contract rests on', () {
    expect(aiLlmProviderUnavailableCode, 'ai-import.llm-provider-unavailable');
    expect(aiProviderDegradationThreshold, 2);
  });

  // The reason function is where the terminal rule actually lives, so it is
  // asserted here rather than only through the widgets: `retryPossible: false`
  // must remove the retry promise AND stay free of an exhaustion claim.
  group('aiJobFailureReason (issue #822 terminal rule)', () {
    final l10n = AppLocalizationsEn();

    test('a retryable provider failure still promises the next attempt', () {
      final copy = aiJobFailureReason(l10n, aiLlmProviderUnavailableCode);
      expect(copy, contains('AI provider'));
      expect(copy, contains('may succeed'));
    });

    test('a terminal provider failure never promises a retry', () {
      final copy = aiJobFailureReason(
        l10n,
        aiLlmProviderUnavailableCode,
        retryPossible: false,
      );
      expect(copy, contains('AI provider'));
      expect(copy, isNot(contains('may succeed')));
      expect(copy, contains('no further attempt is scheduled'));
    });

    test('the generic transient code follows the same rule (both arms)', () {
      final transient = aiJobFailureReason(l10n, 'domain.service-unavailable');
      expect(transient, contains('may succeed'));

      final terminal = aiJobFailureReason(
        l10n,
        'domain.service-unavailable',
        retryPossible: false,
      );
      expect(terminal, isNot(contains('may succeed')));
      expect(terminal, contains('no further attempt is scheduled'));
      // A terminal card must not claim the budget was spent either: a
      // `payload_unavailable` job is terminal for another reason, and the one
      // provable exhaustion claim belongs to the provider banner.
      expect(terminal, isNot(contains('budget is spent')));
    });

    test(
      'a rejected credential never describes retries that cannot happen',
      () {
        final transient = aiJobFailureReason(l10n, 'dependency.auth-failed');
        expect(transient, isNot(contains('retries continue')));

        final terminal = aiJobFailureReason(
          l10n,
          'dependency.auth-failed',
          retryPossible: false,
        );
        expect(terminal, isNot(contains('may succeed')));
        expect(terminal, contains('no further attempt is scheduled'));
      },
    );

    test('an unknown code keeps the generic arm with no retry vocabulary', () {
      expect(
        aiJobFailureReason(l10n, 'some.future-code', retryPossible: false),
        contains('some.future-code'),
      );
      expect(aiJobFailureReason(l10n, null), contains('unknown reason'));
    });
  });
}
