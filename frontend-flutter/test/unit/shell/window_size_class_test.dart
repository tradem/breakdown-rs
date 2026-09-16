// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:test/test.dart';

import 'package:frontend_flutter/features/shell/window_size_class.dart';

void main() {
  group('resolveWindowSizeClass (M3 canonical breakpoints 600/840)', () {
    test('below 600dp is compact', () {
      expect(resolveWindowSizeClass(0), WindowSizeClass.compact);
      expect(resolveWindowSizeClass(360), WindowSizeClass.compact);
      expect(resolveWindowSizeClass(599.99), WindowSizeClass.compact);
    });

    test('600dp boundary starts medium (rail)', () {
      expect(resolveWindowSizeClass(600), WindowSizeClass.medium);
      expect(resolveWindowSizeClass(700), WindowSizeClass.medium);
      expect(resolveWindowSizeClass(839.99), WindowSizeClass.medium);
    });

    test('840dp boundary starts expanded (drawer)', () {
      expect(resolveWindowSizeClass(840), WindowSizeClass.expanded);
      expect(resolveWindowSizeClass(1000), WindowSizeClass.expanded);
    });
  });
}
