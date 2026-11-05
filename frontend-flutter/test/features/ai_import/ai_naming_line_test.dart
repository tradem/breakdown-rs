// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the shared provider/model naming line (issue
// #608, EU AI Act Art. 50 transparency): the configured wire naming, the
// honest unconfigured degradation, and the loading/error states — copy in
// every state, never a spinner trap, never an invented name.
//
// Plus the header card of the preview screen (issues #760 and #831): the card
// names the pair the JOB ran with (its content-free telemetry) as the primary
// line, adds the configured pair only when it differs — never twice, never a
// comparison it cannot make — and degrades honestly when a job recorded no
// telemetry, the account is unconfigured, or the discovery is still pending.

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_telemetry.dart';
import 'package:frontend_flutter/features/ai_import/naming_line.dart';

AiConfigView _namingConfig({
  LlmProvider provider = LlmProvider.openai,
  String model = 'assistant-model-1',
  String? decisionModel = 'decision-model-1',
  LlmProvider? decisionProvider = LlmProvider.openai,
}) => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = model
    ..provider = provider
    ..vaultKeyId = 'vk-1'
    ..prompts.replace(BuiltMap<String, String>())
    ..promptKinds.replace(BuiltList<DocumentKind>())
    ..revoked = false
    ..version = 1
    // The optional Decision Model slot (issue #722): only the "no Decision
    // Model" warning surface (issue #760) reads it.
    ..decisionModel = decisionModel
    ..decisionProvider = decisionProvider,
);

/// The job's content-free telemetry (issue #831): the pair the card names as
/// USED. `null` fields model a partially-recorded snapshot.
JobTelemetrySummary _jobTelemetry({
  LlmProvider? provider = LlmProvider.eurouter,
  String? model = 'mistral-large-3',
}) => JobTelemetrySummary(
  (b) => b
    ..cachedTokensIn = 0
    ..chunkCount = 1
    ..energyMillijoules = 0
    ..latencyTotalMs = 0
    ..tokensIn = 0
    ..tokensOut = 0
    ..model = model
    ..provider = provider,
);

const degradedCopy = 'No AI configuration is set up for this account.';
const loadingCopy = 'Provider and models are loading …';

Future<void> pumpLine(WidgetTester tester, ProviderContainer container) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AiNamingLine())),
    ),
  );
  await tester.pump();
}

