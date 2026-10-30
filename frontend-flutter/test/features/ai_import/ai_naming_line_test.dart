// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the shared provider/model naming line (issue
// #608, EU AI Act Art. 50 transparency): the configured wire naming, the
// honest unconfigured degradation, and the loading/error states — copy in
// every state, never a spinner trap, never an invented name.
//
// Plus the PROMOTED header card of the preview screen (issue #760): model as
// the primary line, provider as the secondary line, the unchanged Art. 50
// sentence as the caption, and the same honest degradation when there is no
// configuration to promote.

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

/// Pumps [AiNamingCard] inside a fixed-width, scroll-free box so an overflow
/// in the header would fail loudly (issue #760: a curated model id can be
/// long).
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
            child: SizedBox(width: width, child: const AiNamingCard()),
          ),
        ),
      ),
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

  group('AiNamingCard — the promoted preview header (issue #760)', () {
    testWidgets('configured: model primary, provider secondary, the Art. 50 '
        'sentence as the caption', (tester) async {
      await pumpCard(
        tester,
        ProviderContainer(
          overrides: [
            configuredAiNamingProvider.overrideWith(
              (ref) => Future.value(_namingConfig()),
            ),
          ],
        ),
      );

      // It is a CARD, not a bare `bodySmall` line.
      expect(find.byType(Card), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-model')))
            .data,
        'assistant-model-1',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-provider')))
            .data,
        'Provider: openai',
      );
      // The transparency statement is unchanged by the promotion.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        'Currently configured: provider openai, model assistant-model-1.',
      );
    });

    testWidgets('a long model id stays on ONE line and ellipsizes (no '
        'overflow, rows are not pushed off screen)', (tester) async {
      const longModel =
          'anthropic/claude-sonnet-4.6-extended-thinking-preview-2026-01-31';
      await pumpCard(
        tester,
        ProviderContainer(
          overrides: [
            configuredAiNamingProvider.overrideWith(
              (ref) => Future.value(_namingConfig(model: longModel)),
            ),
          ],
        ),
        width: 280,
      );

      final model = tester.widget<Text>(
        find.byKey(const Key('ai-preview-naming-model')),
      );
      expect(model.data, longModel);
      expect(model.maxLines, 1);
      expect(model.overflow, TextOverflow.ellipsis);
      // No RenderFlex overflow was reported while laying the card out.
      expect(tester.takeException(), isNull);
    });

    testWidgets('unconfigured: the honest degradation copy, no invented '
        'model/provider line', (tester) async {
      await pumpCard(
        tester,
        ProviderContainer(
          overrides: [
            configuredAiNamingProvider.overrideWith(
              (ref) => Future.value(null),
            ),
          ],
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        degradedCopy,
      );
      expect(find.byKey(const Key('ai-preview-naming-model')), findsNothing);
      expect(find.byKey(const Key('ai-preview-naming-provider')), findsNothing);
    });

    testWidgets('discovery failure: the same degradation copy (never a '
        'provider/model the app could not read)', (tester) async {
      await pumpCard(
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

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        degradedCopy,
      );
      expect(find.byKey(const Key('ai-preview-naming-model')), findsNothing);
    });

    testWidgets('loading: the honest loading note instead of an empty header', (
      tester,
    ) async {
      await pumpCard(
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

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-preview-naming-disclosure')))
            .data,
        loadingCopy,
      );
    });
  });
}
