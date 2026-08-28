// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Root widget. Riverpod is the sole composition mechanism (AGENTS.md §1, D3);
/// widgets render and dispatch, they never branch on domain semantics.
///
/// The HTTP client is constructed from the flavor config and will later be
/// exposed through a Riverpod provider; it is intentionally not stateful here.
class App extends StatelessWidget {
  const App({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breakdown',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Breakdown')),
        body: const Center(child: Text('Breakdown')),
      ),
    );
  }
}

/// Composition root: wraps the app in [ProviderScope] and applies the resolved
/// [AppConfig]. Called from the per-flavor entrypoints.
void bootstrap(Flavor flavor) {
  runApp(ProviderScope(child: App(config: AppConfig.fromEnvironment(flavor))));
}
