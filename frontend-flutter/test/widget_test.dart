// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';

void main() {
  testWidgets('App renders the Breakdown shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    expect(find.text('Breakdown'), findsWidgets);
  });
}
