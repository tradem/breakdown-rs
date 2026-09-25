// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

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
    categoryName: detail?.categoryName,
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
