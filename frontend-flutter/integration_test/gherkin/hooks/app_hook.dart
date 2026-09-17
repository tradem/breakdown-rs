// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

import 'package:gherkin/gherkin.dart';

import '../steps/seed_http.dart';

/// Lifecycle hook for the on-device Gherkin run.
///
/// Runs on a device as part of the flutter_gherkin driver session (never as
/// a pure-function unit test). Hooks are the place for cross-scenario setup
/// such as resetting the network recorder or seeding the dev backend.
///
/// The costume-assignment seed (issue #368) runs in `onBeforeRun` — BEFORE
/// the first app launch: the app then boots with the seeded aggregates
/// already projected (its boot-time seasons fetch includes the seeded
/// season — no read-model refresh race), and both costume scenarios share
/// the state (the viewer denial fires client-side before any network call).
/// The scenario Given steps copy the ids from [SeedCache] into
/// `AppWorld.seedIds`.
class AppHook extends Hook {
  @override
  int get priority => 10;

  @override
  Future<void> onBeforeRun(TestConfiguration config) async {
    SeedCache.costumeAssignmentIds = await seedCostumeAssignment();
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
    // No reset needed: the app restarts per scenario
    // (`restartAppBetweenScenarios`), so the in-app request recorder
    // (issue #380, read via the FlutterDriver data channel) starts at zero
    // with the fresh app isolate.
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
