// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
//Co-authored-by: glm-5.3 (neuralwatt)

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

  /// Count of AUTHZ-GATED photo-pipeline HTTP requests (`/photos`,
  /// `/continuity-photos` — upload, bytes, delete, link) that left the
  /// device, populated by the `no network request leaves the device` step
  /// from the in-app Dio recorder (issue #380) over the FlutterDriver data
  /// channel. The runner and app run in separate processes, so the step
  /// fetches the count via `driver.requestData` — it is never written
  /// in-process. Used by the AUTHZ-GATE preflight assertion; navigation
  /// read-model fetches are legitimate traffic and stay out of this count.
  int requestsLeftDevice = 0;

  /// IDs from the most recent assign action, so assertion steps can build the
  /// per-assignment widget keys (`overlay-assign-<costume>-<character>` and
  /// `assigned-<costume>-<character>`).
  String? lastCostumeId;
  String? lastCharacterId;

  /// Real backend ids resolved by the host-side seeding step (issue #368):
  /// the symbolic ids in `costume_assignment.feature` (season "1", costume
  /// "c-7", character "ch-3") map to the freshly created aggregates. The
  /// navigation/assign/assertion steps translate symbolic → real ids through
  /// this map (symbolic season key → real season id; costume/character keys
  /// likewise).
  final Map<String, String> seedIds = {};

  /// Free SERIES-scoped season number resolved host-side by the wizard
  /// harness (season_wizard_steps.dart): the feature's symbolic season
  /// number "1" maps here before entering the wizard's number field (the
  /// dev series accumulates seasons across runs — the dispatch 409s on a
  /// taken number). `null` = use the literal feature number.
  int? wizardFreeSeasonNumber;

  /// Intent flag recorded by the season-setup-wizard steps: the scenario
  /// arranged the dev backend to reject the first block create, so the
  /// wizard must stop with the partial-failure surface.
  bool wizardExpectsPartialFailure = false;

  @override
  void dispose() {
    currentRole = null;
    requestsLeftDevice = 0;
    lastCostumeId = null;
    lastCharacterId = null;
    seedIds.clear();
    wizardFreeSeasonNumber = null;
    wizardExpectsPartialFailure = false;
    super.dispose();
  }
}
