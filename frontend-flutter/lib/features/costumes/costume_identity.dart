// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

/// The user-facing identity fields derived from a costume projection.
///
/// A costume has no wire-level name. The first detail's `subject` is the
/// de-facto designation; `notes` are a deliberate fallback, never a UUID.
class CostumeTileIdentity {
  const CostumeTileIdentity({
    required this.subject,
    required this.text,
    required this.categoryName,
    required this.photo,
  });

  final String? subject;
  final String text;
  final String? categoryName;
  final CostumePhotoView? photo;
}

CostumeTileIdentity costumeTileIdentity(CostumeView costume) {
  final detail = costume.details.isEmpty ? null : costume.details.first;
  CostumePhotoView? thumbnail;
  for (final photo in costume.photos) {
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
  return CostumeTileIdentity(
    subject: detail?.subject,
    text: detail?.text ?? '',
    // Issue #543: the category belongs to the COSTUME now — the grid tile
    // reads it from the view itself, never from `details.first` (which was
    // the one-deep model defect this issue fixes).
    categoryName: costume.categoryName,
    photo: thumbnail,
  );
}

String costumeDisplayName(CostumeView costume, String genericFallback) {
  final identity = costumeTileIdentity(costume);
  final subject = identity.subject?.trim();
  if (subject != null && subject.isNotEmpty) return subject;
  final notes = costume.notes.trim();
  if (notes.isNotEmpty) return notes;
  return genericFallback;
}

/// Display label for a scene costume beat (issue #546).
///
/// Identity comes from the SAME tile helper ([costumeDisplayName] over
/// [costumeTileIdentity]) — never from a random detail. A costume missing
/// from the season projection (projection miss) falls back to the
/// backend-joined `costume_category_name`, then the localized generic
/// fallback.
String sceneBeatCostumeLabel({
  required CostumeView? costume,
  required String? joinedCategoryName,
  required String genericFallback,
}) {
  if (costume != null) return costumeDisplayName(costume, genericFallback);
  final joined = joinedCategoryName?.trim();
  if (joined != null && joined.isNotEmpty) return joined;
  return genericFallback;
}

/// Icon category for a scene costume beat: the costume's own category
/// (tile source) wins, the backend-joined name is the fallback.
String? sceneBeatCostumeCategory({
  required CostumeView? costume,
  required String? joinedCategoryName,
}) => costume?.categoryName ?? joinedCategoryName;
