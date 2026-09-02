// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:gherkin/gherkin.dart';

/// Lifecycle hook for the on-device Gherkin run.
///
/// Runs on a device as part of the flutter_gherkin driver session (never as a
/// pure-function unit test). Hooks are the place for cross-scenario setup such
/// as resetting the network recorder or seeding a dev membership; the bodies
/// below are intentionally minimal and only log, because the acceptance state
/// is established through the real app UI / HTTP path, not local stubs.
class AppHook extends Hook {
  @override
  int get priority => 10;

  @override
  Future<void> onBeforeRun(TestConfiguration config) async {
    // No-op: the runner launches the instrumented app once.
  }

  @override
  Future<void> onAfterRun(TestConfiguration config) async {
    // No-op.
  }

  @override
  Future<void> onBeforeScenario(
    TestConfiguration config,
    String scenario,
    Iterable<Tag> tags,
  ) async {
    // TODO(screen): when a network recorder is injected into the app build,
    // reset `world.requestsLeftDevice` here so each scenario starts clean.
  }

  @override
  Future<void> onAfterScenario(
    TestConfiguration config,
    String scenario,
    Iterable<Tag> tags,
  ) async {
    // No-op.
  }
}
