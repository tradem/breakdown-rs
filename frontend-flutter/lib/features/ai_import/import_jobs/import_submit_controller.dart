// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/active_block.dart';
import '../../../auth/membership_gate.dart';
import '../../../auth/membership/membership_providers.dart';
import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart';
import 'import_state.dart';

part 'import_submit_controller.g.dart';

/// The submission controller (`flutter-ai-import-workflow` task 3.1).
///
/// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
/// season costume-dept capability is checked via
/// `currentMembershipProvider` BEFORE any network call; a client-side
/// denial renders the localized 403 narrative and issues ZERO calls
/// (provable by the fake-repository call count in tests).
///
/// The upload carries the episode context (design §2.3): the picked
/// episode's id + series id are persisted with the job record right after
/// the 202/200 ack, so the apply step later never guesses an
/// `episode_id`.
@Riverpod(keepAlive: false)
class AiImportSubmitController extends _$AiImportSubmitController {
  @override
  AiImportKind build() => AiImportKind.schedule;

  /// Switches the document kind (schedule CSV/PDF/plain, script PDF).
  /// The pending body is KIND-SPECIFIC: a carried-over paste/CSV would
  /// be uploaded with the wrong declared content type (e.g. plain text
  /// declared as `application/pdf`), so the switch clears both pending
  /// sources — the user re-provides the document for the new kind.
  void selectKind(AiImportKind kind) {
    if (state == kind) return;
    state = kind;
    ref.read(pendingDocumentProvider.notifier).set(null);
    ref.read(pendingPasteProvider.notifier).clear();
  }

  /// The submit dispatch. Returns the acknowledgement on success (the
  /// screen navigates to the job status screen); every failure surfaces
  /// keyed on its stable problem `code`.
  ///
  /// // AUTHZ-GATE: schedule/script uploads and the apply command are
  /// season-membership-gated server-side (`authorize_season_result
  /// Action::Write` on the job's season — the same predicate that derives
  /// the capability set). The client mirrors that gate here via
  /// [checkAiImportCapability] BEFORE the call; denial issues zero calls.
  Future<Result<AiUploadAck>> submit(AiImportDocument document) async {
    // Every dispatch starts clean: a previous dispatch's non-fatal stamp
    // warning must not leak into this one's outcome.
    ref.read(aiStampWarningProvider.notifier).set(null);
    // -- AUTHZ-GATE (begin): scope + capability resolution --------------
    final scope = ref.read(activeBlockProvider);
    if (scope == null) {
      const error = ProblemError(code: 'ai_import.scope_missing', status: 400);
      return const Left(error);
    }
    // The membership read is an AsyncValue provider: a pending fetch is
    // NOT a resolved denial (D3 — disabled-with-retry, never the 403
    // narrative). The dispatch therefore AWAITS the underlying fetch
    // first (same discipline as the seasons AUTHZ-GATE's awaited session
    // resolve) so a pending restore never reads as denial-by-absence;
    // dev-auth mode short-circuits without a network call.
    //
    // The gate's read is held open with `ref.listen` for the duration:
    // two bare `ref.read`s would let the autoDispose family die between
    // them (its 0ms disposal timer), re-arming a fresh pending fetch and
    // deterministically misreading the gate as `membership.pending`.
    final sub = ref.listen(
      currentMembershipProvider(scope.seasonId),
      (_, _) {},
    );
    try {
      final fetched = await ref.read(
        membershipFetchProvider(scope.seasonId).future,
      );
      // Explicitly consumed: the gate below re-reads the resolved
      // CurrentMembership state; the fetch Result itself needs no branch
      // (a Left becomes AsyncError → `membership.pending` there).
      fetched.match<void>((_) {}, (_) {});
    } on Object {
      // A failed fetch is an error state → the gate below denies with
      // `membership.pending` (retry affordance), never the 403 narrative.
    }
    // The provider may have been disposed while the fetch was pending
    // (screen left mid-dispatch) — resolve harmlessly, never touch the
    // dead ref.
    if (!ref.mounted) {
      return const Left(ProblemError(code: 'membership.pending'));
    }
    final SeasonMembershipDto? membership = ref
        .read(currentMembershipProvider(scope.seasonId))
        .value;
    final decision = checkAiImportCapability(membership);
    sub.close();
    switch (decision) {
      case GateAllow():
        break;
      case GateDeny(:final code):
        // Client-side denial: the localized narrative renders and the
        // request is NEVER issued (task 5.2 — fake-repo call count 0).
        return Left(
          ProblemError(
            code: code,
            status: code == 'membership.pending' ? null : 403,
          ),
        );
    }
    // -- AUTHZ-GATE (end) ------------------------------------------------

    final repo = ref.read(aiImportRepositoryProvider);
    // Content-type honesty: the script route declares
    // `application/pdf` — a non-PDF source (pasted text, CSV picked
    // before a kind switch) is rejected CLIENT-side with the stable
    // 415 code instead of sending mismatched bytes to the backend.
    final ack = await switch (state) {
      AiImportKind.schedule => repo.uploadSchedule(
        body: document.body,
        source: document.source,
      ),
      AiImportKind.script when document.source == AiScheduleSource.pdf =>
        repo.uploadScript(body: document.body),
      AiImportKind.script => Future<Result<AiUploadAck>>.value(
        const Left(
          ProblemError(code: 'ai_import.unsupported_media_type', status: 415),
        ),
      ),
    };

    return ack.match((err) => Left<ProblemError, AiUploadAck>(err), (
      uploaded,
    ) async {
      if (!ref.mounted) {
        // The screen went away mid-upload; the job exists server-side
        // and is remembered nowhere — the honest state for a dead
        // subscriber.
        return Right(uploaded);
      }
      // Persist the episode context with the job record (design §2.3):
      // fetch the job (success-only cache write) and stamp the
      // client-local episode/series columns, then remember the job id.
      final contextStamped = await _stampEpisodeContext(uploaded.jobId);
      final stampError = contextStamped.getLeft().toNullable();
      // The job EXISTS server-side (the ack carried its id) — a context
      // stamp failure is NON-FATAL: the acknowledgement is kept so the
      // screen navigates to the job (a discarded ack would hide a
      // created job behind a local storage fault). The stamp error is
      // surfaced as a warning; the apply step requires the explicit
      // episode pick either way (never a guessed episode_id).
      if (stampError != null) {
        ref.read(aiStampWarningProvider.notifier).set(stampError);
      }
      return Right(uploaded);
    });
  }

