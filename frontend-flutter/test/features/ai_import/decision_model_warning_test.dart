// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the "no Decision Model configured" disclosure of the
// AI-import preview (issue #760): the warning renders ONLY for a resolved
// configuration whose Decision Model slot is empty, states the two factual
// consequences, offers the way into the AI configuration, and stays silent for
// a configured Decision Model, an unconfigured account, a pending discovery and
// a FAILED discovery (a failed read is not the fact "unset").

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/features/ai_import/naming_line.dart';

AiConfigView _config({String? decisionModel, LlmProvider? decisionProvider}) =>
    AiConfigView(
      (b) => b
        ..id = 'config-1'
        ..userId = 'dev-user'
        ..assistantModel = 'assistant-model-1'
        ..provider = LlmProvider.openai
        ..vaultKeyId = 'vk-1'
        ..prompts.replace(BuiltMap<String, String>())
        ..promptKinds.replace(BuiltList<DocumentKind>())
        ..revoked = false
        ..version = 1
        // The additive Decision Model slot (issue #722): both null = unset.
        ..decisionModel = decisionModel
        ..decisionProvider = decisionProvider,
    );

Future<void> pumpWarning(
  WidgetTester tester,
  ProviderContainer container, {
  VoidCallback? onConfigure,
}) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: AiDecisionModelWarning(onConfigure: onConfigure)),
      ),
    ),
  );
  await tester.pump();
}

ProviderContainer _container(FutureOr<AiConfigView?> Function() discovery) =>
    ProviderContainer(
      overrides: [
        configuredAiNamingProvider.overrideWith(
          (ref) => Future<AiConfigView?>.value(discovery()),
        ),
      ],
    );

void main() {
  testWidgets('configured WITHOUT a Decision Model: the warning names the two '
      'skipped consequences and the import staying runnable', (tester) async {
    await pumpWarning(tester, _container(() => _config()));

    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('ai-preview-decision-model-warning-title')),
          )
          .data,
      'No Decision Model configured',
    );
    final body = tester
        .widget<Text>(
          find.byKey(const Key('ai-preview-decision-model-warning-body')),
        )
        .data;
    // Exactly the two facts: Pass-2 wardrobe continuity and the ratings; the
    // import still runs. No speculation about quality.
    expect(body, contains('Wardrobe continuity suggestions (Pass 2)'));
    expect(body, contains('ratings are skipped'));
    expect(body, contains('The import still runs'));
  });

  testWidgets('the action opens the AI configuration (callback seam)', (
    tester,
  ) async {
    var configured = 0;
    await pumpWarning(
      tester,
      _container(() => _config()),
      onConfigure: () => configured++,
    );

    await tester.tap(
      find.byKey(const Key('ai-preview-decision-model-warning-action')),
    );
    await tester.pump();
    expect(configured, 1);
  });

  testWidgets('a configured Decision Model renders NOTHING', (tester) async {
    await pumpWarning(
      tester,
      _container(
        () => _config(
          decisionModel: 'decision-model-1',
          decisionProvider: LlmProvider.openai,
        ),
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(
      find.byKey(const Key('ai-preview-decision-model-warning-title')),
      findsNothing,
    );
  });

  testWidgets('a provider without a model stays unset (both fields are '
      'required)', (tester) async {
    await pumpWarning(
      tester,
      _container(() => _config(decisionProvider: LlmProvider.openai)),
    );

    expect(
      find.byKey(const Key('ai-preview-decision-model-warning-title')),
      findsOneWidget,
    );
  });

  testWidgets('an UNCONFIGURED account: nothing to warn about — the naming '
      'card states the missing configuration', (tester) async {
    await pumpWarning(tester, _container(() => null));

    expect(
      find.byKey(const Key('ai-preview-decision-model-warning-title')),
      findsNothing,
    );
  });

  testWidgets('a PENDING discovery renders nothing (never a premature claim)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        configuredAiNamingProvider.overrideWith((ref) {
          final Completer<AiConfigView?> never = Completer<AiConfigView?>();
          return never.future;
        }),
      ],
    );
    await pumpWarning(tester, container);

    expect(
      find.byKey(const Key('ai-preview-decision-model-warning-title')),
      findsNothing,
    );
  });

  testWidgets('a FAILED discovery renders nothing: a failed read is not the '
      'fact "no Decision Model is set"', (tester) async {
    final container = ProviderContainer(
      overrides: [
        configuredAiNamingProvider.overrideWith((ref) {
          final Future<AiConfigView?> failed = Future.error(
            StateError('discovery down'),
          );
          return failed;
        }),
      ],
    );
    await pumpWarning(tester, container);
    await tester.pump();

    expect(
      find.byKey(const Key('ai-preview-decision-model-warning-title')),
      findsNothing,
    );
  });
}
