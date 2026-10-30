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
/// * [episodeId] / [projectId] — the **persisted apply context** (design
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
  TextColumn get projectId => text().nullable()();

  TextColumn get dedupKey => text()();
  TextColumn get documentDigest => text()();
  TextColumn get sourceHandle => text()();

  TextColumn get lastError => text().nullable()();
  TextColumn get previewHandle => text().nullable()();

  IntColumn get retries => integer()();
  IntColumn get maxRetries => integer()();

  /// Live extraction progress of a running job (backend issue #664),
  /// serialized as the generated [AiImportProgress] JSON object — `null`
  /// for pending jobs and freshly re-claimed retry attempts. Text (not a
  /// typed column) so an unknown future stage degrades to a parse failure
  /// at read, not a DB fault.
  TextColumn get progressJson => text().nullable()();

  /// The uploaded document's own file name (issue #763), as the authoritative
  /// list read reported it. `null` for a job whose upload carried no name and
  /// for a pre-#763 row — a cached-first paint then keeps the kind/date title
  /// instead of inventing one.
  TextColumn get sourceFileName => text().nullable()();

  /// The episodes a successful apply landed rows in (issue #763), serialized as
  /// the generated `AppliedEpisode` JSON list. Text (not typed columns) for the
  /// same reason as [progressJson]: an unknown future payload degrades to "not
  /// known" at read, never to a DB fault. `null` until an apply has run.
  TextColumn get appliedEpisodesJson => text().nullable()();

  /// The job-level Decision Model scoring outcome (issue #767), serialized as
  /// the generated `DecisionTelemetry` JSON object — `null` for a pre-#767 row
  /// (`decision_telemetry` is `NULL` server-side for those and the outcome
  /// cannot be reconstructed) and for a job that completed without the pass.
  /// Text (not typed columns) for the same reason as [progressJson]: an
  /// unknown future outcome/enum value degrades to "not recorded" at read,
  /// never to a DB fault, and the cache never invents an outcome.
  TextColumn get decisionTelemetryJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Client-only write time (D2 TTL discipline).
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
