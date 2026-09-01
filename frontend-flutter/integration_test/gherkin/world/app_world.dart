// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:flutter_gherkin/flutter_gherkin.dart';

/// Per-scenario shared state for the on-device Gherkin run.
///
/// `flutter_gherkin` always constructs a `FlutterWorld` (with the connected
/// `driver`); this subclass merely carries a little scenario context the step
/// definitions need (the auth role asserted by `I am authenticated as a
/// {string} user`, and a recording slot for the network interceptor used by
/// the AUTHZ-GATE preflight assertion). It holds NO domain logic and never
/// calls a pure function to satisfy an assertion.
class AppWorld extends FlutterWorld {
  /// The role asserted by the `I am authenticated as a {string} user` step.
  /// The authoritative membership/capabilities are still derived server-side;
  /// this only records the intent for downstream AUTHZ-GATE assertions.
  String? currentRole;

  /// Count of HTTP requests that left the device during the scenario, recorded
  /// by a Dio interceptor injected into the running app. Used by the
  /// `no network request leaves the device` step (AUTHZ-GATE preflight).
  int requestsLeftDevice = 0;

  @override
  void dispose() {
    currentRole = null;
    requestsLeftDevice = 0;
    super.dispose();
  }
}