  /// Fetches the fresh job (caching the row) and stamps the persisted
  /// apply context from the acting episode.
  Future<Result<void>> _stampEpisodeContext(String jobId) async {
    final episode = ref.read(pendingEpisodeProvider);
    final repo = ref.read(aiImportRepositoryProvider);
    final job = await repo.getJobAndCache(jobId);
    final fetched = job.getRight().toNullable();
    if (fetched == null) {
      return job.map<void>((_) {});
    }
    if (episode == null) {
      // No episode picked: the context stays missing — the apply step
      // requires an explicit episode selection (never a guessed id).
      return const Right(null);
    }
    try {
      // Identity-scoped context stamp: the row's own userId (the
      // server-provided caller identity) scopes the lookup — never a
      // same-id row of a previous session identity.
      await repo.cache.setEpisodeContext(
        jobId,
        userId: fetched.userId,
        episodeId: episode.id,
        seriesId: episode.seriesId,
      );
      return const Right(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.write_failed'));
    }
  }
}

/// The submit-time paste text (transient controller state, cleared after
/// dispatch; it is a document body, not a secret). Lives HERE (the
/// controller layer) so [selectKind] can clear it — the screen only
/// binds to it.
class PendingPaste extends Notifier<String> {
  @override
  String build() => '';

  void set(String text) => state = text;

  void clear() => state = '';
}

final pendingPasteProvider = NotifierProvider<PendingPaste, String>(
  PendingPaste.new,
);

/// The pending document (picked file). Cleared after every dispatch —
/// by [selectKind] (a kind switch invalidates the body) and by the
/// screen after a successful dispatch.
class PendingDocument extends Notifier<AiImportDocument?> {
  @override
  AiImportDocument? build() => null;

  void set(AiImportDocument? document) => state = document;
}

final pendingDocumentProvider =
    NotifierProvider<PendingDocument, AiImportDocument?>(PendingDocument.new);

/// Non-fatal context-stamp warning (design §2.3): the upload ack was
/// accepted and the job exists server-side, but the client-local
/// episode/series context could not be persisted. The submit screen
/// surfaces it as a warning while STILL navigating to the job; cleared
/// at the start of every dispatch.
class _StampWarning extends Notifier<ProblemError?> {
  @override
  ProblemError? build() => null;

  void set(ProblemError? error) => state = error;
}

final aiStampWarningProvider = NotifierProvider<_StampWarning, ProblemError?>(
  _StampWarning.new,
);

/// The episode the user picked as the apply target for the NEXT import
/// (submit-time context, design §2.3). Controller state — not navigation
/// state; cleared after the dispatch settles.
class PendingEpisode extends Notifier<EpisodeView?> {
  @override
  EpisodeView? build() => null;

  void set(EpisodeView? episode) => state = episode;
}

final pendingEpisodeProvider = NotifierProvider<PendingEpisode, EpisodeView?>(
  PendingEpisode.new,
);
