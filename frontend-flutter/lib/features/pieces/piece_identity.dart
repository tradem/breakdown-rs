// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

/// The user-facing identity fields derived from a piece projection.
///
/// A piece has no wire-level name. The first detail's `subject` is the
/// de-facto designation; `notes` are a deliberate fallback, never a UUID.
class PieceTileIdentity {
  const PieceTileIdentity({
    required this.subject,
    required this.text,
    required this.categoryName,
    required this.photo,
  });

  final String? subject;
  final String text;
  final String? categoryName;
  final PiecePhotoView? photo;
}

PieceTileIdentity pieceTileIdentity(PieceView piece) {
  final detail = piece.details.isEmpty ? null : piece.details.first;
  PiecePhotoView? thumbnail;
  for (final photo in piece.photos) {
    final readyThumb = photo.variants.any(
      (variant) =>
          variant.kind == PhotoVariant.thumb &&
          variant.status == VariantStatus.ready,
    );
    if (readyThumb) {
      thumbnail = photo;
      break;
    }
  }
  return PieceTileIdentity(
    subject: detail?.subject,
    text: detail?.text ?? '',
    // Issue #543: the category belongs to the COSTUME now — the grid tile
    // reads it from the view itself, never from `details.first` (which was
    // the one-deep model defect this issue fixes).
    categoryName: piece.categoryName,
    photo: thumbnail,
  );
}

/// Display name of a fundus piece.
///
/// `PieceView.name` is the authoritative, required label (the aggregate
/// rejects a blank name). The detail subject and the notes remain fallbacks
/// for rows whose name was left at the created placeholder.
String pieceDisplayName(PieceView piece, String genericFallback) {
  final name = piece.name.trim();
  if (name.isNotEmpty) return name;
  final identity = pieceTileIdentity(piece);
  final subject = identity.subject?.trim();
  if (subject != null && subject.isNotEmpty) return subject;
  final notes = piece.notes.trim();
  if (notes.isNotEmpty) return notes;
  return genericFallback;
}

/// Display label for a scene **outfit** beat.
///
/// A beat references a composed look, so the look's own `name` (joined by the
/// backend into `SceneOutfitBeatView.outfitName`) is the label. A projection
/// miss falls back to the localized generic label — never to a UUID.
String sceneBeatOutfitLabel({
  required String? outfitName,
  required String genericFallback,
}) {
  final joined = outfitName?.trim();
  if (joined != null && joined.isNotEmpty) return joined;
  return genericFallback;
}

/// Display label for a scene piece beat (issue #546).
///
/// Identity comes from the SAME tile helper ([pieceDisplayName] over
/// [pieceTileIdentity]) — never from a random detail. A piece missing
/// from the season projection (projection miss) falls back to the
/// backend-joined `costume_category_name`, then the localized generic
/// fallback.
String sceneBeatPieceLabel({
  required PieceView? piece,
  required String? joinedCategoryName,
  required String genericFallback,
}) {
  if (piece != null) return pieceDisplayName(piece, genericFallback);
  final joined = joinedCategoryName?.trim();
  if (joined != null && joined.isNotEmpty) return joined;
  return genericFallback;
}

/// Icon category for a scene piece beat: the piece's own category
/// (tile source) wins, the backend-joined name is the fallback.
String? sceneBeatPieceCategory({
  required PieceView? piece,
  required String? joinedCategoryName,
}) => piece?.categoryName ?? joinedCategoryName;