/// Pumps [AiNamingCard] for `job-1` inside a fixed-width, scroll-free box so an
/// overflow in the header would fail loudly (issues #760/#831: a curated model
/// id can be long).
Future<void> pumpCard(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 360,
}) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const AiNamingCard(jobId: 'job-1'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The card's two reads: the configured naming discovery and the job's
/// telemetry snapshot. [naming] defaults to a resolved configuration;
/// [telemetry] defaults to a job that recorded NONE (an old job).
ProviderContainer _cardContainer({
  Future<AiConfigView?> Function()? naming,
  JobTelemetrySummary? telemetry,
}) => ProviderContainer(
  overrides: [
    configuredAiNamingProvider.overrideWith(
      (ref) => naming != null ? naming() : Future.value(_namingConfig()),
    ),
    aiJobTelemetryProvider.overrideWith(
      (ref, jobId) => Future<JobTelemetrySummary?>.value(telemetry),
    ),
  ],
);

void main() {
  testWidgets('configured: the wire naming (provider + assistant model) '
      'renders — model bound per the gen-l10n alphabetical order', (
    tester,
  ) async {
    await pumpLine(
      tester,
      ProviderContainer(
        overrides: [
          configuredAiNamingProvider.overrideWith(
            (ref) => Future.value(_namingConfig()),
          ),
        ],
      ),
    );
    expect(find.byType(Text), findsOneWidget);
    expect(
      tester.widget<Text>(find.byType(Text)).data,
      'Currently configured: provider openai, model assistant-model-1.',
    );
  });

  testWidgets('unconfigured discovery data: the honest degradation copy '
      '(never an invented name)', (tester) async {
    await pumpLine(
      tester,
      ProviderContainer(
        overrides: [
          configuredAiNamingProvider.overrideWith((ref) => Future.value(null)),
        ],
      ),
    );
    expect(tester.widget<Text>(find.byType(Text)).data, degradedCopy);
  });

  testWidgets('discovery failure: the same honest degradation copy', (
    tester,
  ) async {
    await pumpLine(
      tester,
      ProviderContainer(
        overrides: [
          configuredAiNamingProvider.overrideWith((ref) {
            final Future<AiConfigView?> failed = Future.error(
              StateError('discovery down'),
            );
            return failed;
          }),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(Text), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).data, degradedCopy);
  });

  testWidgets('loading: the honest loading note (re-renders, never a '
      'spinner trap)', (tester) async {
    await pumpLine(
      tester,
      ProviderContainer(
        overrides: [
          configuredAiNamingProvider.overrideWith((ref) {
            final Completer<AiConfigView?> never = Completer<AiConfigView?>();
            return never.future;
          }),
        ],
      ),
    );
    expect(tester.widget<Text>(find.byType(Text)).data, loadingCopy);
  });

  testWidgets('skipLoadingOnReload: a container invalidation keeps the '
      'resolved naming instead of flickering back to loading', (tester) async {
    final container = ProviderContainer(
      overrides: [
        configuredAiNamingProvider.overrideWith(
          (ref) => Future.value(_namingConfig()),
        ),
      ],
    );
    await pumpLine(tester, container);
    expect(
      tester.widget<Text>(find.byType(Text)).data,
      contains('assistant-model-1'),
    );

    // Invalidate + rebuild → data re-resolves without the loading copy.
    container.invalidate(configuredAiNamingProvider);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byType(Text)).data,
      contains('assistant-model-1'),
    );
  });

  group('aiNamingPairLabel — the display join of a wire pair (unit)', () {
    test('joins a complete pair, names a half alone, and refuses none', () {
      expect(
        aiNamingPairLabel(model: 'mistral-large-3', provider: 'eurouter'),
        'mistral-large-3 (eurouter)',
      );
      expect(aiNamingPairLabel(model: 'mistral-large-3'), 'mistral-large-3');
      expect(aiNamingPairLabel(provider: 'eurouter'), 'eurouter');
      expect(aiNamingPairLabel(), isNull);
      // Blank wire values are absences, not a pair.
      expect(aiNamingPairLabel(model: '  ', provider: ''), isNull);
    });
  });

  group('aiNamingComparison — used vs configured (unit, issue #831)', () {
    test('a differing configuration yields the used pair AND the differs '
        'pair', () {
      final comparison = aiNamingComparison(_namingConfig(), _jobTelemetry());
      expect(comparison.usedPair, 'mistral-large-3 (eurouter)');
      expect(comparison.configuredDiffersPair, 'assistant-model-1 (openai)');
      expect(comparison.hasUsed, isTrue);
    });

    test('an EQUAL configuration yields no second pair (the pair is named '
        'once)', () {
      final comparison = aiNamingComparison(
        _namingConfig(provider: LlmProvider.eurouter, model: 'mistral-large-3'),
        _jobTelemetry(),
      );
      expect(comparison.usedPair, 'mistral-large-3 (eurouter)');
      expect(comparison.configuredDiffersPair, isNull);
    });

    test('a differing PROVIDER alone counts as differing', () {
      final comparison = aiNamingComparison(
        _namingConfig(provider: LlmProvider.openai, model: 'mistral-large-3'),
        _jobTelemetry(),
      );
      expect(
        comparison.configuredDiffersPair,
        'mistral-large-3 (openai)',
        reason: 'the provider is half of the identity, not decoration',
      );
    });

    test('no telemetry (an old job) claims no used pair and NO comparison — '
        'even with a configuration', () {
      final comparison = aiNamingComparison(_namingConfig(), null);
      expect(comparison.hasUsed, isFalse);
      expect(comparison.usedPair, isNull);
      expect(comparison.configuredDiffersPair, isNull);
    });

    test('a telemetry with no identity at all is "no telemetry"', () {
      final comparison = aiNamingComparison(
        _namingConfig(),
        _jobTelemetry(provider: null, model: null),
      );
      expect(comparison.hasUsed, isFalse);
      expect(comparison.configuredDiffersPair, isNull);
    });

    test('a used pair survives an unconfigured account (no comparison, but '
        'the fact stays)', () {
      final comparison = aiNamingComparison(null, _jobTelemetry());
      expect(comparison.usedPair, 'mistral-large-3 (eurouter)');
      expect(comparison.configuredDiffersPair, isNull);
    });
  });

  group('AiNamingCard — the preview header (issues #760 and #831)', () {
    testWidgets('the USED pair is the primary line and a differing configured '
        'pair is named once beneath it (issue #831)', (tester) async {
      await pumpCard(tester, _cardContainer(telemetry: _jobTelemetry()));

      // It is a CARD, not a bare `bodySmall` line.
      expect(find.byType(Card), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-used')))
            .data,
        'Model used: mistral-large-3 (eurouter)',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('ai-preview-naming-configured-differs')),
            )
            .data,
        'Currently configured, differing model: assistant-model-1 (openai)',
      );
      // The configured pair is never repeated as a caption: the header names
      // each pair at most once (the pre-#831 defect named the configured pair
      // twice and the used pair never).
      expect(
        find.byKey(const Key('ai-preview-naming-disclosure')),
        findsNothing,
      );
    });

    testWidgets('an EQUAL configuration renders ONE line — no "differs" line, '
        'no caption repetition', (tester) async {
      await pumpCard(
        tester,
        _cardContainer(
          naming: () => Future.value(
            _namingConfig(
              provider: LlmProvider.eurouter,
              model: 'mistral-large-3',
            ),
          ),
          telemetry: _jobTelemetry(),
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-used')))
            .data,
        'Model used: mistral-large-3 (eurouter)',
      );
      expect(
        find.byKey(const Key('ai-preview-naming-configured-differs')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('ai-preview-naming-disclosure')),
        findsNothing,
      );
    });

    testWidgets('a job WITHOUT telemetry names no used model and invents no '
        'comparison — it names the configured pair once, labelled as '
        'configured', (tester) async {
      await pumpCard(tester, _cardContainer());

      expect(find.byKey(const Key('ai-preview-naming-used')), findsNothing);
      expect(
        find.byKey(const Key('ai-preview-naming-configured-differs')),
        findsNothing,
      );
      // The wording is explicitly "currently configured" — the card never
      // claims the import ran with it.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        'Currently configured: provider openai, model assistant-model-1.',
      );
    });

    testWidgets('a used pair is named even when the account has NO '
        'configuration (deleting a config does not undo the import)', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _cardContainer(
          naming: () => Future.value(null),
          telemetry: _jobTelemetry(),
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-used')))
            .data,
        'Model used: mistral-large-3 (eurouter)',
      );
      expect(
        find.byKey(const Key('ai-preview-naming-configured-differs')),
        findsNothing,
      );
      expect(find.text(degradedCopy), findsNothing);
    });

    testWidgets('a long model id stays on ONE line and ellipsizes (no '
        'overflow, rows are not pushed off screen)', (tester) async {
      const longModel =
          'anthropic/claude-sonnet-4.6-extended-thinking-preview-2026-01-31';
      await pumpCard(
        tester,
        _cardContainer(telemetry: _jobTelemetry(model: longModel)),
        width: 280,
      );

      final used = tester.widget<Text>(
        find.byKey(const Key('ai-preview-naming-used')),
      );
      expect(used.data, contains(longModel));
      expect(used.maxLines, 1);
      expect(used.overflow, TextOverflow.ellipsis);
      // No RenderFlex overflow was reported while laying the card out.
      expect(tester.takeException(), isNull);
    });

    testWidgets('unconfigured (and no telemetry): the honest degradation '
        'copy, no invented model/provider line', (tester) async {
      await pumpCard(tester, _cardContainer(naming: () => Future.value(null)));

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        degradedCopy,
      );
      expect(find.byKey(const Key('ai-preview-naming-used')), findsNothing);
      expect(
        find.byKey(const Key('ai-preview-naming-configured-differs')),
        findsNothing,
      );
    });

    testWidgets('discovery failure: the same degradation copy (never a '
        'provider/model the app could not read)', (tester) async {
      await pumpCard(
        tester,
        _cardContainer(
          naming: () =>
              Future<AiConfigView?>.error(StateError('discovery down')),
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        degradedCopy,
      );
      expect(find.byKey(const Key('ai-preview-naming-used')), findsNothing);
    });

    testWidgets('loading: the honest loading note instead of an empty header', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _cardContainer(naming: () => Completer<AiConfigView?>().future),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        loadingCopy,
      );
    });

    testWidgets('a FAILED telemetry read degrades to "no used pair" and never '
        'claims a comparison', (tester) async {
      final container = ProviderContainer(
        overrides: [
          configuredAiNamingProvider.overrideWith(
            (ref) => Future.value(_namingConfig()),
          ),
          aiJobTelemetryProvider.overrideWith(
            (ref, jobId) => Future<JobTelemetrySummary?>.error(
              StateError('job snapshot unreadable'),
            ),
          ),
        ],
      );
      await pumpCard(tester, container);

      expect(find.byKey(const Key('ai-preview-naming-used')), findsNothing);
      expect(
        find.byKey(const Key('ai-preview-naming-configured-differs')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        'Currently configured: provider openai, model assistant-model-1.',
      );
    });
  });
}
