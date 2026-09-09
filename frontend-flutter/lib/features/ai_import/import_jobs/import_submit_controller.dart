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
  void selectKind(AiImportKind kind) => state = kind;

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
    final ack = await switch (state) {
      AiImportKind.schedule => repo.uploadSchedule(
        body: document.body,
        source: document.source,
      ),
      AiImportKind.script => repo.uploadScript(body: document.body),
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
      if (stampError != null) {
        // The job EXISTS server-side (the ack carried its id) — surface
        // the context-stamp failure honestly; the job status screen
        // still opens and the apply step will require the explicit
        // episode pick (never a guessed episode_id).
        return Left(stampError);
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
      await repo.cache.setEpisodeContext(
        jobId,
        episodeId: episode.id,
        seriesId: episode.seriesId,
      );
      return const Right(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.write_failed'));
    }
  }
}

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
