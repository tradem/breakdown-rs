// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:gherkin/gherkin.dart';

import 'configuration.dart';

/// On-device `flutter_gherkin` runner entrypoint for the critical acceptance
/// scenarios under `features-spec/`.
///
/// Run via `dart integration_test/gherkin/gherkin_runner.dart`
/// (see `tool/run_gherkin.sh`). The runner builds and installs the
/// instrumented app on a connected device/emulator and drives it through the
/// Flutter Driver extension — it is NOT a headless pure-Dart run
/// (AGENTS.md §6: Gherkin steps run on device).
Future<void> main() async {
  final config = await buildGherkinConfig();
  await GherkinRunner().execute(config);
}
