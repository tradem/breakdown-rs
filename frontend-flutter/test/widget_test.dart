// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/app_config.dart';

void main() {
  testWidgets('App renders the Breakdown shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: App(config: AppConfig.fromEnvironment(Flavor.dev))),
    );
    expect(find.text('Breakdown'), findsWidgets);
  });
}
