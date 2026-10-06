// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import 'membership/capability.dart';

/// Shared client-side capability gate mirroring the backend authorization
/// policies (flutter-costume-domains Task 2.1; series-level photo policy
/// since issue #535).
///
/// Every photo upload, bytes fetch and delete — and every costume assign /
/// unassign command — runs a check BEFORE the network call, annotated with
/// a `// AUTHZ-GATE:` comment at the dispatch site. A client-side denial
/// renders a localized 403 narrative and never issues the request (provable
/// in tests by a fake repository call count of zero).
///
/// The server remains authoritative and re-checks authorization on every
/// gated handler — a client `true` is a gate decision only (AGENTS.md §5).
///
/// **Two scopes, two gates (issue #535):**
/// * **Costume photos** (`/costumes/{id}/photos*`) authorize **series-wide**
///   server-side (`has_active_costume_role_in_series`, ADR-035 B2/S2) — the
///   mirror reads the backend-computed series predicate from
///   `SeriesMembershipDto` via [checkCostumePhotoCapability].
/// * **Continuity photos** (scene-shoot bound) stay **season-scoped**
///   server-side (`has_active_costume_role_in_season` via the
///   shooting_day → episode → block → season chain) — the mirror keeps the
///   season DTO via [checkContinuityCapability].
///
/// v1 capability set (season DTO, derived server-side from
/// `has_active_costume_role_in_season`):
/// * `assign_costumes` — costume assign/unassign, scene-character binding.
/// * `upload_continuity_photos` — continuity photos (season-scoped policy
///   mirror, D3).
enum GatedCapability {
  assignCostumes('assign_costumes'),
  uploadPhotos('upload_continuity_photos'),
  importAiDocuments('import_ai_documents');

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
    case GatedCapability.importAiDocuments:
      // `flutter-ai-import` D4: the backend gates schedule/script uploads
      // and the apply command on `authorize_season_result(Action::Write)`
      // in the job's season — the same predicate the capability set derives
      // from (`has_active_costume_role_in_season`). No dedicated wire
      // capability string exists, so the gate reads the backend-computed
      // predicate directly (exactly the `canViewReports` pattern); unknown
      // capability strings never enable it (server authoritative).
      return membership.hasActiveCostumeRoleInSeason
          ? const GateAllow()
          : GateDeny(denyCode);
  }
}

/// Convenience: costume photo upload/bytes/delete gate — **series-scoped**
/// photo policy mirror (issue #535, ADR-035 B2/S2). Reads the
/// backend-computed series predicate directly (exactly the
/// `canViewReports` pattern); a client `true` is a gate decision only, the
/// server re-checks on every gated handler.
GateDecision checkCostumePhotoCapability(SeriesMembershipDto? membership) {
  if (membership == null) return const GateDeny('membership.pending');
  return membership.hasActiveCostumeRoleInSeries
      ? const GateAllow()
      : const GateDeny('photo.forbidden');
}

/// Convenience: **continuity photo** gate (scene-shoot bound) — stays
/// season-scoped (the server's continuity-photo handlers gate on the
/// season predicate via the shooting_day → episode → block → season
/// chain), so the mirror reads the season DTO.
GateDecision checkContinuityCapability(SeasonMembershipDto? membership) =>
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

/// Convenience: AI-import upload/apply gate (season costume-dept membership
/// — the same backend predicate that derives the capability set, D4).
GateDecision checkAiImportCapability(SeasonMembershipDto? membership) =>
    checkCapability(
      membership,
      GatedCapability.importAiDocuments,
      denyCode: 'ai_import.forbidden',
    );
