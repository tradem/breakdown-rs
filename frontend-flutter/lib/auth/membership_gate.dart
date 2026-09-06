// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import 'membership/capability.dart';

/// Shared client-side capability gate mirroring the season-scoped photo
/// policy (flutter-costume-domains Task 2.1).
///
/// Every photo upload, bytes fetch and delete — and every costume assign /
/// unassign command — runs [checkCapability] BEFORE the network call,
/// annotated with a `// AUTHZ-GATE:` comment at the dispatch site. A
/// client-side denial renders a localized 403 narrative and never issues
/// the request (provable in tests by a fake repository call count of zero).
///
/// The server remains authoritative and re-checks authorization on every
/// gated handler — a client `true` is a gate decision only (AGENTS.md §5).
///
/// v1 capability set (both derived server-side from
/// `has_active_costume_role_in_season`):
/// * `assign_costumes` — costume assign/unassign, scene-character binding.
/// * `upload_continuity_photos` — photo upload/bytes/delete (season-scoped
///   photo policy mirror, D3).
enum GatedCapability {
  assignCostumes('assign_costumes'),
  uploadPhotos('upload_continuity_photos');

  const GatedCapability(this.wireName);

  final String wireName;
}

/// Result of [checkCapability]: allow, or deny with the stable problem `code`
/// the UI localizes (never the `detail` text).
sealed class GateDecision {
  const GateDecision();
}

class GateAllow extends GateDecision {
  const GateAllow();
}

class GateDeny extends GateDecision {
  const GateDeny(this.code);

  /// Stable problem `code` (e.g. `costume.forbidden`, `photo.forbidden`).
  final String code;
}

/// Checks whether [membership] grants [capability].
///
/// * Unknown capabilities in the wire set are tolerated (stored on the DTO
///   but never enable a known gate — inherited strict parsing from Phase 1).
/// * A `null` membership (still loading / fetch error) is NOT a resolved
///   denial — callers disable with spinner/retry, never the 403 narrative.
GateDecision checkCapability(
  SeasonMembershipDto? membership,
  GatedCapability capability, {
  String denyCode = 'costume.forbidden',
}) {
  if (membership == null) return const GateDeny('membership.pending');
  final wire = membership.capabilities.toList();
  switch (capability) {
    case GatedCapability.assignCostumes:
      return wire.contains(Capability.assignCostumes.wireName)
          ? const GateAllow()
          : GateDeny(denyCode);
    case GatedCapability.uploadPhotos:
      return wire.contains(Capability.uploadContinuityPhotos.wireName)
          ? const GateAllow()
          : GateDeny(denyCode);
  }
}

/// Convenience: photo upload/bytes/delete gate (season-scoped photo policy).
GateDecision checkPhotoCapability(SeasonMembershipDto? membership) =>
    checkCapability(
      membership,
      GatedCapability.uploadPhotos,
      denyCode: 'photo.forbidden',
    );

/// Convenience: costume assign/unassign + scene-character binding gate.
GateDecision checkAssignCapability(SeasonMembershipDto? membership) =>
    checkCapability(
      membership,
      GatedCapability.assignCostumes,
      denyCode: 'costume.forbidden',
    );
