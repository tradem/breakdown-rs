// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:frontend_flutter/src/connectivity/connectivity_providers.dart';

/// Test-double passive connectivity source (issue #654): never emits — the
/// [ConnectivityController] stays optimistically online and the shell keeps
/// its pill-free layout. Hand this to
/// `passiveConnectivitySourceProvider.overrideWithValue` in every harness
/// that pumps the shell, so the real connectivity_plus platform channel is
/// never activated in the widget-test environment (its activation error is
/// reported via `FlutterError` and would fail tests/goldens).
class SilentPassiveSource implements PassiveConnectivitySource {
  const SilentPassiveSource();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
}
