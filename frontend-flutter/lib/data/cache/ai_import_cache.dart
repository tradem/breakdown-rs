// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/drift.dart';

/// Drift projection table for AI-import job rows (`flutter-ai-import`
/// task 1.4).
///
/// Mirrors the generated [AiImportJob] read DTO (`GET /v1/ai-import/jobs`,
/// backend issue #337) — never the event-store schema. Two client-local
/// columns sit alongside the mirrored fields:
///
/// * [episodeId] / [seriesId] — the **persisted apply context** (design
///   §2.3): `ApplyAiImportRequest.episode_id` is required, and both the
///   documented seasons-toolbar entry point and the remembered-job path can
///   reach a preview with no `EpisodeView` on the navigation stack, so the
///   episode context is *data persisted with the job*, not navigation
///   state. Written when the job is enqueued (upload) and on every
///   remembered-job cache write; nullable because a remembered id from an
///   older build may lack it (the UI then requires an explicit episode
///   pick before apply).
/// * [cachedAt] — client-only write time (never the server `updatedAt`).
///
/// The table is keyed by the server job id; rows are cleared on sign-out /
/// backend switch by `SessionReset` (identity-scoped, design §3).
class AiImportJobCacheRows extends Table {
  TextColumn get id => text()();

  /// Opaque server-side owner (`UserId` — the raw OIDC `sub`).
  TextColumn get userId => text()();

  /// Wire enum value of [JobStatus] (pending/running/succeeded/failed/
  /// dead_letter/payload_unavailable) — stored as text so an unknown
  /// future status degrades to a parse failure at read, not a DB fault.
  TextColumn get status => text()();

  /// Wire enum value of [DocumentKind] (script/schedule).
  TextColumn get documentKind => text()();

  /// Wire enum value of [SourceFormat] (csv/pdf/plain_text).
  TextColumn get sourceFormat => text()();

  /// Opaque `Block` aggregate id, when the job is block-scoped.
  TextColumn get blockId => text().nullable()();

  /// Client-local persisted apply context (design §2.3) — see class doc.
  TextColumn get episodeId => text().nullable()();
  TextColumn get seriesId => text().nullable()();

  TextColumn get dedupKey => text()();
  TextColumn get documentDigest => text()();
  TextColumn get sourceHandle => text()();

  TextColumn get lastError => text().nullable()();
  TextColumn get previewHandle => text().nullable()();

  IntColumn get retries => integer()();
  IntColumn get maxRetries => integer()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Client-only write time (D2 TTL discipline).
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
