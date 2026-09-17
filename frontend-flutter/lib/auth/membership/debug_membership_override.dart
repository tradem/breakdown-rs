// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

/// Test-support override of the DEV-auth membership (issue #368).
///
/// The on-device Gherkin runner builds the instrumented app ONCE with fixed
/// dart-defines; `restartAppBetweenScenarios` relaunches the same binary, so
/// a per-scenario membership shape (permissive costume-dept vs. capability-less
/// viewer) cannot be expressed as a compile-time define. The override rides
/// the FlutterDriver data channel instead: the runner-side
/// `I am authenticated as a "{string}" user` step sends
/// `dev-membership:role=<role>` to the instrumented app
/// (`integration_test/gherkin/app.dart`), which calls
/// [DebugMembershipOverride.set]. `membershipFetchProvider` consults the
/// override in dev-auth mode only.
///
/// Production can never reach this: the handler is registered ONLY by the
/// instrumented Gherkin target (`main.dart` does not), the field is
/// `@visibleForTesting`, and the provider branch is gated behind
/// `AppConfig.devAuthMode` (dev flavor, no `OIDC_ISS`, `DEV_AUTH_SUB` set) —
/// structurally unreachable in prod (membership_providers.dart, Task 5.1
/// guard).
///
/// Pure Dart only (no Flutter imports): the gherkin runner host process
/// compiles the step definitions headlessly, where `dart:ui` is unavailable —
/// `package:meta`'s `visibleForTesting` annotation is the Flutter-free
/// equivalent of the foundation one.
library;

import 'package:meta/meta.dart' show visibleForTesting;

abstract final class DebugMembershipOverride {
  /// The overridden dev-auth role, or `null` for the default permissive
  /// costume-dept membership.
  @visibleForTesting
  static String? role;

  /// Sets the role override from the driver data channel (`<role>` or the
  /// empty string to reset to the default permissive membership). Returns the
  /// applied role as the channel response.
  static String set(String role) {
    DebugMembershipOverride.role = role.isEmpty ? null : role;
    return DebugMembershipOverride.role ?? '';
  }

  /// True when the current override denies the costume-dept membership
  /// (capability-less viewer). Unknown role strings deny fail-closed — an
  /// unrecognized harness value must never hand out capabilities. An
  /// explicitly set `costume_dept` stays permissive (CodeRabbit review,
  /// #456: the driver handler accepts the role, so a valid
  /// `dev-membership:role=costume_dept` command must never produce the
  /// viewer membership).
  static bool get deniesAll => role != null && role != DevAuthRole.costumeDept;
}

/// The dev-auth roles the Gherkin harness uses (issue #368).
abstract final class DevAuthRole {
  const DevAuthRole._();

  /// Seeded costume-dept principal — permissive membership (default).
  static const costumeDept = 'costume_dept';

  /// Capability-less viewer — client-side AUTHZ-GATE denies every gated
  /// action before any network call.
  static const viewer = 'viewer';

  /// True for a known role name (harness input validation).
  static bool isKnown(String role) => role == costumeDept || role == viewer;
}
