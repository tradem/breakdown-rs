// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_driver/driver_extension.dart';
import 'package:frontend_flutter/app.dart' show bootstrap;
import 'package:frontend_flutter/app_config.dart';

/// Instrumented entrypoint for the on-device `flutter_gherkin` runner.
///
/// `enableFlutterDriverExtension()` MUST be called before the app starts so
/// the driver can connect and drive the real, built app on a device/emulator
/// (AGENTS.md §6 — Gherkin steps run on device, not as headless pure-function
/// tests). The runner (`gherkin_runner.dart`) launches this target, builds it
/// in dev-auth mode (see `configuration.dart` `dartDefineArgs`), and drives it.
Future<void> main() async {
  // Enables automation. Required before runApp.
  enableFlutterDriverExtension();

  // dev flavor → the runner's DEV_AUTH_SUB dart-define treats the dummy user
  // as authenticated; the real app composition root is used unchanged.
  // Await bootstrap so startup failures surface through the entrypoint
  // (Future<void>) instead of being dropped.
  await bootstrap(Flavor.dev);
}
