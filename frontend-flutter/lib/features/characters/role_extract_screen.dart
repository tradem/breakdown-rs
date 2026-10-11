// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import 'character_detail_screen.dart';

/// `RoleExtractScreen` — the Cast view's deep content for one character
/// (issue #611): the traditional ring binder/Register per role. Every scene
/// the character appears in, in script order, with that character's costume
/// per scene — sourced from the per-character appearances read model.
///
/// **Degraded state (deliberate, no client-side aggregation):** the
/// per-character appearances route (`GET /v1/characters/{id}/appearances`,
/// backend issue #621) does not exist yet. Per the CQRS discipline the client
/// never aggregates projections itself, and fanning out per-scene membership
/// queries is rejected as neither deterministic nor projector-lag-friendly —
/// so until the backend route ships and the Dart client is regenerated, this
/// screen renders the character detail as today (issue #611's list-only
/// fallback: contacts, measurements, category row — the existing
/// `CharacterDetailScreen` content, unchanged).
///
/// The screen exists as its own route seam so the Cast view's entry point is
/// already the extract: a character row tap opens the role extract (never the
/// bare detail). When the backend read model lands, this `build` swaps the
/// pass-through for the extract rows without touching any call site or test
/// key; the detail content remains reachable below the extract as today's
/// degraded sections.
class RoleExtractScreen extends StatelessWidget {
  const RoleExtractScreen({
    super.key,
    required this.season,
    required this.characterId,
  });

  final SeasonView season;
  final String characterId;

  @override
  Widget build(BuildContext context) {
    // TODO(#611): replace the degraded pass-through with the generated
    // appearances read type (scene order + costume per scene) once backend
    // issue #621 ships and the client is regenerated (`regen-client.sh`).
    // Until then: characters detail as today — no client-side fan-out.
    return CharacterDetailScreen(season: season, characterId: characterId);
  }
}
