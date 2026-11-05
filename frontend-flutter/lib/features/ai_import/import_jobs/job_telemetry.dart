// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// The provider/model a job ACTUALLY ran with (issue #831).
///
/// The reported defect: the preview's naming card rendered the **currently
/// configured** `AiConfigView` as its primary line, its provider as the
/// secondary line, and then repeated the same pair in the caption — so the
/// configured model was named twice and the model that actually produced the
/// rows was named nowhere. The identity IS on the wire, content-free:
/// `AiImportJob.telemetry` (`JobTelemetrySummary.provider` / `.model`), the
/// same pair the job status screen already renders as identity chips.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview reads one authoritative job record and the app's single SSE
/// consumer stays the job-status controller (battery contract D5). The
/// repository write-through caches the row, so the sibling read that already
/// happens for the Decision-Model line (`aiJobDecisionTelemetryProvider`) costs
/// the preview at most one extra small GET — the two surfaces are kept
/// independent on purpose, so a failure or retry on one never speaks for the
/// other.
///
/// No automatic retry: Riverpod 3's default re-runs a failed provider on an
/// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
/// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
/// backoff is pending. This surface is a quiet header fact, not a blocking read
/// — it has no retry affordance of its own (see the card's honest degradation).
library;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/ai_import_providers.dart';

part 'job_telemetry.g.dart';

/// The job's content-free telemetry summary — `null` for a job that recorded
/// none (every pre-#609 row).
///
/// `null` means exactly one thing: **the wire carries no telemetry**, so the
/// app cannot name the model that produced the rows. The provider never
/// invents one, and it never falls back to the configured model — "configured"
/// and "used" are different facts, which is the whole point of issue #831.
///
/// A FAILED read re-throws into Riverpod's error channel. The naming card
/// renders that arm like "no telemetry known" rather than inventing a pair (see
/// [aiNamingComparison] callers): a header that cannot state which model ran
/// must not claim a comparison.
@Riverpod(retry: _noAutoRetry)
Future<JobTelemetrySummary?> aiJobTelemetry(Ref ref, String jobId) async {
  final repo = ref.read(aiImportRepositoryProvider);
  final job = await repo.getJobAndCache(jobId);
  return job.match((err) => throw err, (job) => job.telemetry);
}

/// The `retry: null` policy for [aiJobTelemetry] — never retry on a timer (see
/// the provider doc).
Duration? _noAutoRetry(int retryCount, Object error) => null;
