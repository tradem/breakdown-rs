// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../data/report_models.dart';

/// Day scope for the reports screen: the shooting day whose reports render
/// and the season scoping the membership gate.
///
/// Both come from the read DTOs the user acts on (the Phase 2 day screen's
/// acted-on day) — never from a second projection lookup (CQRS boundary).
class ReportDayScope {
  const ReportDayScope({required this.dayId, required this.seasonId});

  final String dayId;
  final String seasonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportDayScope &&
          other.dayId == dayId &&
          other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(dayId, seasonId);
}

/// One PDF card's fetch state: idle, user-initiated fetching with progress,
/// ready (temp file staged for preview/share), or error keyed on `code`.
sealed class PdfCardState {
  const PdfCardState();
}

class PdfIdle extends PdfCardState {
  const PdfIdle();
}

class PdfFetching extends PdfCardState {
  const PdfFetching({this.progress});

  /// 0..1 share of the transfer, or `null` while the total is unknown
  /// (streaming responses report -1) — the card renders an indeterminate
  /// indicator then, never a fabricated percentage.
  final double? progress;
}

class PdfReady extends PdfCardState {
  const PdfReady(this.file);

  /// The staged temp-file copy (cache/temporary directory — never the
  /// persistent documents directory, never Drift). Deleted on every
  /// non-save exit (preview closed, share done/cancelled/failed).
  final File file;
}

class PdfError extends PdfCardState {
  const PdfError(this.error);

  final ProblemError error;
}

/// Controller state shape (seasons reference pattern).
class ReportsScreenState {
  const ReportsScreenState({
    required this.sollIst,
    required this.plannedCount,
    required this.actualCount,
    this.pdfs = const {},
    this.commandError,
    this.accessDenial,
  });

  /// The Soll-Ist diff report (rows + flags + finality, read-model render).
  final AsyncValue<SollIstReport> sollIst;

  /// Planned scene count (dispo row count) and actual scene count
  /// (shoot-day row count) — counts over read DTOs, never recomputed flags.
  final AsyncValue<int> plannedCount;
  final AsyncValue<int> actualCount;

  /// Per-kind PDF card state (idle until the user fetches).
  final Map<ReportPdfKind, PdfCardState> pdfs;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// Local AUTHZ-GATE denial (`membership.pending` while the membership
  /// resolves, `membership.unavailable` on fetch error,
  /// `report.forbidden` on resolved denial) — every variant issues zero
  /// report requests.
  final ProblemError? accessDenial;
}
