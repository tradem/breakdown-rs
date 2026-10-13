// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Widget tests for the shell quick-create sheet (issue #612): the sheet
// lists its v1 entries with VISIBLE labels (glossary rule), the tap
// mechanic pops the sheet and pushes the entry's flow on the ROOT
// navigator, and the shipped affordance list wires the AI-import /
// setup-wizard routes (the expensive flows are asserted by TYPE here —
// they pump in their own feature test suites).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/scenes/create_scene_screen.dart';
import 'package:frontend_flutter/features/seasons/setup/setup_wizard_screen.dart';
import 'package:frontend_flutter/features/shooting_days/create_shooting_day_screen.dart';
import 'package:frontend_flutter/features/shell/quick_create_sheet.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';

/// Bounded frame pump (deterministic-tests rule — no pumpAndSettle while
/// sheet animations may run, no wall-clock budgets).
Future<void> pumpFrames(WidgetTester tester, {int n = 12}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A stub flow screen the fake action pushes (proves the entry ROUTED to
/// a pushed route — the sheet deep-links, never embeds).
class _StubFlowScreen extends StatelessWidget {
  const _StubFlowScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: const Center(child: Text('stub-flow')));
}

Future<void> pumpHarness(
  WidgetTester tester, {
  required List<QuickCreateAction> actions,
  GlobalKey<NavigatorState>? rootNavigatorKey,
  GlobalKey<NavigatorState>? nestedNavigatorKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        // A nested navigator below the ROOT navigator mirrors the shell
        // structure: the assertion “the entry PUSHED on the ROOT navigator,
        // never the nested one” can only be made by inspecting both stacks.
        home: Navigator(
          key: nestedNavigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => FilledButton(
                    key: const Key('harness-open-sheet'),
                    onPressed: () =>
                        showQuickCreateSheet(context, actions: actions),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await pumpFrames(tester, n: 2);
}

void main() {
  group('quick-create affordance list (wiring, issue #612)', () {
    test('v1 list routes AI import and setup wizard as PUSHED flows', () {
      final actions = shellQuickCreateActions(AppLocalizationsDe());
      expect(actions, hasLength(2));
      // AI import entry: the existing submit flow (which gates inside its
      // controller BEFORE any network call — the AUTHZ-GATE comment
      // travels with the screen).
      expect(actions[0].routeBuilder(), isA<AiImportSubmitScreen>());
      // Wizard entry: the guided season setup as a full-screen route.
      expect(actions[1].routeBuilder(), isA<SetupWizardScreen>());
      // Entries carry test keys and a VISIBLE label + subtitle each
      // (glossary rule — the icon never carries the meaning alone).
      for (final action in actions) {
        expect(action.key, isNotNull);
        expect(action.title, isNotEmpty);
        expect(action.subtitle, isNotEmpty);
      }
    });
  });

  group('sheet mechanics', () {
    testWidgets('opens listing the real v1 entries with visible labels', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        actions: shellQuickCreateActions(AppLocalizationsDe()),
      );
      await tester.tap(find.byKey(const Key('harness-open-sheet')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('shell-quick-create-sheet')), findsOneWidget);
      expect(find.byKey(const Key('quick-create-ai-import')), findsOneWidget);
      expect(find.byKey(const Key('quick-create-wizard')), findsOneWidget);
      // Visible labels (German template suite) — the icon never carries
      // the meaning alone.
      expect(find.text('Import'), findsOneWidget);
      expect(find.text('Season-Setup'), findsOneWidget);
      expect(find.text('Was möchtest du erstellen?'), findsOneWidget);
    });

    testWidgets('tap pops the sheet and pushes the flow on the navigator', (
      tester,
    ) async {
      final rootNavigatorKey = GlobalKey<NavigatorState>();
      final nestedNavigatorKey = GlobalKey<NavigatorState>();
      await pumpHarness(
        tester,
        rootNavigatorKey: rootNavigatorKey,
        nestedNavigatorKey: nestedNavigatorKey,
        actions: const [
          QuickCreateAction(
            key: Key('quick-create-stub'),
            icon: Icons.add,
            title: 'Eintrag',
            subtitle: 'Beschreibung',
            routeBuilder: _StubFlowScreen.new,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('harness-open-sheet')));
      await pumpFrames(tester);
      expect(find.byKey(const Key('shell-quick-create-sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick-create-stub')));
      await pumpFrames(tester);

      // The sheet is GONE and the chosen flow replaced it (push, not
      // embed — the stub screen is visible, the sheet no longer is).
      expect(find.text('Eintrag'), findsNothing);
      expect(find.text('stub-flow'), findsOneWidget);

      // CodeRabbit review #623: the sheet lives on the ROOT navigator
      // (useRootNavigator), so the pushed flow must change the ROOT stack
      // — the nested navigator (the shell-tab analog) stays untouched.
      expect(rootNavigatorKey.currentState!.canPop(), isTrue);
      expect(nestedNavigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('dismiss restores the previous surface untouched', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        actions: const [
          QuickCreateAction(
            key: Key('quick-create-stub'),
            icon: Icons.add,
            title: 'Eintrag',
            subtitle: 'Beschreibung',
            routeBuilder: _StubFlowScreen.new,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('harness-open-sheet')));
      await pumpFrames(tester);
      // Swipe-dismiss the sheet.
      await tester.drag(
        find.byKey(const Key('shell-quick-create-sheet')),
        const Offset(0, 400),
      );
      await pumpFrames(tester);
      expect(find.byKey(const Key('shell-quick-create-sheet')), findsNothing);
      // The harness surface is still the root route (nothing pushed).
      expect(find.text('open'), findsOneWidget);
      expect(find.text('stub-flow'), findsNothing);
    });
  });

  group('context-sensitive entries (issue #624)', () {
    const scope = ActiveEpisodeScope(
      seasonId: 'season-1',
      blockId: 'block-1',
      episodeId: 'episode-1',
      episodeNumber: 3,
      episodeName: 'Pilot',
    );

    test('no scope keeps the shipped context-free list', () {
      final actions = shellQuickCreateActions(AppLocalizationsDe());
      expect(actions, hasLength(2));
      expect(actions[0].routeBuilder(), isA<AiImportSubmitScreen>());
      expect(actions[1].routeBuilder(), isA<SetupWizardScreen>());
    });

    test('a scope adds scene/day entries for that episode, additively', () {
      final actions = shellQuickCreateActions(
        AppLocalizationsDe(),
        episode: scope,
      );
      expect(actions, hasLength(4));
      // Context entries first (the immediate task), the context-free pair
      // still present.
      expect(actions[0].routeBuilder(), isA<CreateSceneScreen>());
      expect(actions[1].routeBuilder(), isA<CreateShootingDayScreen>());
      expect(actions[2].routeBuilder(), isA<AiImportSubmitScreen>());
      expect(actions[3].routeBuilder(), isA<SetupWizardScreen>());
      // The context pages carry the scoped episode id.
      expect(
        (actions[0].routeBuilder() as CreateSceneScreen).episodeId,
        'episode-1',
      );
      expect(
        (actions[1].routeBuilder() as CreateShootingDayScreen).episodeId,
        'episode-1',
      );
      for (final action in actions) {
        expect(action.title, isNotEmpty);
        expect(action.subtitle, isNotEmpty);
      }
    });

    testWidgets('the sheet lists the context entries with visible labels', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        actions: shellQuickCreateActions(AppLocalizationsDe(), episode: scope),
      );
      await tester.tap(find.byKey(const Key('harness-open-sheet')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('quick-create-scene')), findsOneWidget);
      expect(
        find.byKey(const Key('quick-create-shooting-day')),
        findsOneWidget,
      );
      expect(find.text('Neue Szene'), findsOneWidget);
      expect(find.text('Neuer Drehtag'), findsOneWidget);
      // The context-free entries remain.
      expect(find.byKey(const Key('quick-create-ai-import')), findsOneWidget);
      expect(find.byKey(const Key('quick-create-wizard')), findsOneWidget);
    });
  });
}
