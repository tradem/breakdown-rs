// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:uuid/uuid.dart';

/// Generates a client-side UUIDv7 for wire payloads that require a caller-
/// supplied, server-validated UUID (e.g. `CostumeDetail.id`).
///
/// The backend contract types such ids as `uuid` (required); serde rejects a
/// non-UUID string before the handler runs (issue #472: the previous
/// `'pending'` optimistic-overlay placeholder produced a 422
/// `domain.validation`). `Uuid().v7()` produces time-ordered v7 ids that match
/// the backend's `uuid`-crate v7 ids, so the value is always wire-valid.
///
/// This is the ONLY place the third-party `uuid` package is referenced; call
/// sites import this helper, never `package:uuid/uuid.dart` directly.
String generateUuidV7() => const Uuid().v7();
