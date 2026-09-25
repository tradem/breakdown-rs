// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/auth_providers.dart';
import '../../ai_import/ai_config/ai_config_controller.dart';
import '../../ai_import/ai_config/ai_config_screen.dart';
import '../../ai_import/import_jobs/import_submit_screen.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../l10n/app_localizations_provider.dart';
import 'setup_wizard_controller.dart';
import 'setup_wizard_state.dart';
import 'widgets/wizard_blocks_step.dart';
import 'widgets/wizard_completion_view.dart';
import 'widgets/wizard_dispatch_view.dart';
import 'widgets/wizard_review_step.dart';
import 'widgets/wizard_season_step.dart';

part 'setup_wizard_screen.g.dart';

/// AI-configuration availability for the completion CTA (design D4): the
/// EXISTING ai-config read decides — no new endpoint, no extra AUTHZ
/// surface (the config read already ships its gate comment, reused
/// verbatim). `false` while the discovery is loading/failed; the honest
/// degradation renders the prerequisite info card (a failed discovery is
/// not "a configuration exists").
@riverpod
bool wizardAiConfigAvailable(Ref ref) {
  final discovery = ref.watch(aiConfigDiscoveryProvider);
  return switch (discovery) {
    AsyncData(:final value) => value.match(
      (_) => false,
      (configs) => configs.any((c) => !c.revoked),
    ),
    _ => false,
  };
}

