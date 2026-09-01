// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';

void main() {
  testWidgets('App renders the SeasonsScreen reference shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    // Home is the first screen (first-screen-seasons); without composition
    // overrides it renders the empty projection shell, not a crash.
    expect(find.text('Seasons'), findsOneWidget);
  });
}
