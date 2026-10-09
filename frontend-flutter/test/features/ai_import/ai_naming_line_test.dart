// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for the shared provider/model naming line (issue
// #608, EU AI Act Art. 50 transparency): the configured wire naming, the
// honest unconfigured degradation, and the loading/error states — copy in
// every state, never a spinner trap, never an invented name.

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/features/ai_import/naming_line.dart';

AiConfigView _namingConfig({
  LlmProvider provider = LlmProvider.openai,
  String model = 'assistant-model-1',
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
    ..version = 1,
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
      'AI processing with provider openai, model assistant-model-1.',
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
}