/// The season setup wizard screen (proposal §What Changes): a linear
/// four-step flow — Season → Blocks → Review → Completion — as a
/// full-screen route inside the Season tab's navigator (design D5).
///
/// The screen renders and dispatches only; all domain state lives in
/// [SetupWizardController]. Abort semantics (design D3, team decision 3):
/// leaving while editing/reviewing asks the discard confirmation and
/// discards everything on confirm (nothing is persisted); during dispatch
/// back is blocked; the settled phases pop freely.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  @override
  void initState() {
    super.initState();
    // Smart-default season number (task 2.3) seeded ONCE from the seasons
    // projection. Provider modification is not allowed during initState,
    // so the seed runs after the build phase (a microtask — the first
    // frame's field text is then synced by the step's didUpdateWidget).
    unawaited(
      Future.microtask(() async {
        if (!mounted) return;
        final rows = ref.read(seasonsView).rows;
        ref.read(setupWizardControllerProvider.notifier).seedSeasonNumber(rows);
        // The derived series-scoped block numbers (read-only info on the
        // Blocks step; the backend numbers blocks per SERIES). The series
        // id is the env-sourced default, same rule as the create sheet.
        await ref
            .read(setupWizardControllerProvider.notifier)
            .seedDerivedNumbers(seriesId: _seriesId());
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupWizardControllerProvider);
    final controller = ref.read(setupWizardControllerProvider.notifier);

    // Abort semantics (design D3 / spec `Destructive Abort With
    // Confirmation`):
    // * editing (Season/Blocks/Review) — back triggers the discard
    //   confirmation; confirming discards and pops (nothing was persisted);
    // * dispatching — blocked until the sequence settles;
    // * completed / partial-failure — free pop.
    final canPop = !state.isEditing && !state.isDispatching;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        // Pops during dispatch never reach here (canPop false) — but the
        // callback STILL fires with didPop false; without this guard the
        // discard dialog would open OVER the running dispatch. Only an
        // editing route-exit presents the confirmation.
        if (didPop || !state.isEditing) return;
        // Fire-and-forget: the dialog owns the pop decision.
        unawaited(_confirmDiscard(context, controller));
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10nOf(context).wizardTitle),
          automaticallyImplyLeading: false,
          leading: state.isEditing
              ? IconButton(
                  key: const Key('wizard-back'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l10nOf(context).commonBack,
                  onPressed: () => _confirmDiscard(context, controller),
                )
              : null,
        ),
        body: Column(
          children: [
            // The progress header covers ALL FOUR steps (spec: Season,
            // Blocks, Review, Completion — Completion is step 4); only the
            // dispatch overlay hides it (its own per-command progress
            // rules the screen then).
            if (!state.isDispatching)
              _ProgressHeader(
                position: state.isSettled ? 4 : _stepPosition(state.step),
              ),
            Expanded(child: _body(context, ref, state, controller)),
          ],
        ),
        bottomNavigationBar: state.isEditing
            ? _NavigationRow(
                onBack: controller.back,
                onNext: () => _next(context, controller),
                onNextEnabled: _nextEnabled(state),
                onFirstStep: state.step == SetupWizardStep.season,
              )
            : null,
      ),
    );
  }

  bool _nextEnabled(SetupWizardState state) => switch (state.step) {
    // Parse validity is event-reported (stepValid); the seeded number is
    // a positive integer by construction.
    SetupWizardStep.season => state.stepValid && state.seasonNumber > 0,
    // Parse validity (episode counts) + the submit-time noBlocks rule —
    // gated on the DERIVED NUMBERS having settled: advancing to review
    // (and confirming) with the fallback numbers while the derivation
    // still runs could create the season before a conflict stops the
    // sequence.
    SetupWizardStep.blocks =>
      state.stepValid && state.blocks.isNotEmpty && state.numbersSeeded,
    SetupWizardStep.review => state.numbersSeeded,
  };

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    SetupWizardState state,
    SetupWizardController controller,
  ) {
    return switch (state.phase) {
      SetupWizardPhase.editing => switch (state.step) {
        SetupWizardStep.season => WizardSeasonStep(
          seasonNumber: state.seasonNumber,
          seasonName: state.seasonName,
          onNumberChanged: controller.setSeasonNumber,
          onNameChanged: controller.setSeasonName,
          onValidityChanged: controller.setStepValid,
        ),
        SetupWizardStep.blocks => WizardBlocksStep(
          firstBlockNumber: state.nextBlockNumber,
          blocks: state.blocks,
          onAddBlock: controller.addBlock,
          onRemoveBlockAt: controller.removeBlockAt,
          onEpisodeCountChanged: controller.setBlockEpisodeCount,
          onTitleChanged: controller.setBlockTitle,
          onApplyTemplate: controller.applyTemplate,
          onValidityChanged: controller.setStepValid,
        ),
        SetupWizardStep.review => WizardReviewStep(
          firstBlockNumber: state.nextBlockNumber,
          seasonNumber: state.seasonNumber,
          seasonName: state.seasonName,
          blocks: state.blocks,
          numbersSeeded: state.numbersSeeded,
          onConfirm: () => controller.submit(seriesId: _seriesId()),
        ),
      },
      SetupWizardPhase.dispatching => WizardDispatchView(
        done: state.dispatchDone,
        total: state.dispatchTotal,
        label: state.dispatchLabel,
      ),
      SetupWizardPhase.completed ||
      SetupWizardPhase.partialFailure => WizardCompletionView(
        phase: state.phase,
        createdSeason: state.createdSeason,
        createdBlocks: state.createdBlocks,
        failure: state.failure,
        aiConfigAvailable: ref.watch(wizardAiConfigAvailableProvider),
        onRetry: () => controller.retryRemaining(seriesId: _seriesId()),
        onOpenAiConfig: () => _openAiConfig(context),
        onImport: () => _openImport(context),
        onDone: () => Navigator.of(context).pop(),
      ),
    };
  }

  /// The env-sourced series id (`--dart-define=DEFAULT_SERIES_ID`) — the
  /// same rule the quick-create sheet follows (never hardcoded).
  String _seriesId() => ref.read(appConfigProvider).defaultSeriesId;

  /// The navigation steps' 1-based progress positions (Completion's 4 is
  /// derived from the settled phase, not a navigation step).
  int _stepPosition(SetupWizardStep step) => switch (step) {
    SetupWizardStep.season => 1,
    SetupWizardStep.blocks => 2,
    SetupWizardStep.review => 3,
  };

  /// Advances one step; the "Weiter" button is already disabled when the
  /// step does not validate, so an enabled tap always advances.
  void _next(BuildContext context, SetupWizardController controller) {
    controller.next();
  }

  /// The discard confirmation (design D3): names what will be lost
  /// (decision 3 — no draft persistence). Confirm resets the controller
  /// (reopen starts fresh) and pops the wizard.
  Future<void> _confirmDiscard(
    BuildContext context,
    SetupWizardController controller,
  ) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10nOf(dialogContext).wizardCancelTitle),
        content: Text(l10nOf(dialogContext).wizardCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10nOf(dialogContext).wizardKeepEditing),
          ),
          TextButton(
            key: const Key('wizard-discard-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10nOf(dialogContext).wizardDiscard),
          ),
        ],
      ),
    );
    if (discard ?? false) {
      controller.reset();
      // State.context guarded by the State's own `mounted` check (the
      // dialog awaited above crossed an async gap).
      if (mounted) Navigator.of(this.context).pop();
    }
  }

  /// The info-card action: opens the AI configuration screen (full-screen
  /// push on the current navigator).
  void _openAiConfig(BuildContext context) {
    // Fire-and-forget push (no result consumed).
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AiConfigScreen())),
    );
  }

  /// The AI-import CTA: pops the wizard and pushes the import submission
  /// screen WITH the created season id — the acting context travels from
  /// the command ack (CQRS boundary: never re-derived from a projection
  /// or the ambient active-block scope), and the import flow opens
  /// directly instead of a tab detour.
  void _openImport(BuildContext context) {
    final seasonId = ref.read(setupWizardControllerProvider).createdSeason?.id;
    final navigator = Navigator.of(context);
    navigator.pop();
    if (seasonId != null) {
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AiImportSubmitScreen(seasonId: seasonId),
          ),
        ),
      );
    }
  }
}

/// The "Schritt x von n" progress header (task 4.5): semantic label +
/// linear indicator; directional step transitions are the platform
/// default push/pop animations of the route itself. The contract defines
/// FOUR steps — Season (1), Blocks (2), Review (3), Completion (4) — the
/// settled phases render as step 4.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.position});

  final int position;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l10nOf(context).wizardStepOf('$position', '4'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          key: const Key('wizard-progress'),
          children: [
            Expanded(
              child: Text(
                l10nOf(context).wizardStepOf('$position', '4'),
                key: const Key('wizard-progress-text'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Directional step navigation row: back (hidden on the first step) and
/// the gated "Weiter" advance button.
class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.onBack,
    required this.onNext,
    required this.onNextEnabled,
    required this.onFirstStep,
  });

  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool onNextEnabled;
  final bool onFirstStep;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (!onFirstStep)
              OutlinedButton.icon(
                key: const Key('wizard-prev'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(l10nOf(context).commonBack),
              ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('wizard-next'),
              onPressed: onNextEnabled ? onNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(l10nOf(context).wizardNext),
            ),
          ],
        ),
      ),
    );
  }
}
