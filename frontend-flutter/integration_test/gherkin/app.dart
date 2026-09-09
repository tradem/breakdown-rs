// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter_driver/driver_extension.dart';
import 'package:frontend_flutter/app.dart' show bootstrap;
import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/src/network/api_client.dart'
    show debugDioInterceptors;
import 'package:frontend_flutter/testing/request_recorder.dart';

/// Instrumented entrypoint for the on-device `flutter_gherkin` runner.
///
/// `enableFlutterDriverExtension()` MUST be called before the app starts so
/// the driver can connect and drive the real, built app on a device/emulator
/// (AGENTS.md §6 — Gherkin steps run on device, not as headless pure-function
/// tests). The runner (`gherkin_runner.dart`) launches this target, builds it
/// in dev-auth mode (see `configuration.dart` `dartDefineArgs`), and drives it.
///
/// This is the ONLY target that registers the request recorder (issue #380):
/// the interceptor is appended to every `buildPinnedDio`-built Dio via
/// `debugDioInterceptors`, so it observes the bootstrap client AND every
/// later `apiDioProvider` rebuild. `main.dart` never registers it — the
/// recorder cannot ship in a production build. The host-side runner reads
/// the counters over the FlutterDriver data channel (`driver.requestData`)
/// because runner and app run in separate processes.
Future<void> main() async {
  // Register the recorder BEFORE bootstrap: Dio instances are built inside
  // `bootstrap()` (and later by `apiDioProvider` rebuilds) and pick the
  // interceptor up from the seam at construction time.
  debugDioInterceptors = [RequestRecorderInterceptor()];

  // Enables automation. Required before runApp.
  enableFlutterDriverExtension(
    handler: (message) async {
      // Recorder protocol for the host-side steps: a compact count snapshot
      // or a reset (defensive — the app restart per scenario already zeroes
      // the recorder with its isolate).
      switch (message) {
        case 'request-recorder:snapshot':
          return RequestRecorder.snapshot();
        case 'request-recorder:reset':
          RequestRecorder.reset();
          return 'ok';
        default:
          return 'unknown-command';
      }
    },
  );

  // dev flavor → the runner's DEV_AUTH_SUB dart-define treats the dummy user
  // as authenticated; the real app composition root is used unchanged.
  // Await bootstrap so startup failures surface through the entrypoint
  // (Future<void>) instead of being dropped.
  await bootstrap(Flavor.dev);
}
