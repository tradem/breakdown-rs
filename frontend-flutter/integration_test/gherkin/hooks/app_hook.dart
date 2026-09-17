// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3 (neuralwatt)

import 'dart:io';

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
///
/// The seed is GATED on the costume_assignment.feature promotion state
/// (CodeRabbit review, #456): when its scenarios are `@pending`, the
/// runner excludes them and seeding would only mutate the backend for an
/// unrelated pass — every seed failure would abort the whole run before
/// the first scenario. Parse the feature file directly (the same file the
/// runner reads); a promoted scenario must NOT carry `@pending`.
class AppHook extends Hook {
  /// True when at least one scenario in `costume_assignment.feature` is
  /// free of the `@pending` tag (i.e. promoted into the on-device pass).
  /// Gherkin tags PRECEDE their scenario header, so a pending tag
  /// accumulated before a header attributes to THAT header — a scenario is
  /// promoted exactly when no `@pending` was collected ahead of it.
  /// Best-effort: on any read failure the seed runs (fail-open to the
  /// previous behavior) — the seed itself errors loudly on a broken
  /// backend.
  static bool _costumeScenariosActive() {
    try {
      final running = Platform.environment['GHERKIN_COSTUME_SEED'] ?? 'auto';
      if (running == 'on') return true;
      if (running == 'off') return false;
      final file = File('features-spec/costume_assignment.feature');
      if (!file.existsSync()) return false;
      var pendingTags = 0;
      var promoted = false;
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.startsWith('Scenario:') ||
            trimmed.startsWith('Scenario Outline:')) {
          if (pendingTags == 0) promoted = true;
          pendingTags = 0;
        } else if (trimmed == '@pending') {
          pendingTags++;
        }
      }
      return promoted;
    } on Object {
      return true;
    }
  }

  @override
  int get priority => 10;

  @override
  Future<void> onBeforeRun(TestConfiguration config) async {
    if (!_costumeScenariosActive()) {
      // All costume scenarios are `@pending`: the runner excludes them —
      // skip the seed entirely (repairs the review finding that every
      // unrelated Gherkin run otherwise depended on the seed endpoints).
      return;
    }
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
