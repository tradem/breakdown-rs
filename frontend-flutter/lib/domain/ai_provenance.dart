// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:one_of/one_of.dart';

/// Pure, Flutter-free parsing of the generated provenance discriminators
/// (EU AI Act transparency, issue #538). `SceneView.source_` and
/// `ShootingDayView.source_` serialize as an externally-tagged enum behind
/// the generated `OneOf<String, …OneOf>` machinery; every read surface
/// branches on the parsed variant below instead of poking the oneOf itself
/// (widgets render and dispatch, never branch on wire machinery).
///
/// Parsing never throws: an unrecognized future wire variant degrades to
/// [AiProvenanceVariant.unrecognized] (honest degradation, no invented
/// attribution in either direction) instead of rejecting the read DTO.

/// How an aggregate came into existence, as the client can honestly tell.
enum AiProvenanceVariant {
  /// No discriminator on the wire (`SceneView.source = null`, legacy rows).
  absent,

  /// `Some(Manual)` — the user-created REST path.
  manual,

  /// `Some(AiExtracted)` — created by the AI script/schedule import.
  aiExtracted,

  /// `Some(<future wire variant>)` — recognized shape, unknown variant.
  /// Rendered without any badge (no invented attribution).
  unrecognized,
}

/// Optional detail data carried by `AiExtracted` provenance (`document_id`,
/// `external_ref`, `confidence`). `confidence` is genuinely nullable on the
/// wire — `null` means the pipeline measured no real per-row confidence
/// (issue #517's honest-null rule), never a fabricated placeholder.
typedef AiExtractionDetail = ({
  String documentId,
  String? externalRef,
  double? confidence,
});

/// Parses a nullable scene provenance wire value.
AiProvenanceVariant sceneProvenance(SceneSource? source) =>
    source == null ? AiProvenanceVariant.absent : provenanceOf(source.oneOf);

/// Parses a nullable shooting-day provenance wire value (the day read model
/// carries source non-null, but the legacy-tolerant `null` arm never
/// hurts — absent reads as "no invented attribution").
AiProvenanceVariant dayProvenance(ShootingDaySource? source) =>
    source == null ? AiProvenanceVariant.absent : provenanceOf(source.oneOf);

/// Which `OneOf` arm the generated externally-tagged enum resolved to.
AiProvenanceVariant provenanceOf(OneOf oneOf) => switch (oneOf.value) {
  null => AiProvenanceVariant.absent,
  'Manual' => AiProvenanceVariant.manual,
  // Both generated source wrappers route the externally-tagged object arm
  // through `SceneSourceOneOf` (the shooting-day wrapper reuses it).
  _ when oneOf.valueType == SceneSourceOneOf => AiProvenanceVariant.aiExtracted,
  _ => AiProvenanceVariant.unrecognized,
};

/// The `AiExtracted` detail data (documentId / externalRef / confidence) or
/// `null` when [variant] is not [AiProvenanceVariant.aiExtracted].
AiExtractionDetail? extractionDetailOf(OneOf oneOf) {
  final Object? value = oneOf.value;
  if (value is SceneSourceOneOf) {
    return (
      documentId: value.aiExtracted.documentId,
      externalRef: value.aiExtracted.externalRef,
      confidence: value.aiExtracted.confidence,
    );
  }
  return null;
}

/// Shared badge copy resolution: every provenance-badge surface renders ONE
/// localized badge string when the row is AI-derived, nothing otherwise
/// (`null` = no badge element, never an empty-text arrow).
String? badgeCopyOf(
  AiProvenanceVariant variant,
  String Function() aiExtracted,
) => switch (variant) {
  AiProvenanceVariant.aiExtracted => aiExtracted(),
  _ => null,
};

/// Convenience for the read surfaces: true only when the day is AI-derived
/// (used to grow the badge element; `Manual`/`absent`/`unrecognized` never
/// render a badge — issue #538 "no false attribution in either direction").
bool isAiDerived(AiProvenanceVariant variant) =>
    variant == AiProvenanceVariant.aiExtracted;
