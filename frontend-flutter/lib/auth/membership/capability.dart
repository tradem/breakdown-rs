// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

/// The set of membership capabilities the client understands for the
/// AUTHZ-GATE (D2 of `wire-flutter-oidc-auth`).
///
/// The backend derives `capabilities` server-side from the caller's active
/// costume-dept role and emits them as snake_case wire strings
/// (`backend/openapi.yaml` declares `SeasonMembershipDto.capabilities` as
/// `items: string`, so the generated [SeasonMembershipDto] carries a plain
/// `BuiltList<String>`). The client consumes the known set only.
///
/// The wire contract is additive: a newer backend may emit capabilities this
/// client does not know. Unknown entries are tolerated — they are stored on
/// the generated DTO but never enable a known gate. The server remains
/// authoritative and re-checks authorization on every gated handler.
enum Capability {
  uploadContinuityPhotos('upload_continuity_photos'),
  assignCostumes('assign_costumes');

  const Capability(this.wireName);

  /// The backend's snake_case enum value on the wire.
  final String wireName;

  /// Parses a wire string to a known capability, or `null` if unknown.
  static Capability? tryParse(String wireName) {
    for (final c in Capability.values) {
      if (c.wireName == wireName) return c;
    }
    return null;
  }
}

/// AUTHZ-GATE capability accessors on the generated [SeasonMembershipDto].
///
/// The generated DTO stores `capabilities` as a plain `BuiltList<String>`;
/// these getters map the server-derived wire strings to the gate decisions the
/// UI branches on (`canUploadContinuityPhotos` / `canAssignCostumes`). A client
/// `true` is a gate decision only — the backend re-checks authorization on
/// every gated handler (server authoritative, AGENTS.md §5).
extension SeasonMembershipDtoGate on SeasonMembershipDto {
  /// True when the server-derived capability list includes
  /// `upload_continuity_photos`.
  bool get canUploadContinuityPhotos =>
      capabilities.contains(Capability.uploadContinuityPhotos.wireName);

  /// True when the server-derived capability list includes `assign_costumes`.
  bool get canAssignCostumes =>
      capabilities.contains(Capability.assignCostumes.wireName);
}
