// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 tests for the shared plus-action affordance (issues #612/#823).
//
// The component exists so the two surfaces that render the plus action (the
// Script destination's shell FAB and the AI-import jobs screen's Import
// action) cannot drift in their accessible contract — and so the hero-tag
// rule is stated once: a FAB's default hero tag is ONE shared const across
// every FAB, so two mounted plus actions would collide as soon as a
// root-navigator page transition collects heroes from both subtrees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/components/plus_action_fab.dart';

/// Bounded frame pump (deterministic-tests rule — no `pumpAndSettle`, no
/// wall-clock budgets).
Future<void> pumpFrames(
  WidgetTester tester, {
  int n = 12,
  int stepMs = 16,
}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

void main() {
  testWidgets('carries the button role, the visible label and its key as the '
      'hero tag', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: PlusActionFab(
            fabKey: const Key('probe-plus-fab'),
            label: 'Erstellen',
            onPressed: () {},
          ),
        ),
      ),
    );
    await pumpFrames(tester);

    // Icon-only affordances are forbidden: the visible label carries the
    // meaning, the plus glyph reinforces it.
    expect(find.text('Erstellen'), findsOneWidget);
    expect(
      find.semantics.byPredicate(
        (n) => n.label == 'Erstellen' && n.flagsCollection.isButton,
      ),
      findsOneWidget,
    );
    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('probe-plus-fab')),
    );
    // The key doubles as the hero tag: distinct per surface by construction.
    expect(fab.heroTag, const Key('probe-plus-fab'));
    semantics.dispose();
  });

  testWidgets('two plus actions inside one root-route subtree do not share a '
      'hero tag (no duplicate-tag assertion on a root-navigator push)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The shell's FAB (issue #823): it lives in the ROOT route's
          // subtree, on the Script destination.
          floatingActionButton: PlusActionFab(
            fabKey: const Key('outer-plus-fab'),
            label: 'Erstellen',
            onPressed: () {},
          ),
          // A surface pushed INTO a destination's nested navigator (the
          // AI-import jobs screen, #823): its FAB hangs off a nested
          // Navigator whose current route is a PageRoute.
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (nestedContext) => Scaffold(
                floatingActionButton: PlusActionFab(
                  fabKey: const Key('inner-plus-fab'),
                  label: 'Import',
                  onPressed: () {},
                ),
                body: Center(
                  child: TextButton(
                    // The quick-create sheet's push semantics: the root
                    // navigator, so the flow covers the shell.
                    onPressed: () =>
                        Navigator.of(nestedContext, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const Scaffold(body: Text('pushed')),
                          ),
                        ),
                    child: const Text('push-root'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);

    final outer = tester.widget<FloatingActionButton>(
      find.byKey(const Key('outer-plus-fab')),
    );
    final inner = tester.widget<FloatingActionButton>(
      find.byKey(const Key('inner-plus-fab')),
    );
    expect(outer.heroTag, const Key('outer-plus-fab'));
    expect(inner.heroTag, const Key('inner-plus-fab'));
    expect(outer.heroTag, isNot(inner.heroTag));

    // Both FABs are mounted while the transition runs; with the default
    // `_DefaultHeroTag` this push (and the pop back) throws "There are
    // multiple heroes that share the same tag within a subtree".
    await tester.tap(find.text('push-root'));
    await pumpFrames(tester, n: 20, stepMs: 30);
    expect(tester.takeException(), isNull);
    expect(find.text('pushed'), findsOneWidget);
  });
}
