// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../l10n/app_localizations_provider.dart';
import 'apply_controller.dart';
import 'apply_screen.dart';
import 'job_status_controller.dart';

/// The preview screen (`flutter-ai-import-workflow` task 4.1): typed
/// `AiImportPreviewResponse` / `AiPreviewPayload` rendering
/// (`kind`/`data`: script → `ScriptContext`, schedule →
/// `ShootingSchedule`, merged → `MergedPreview`).
///
/// D1 discipline: rows render FROM the typed payload — never retyped
/// DTOs, never silent coercion. An unknown future `kind` (the generated
/// oneOf rejects it) surfaces as the explicit degraded error card with
/// the stable `ai_import.preview_kind_unknown` code; a 404 (no preview)
/// is the explicit "no preview available" state with the path back to
/// the job's terminal status. No fabricated rows, ever.
class AiPreviewScreen extends ConsumerWidget {
  const AiPreviewScreen({required this.jobId, super.key});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(aiPreviewProvider(jobId));

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiPreviewTitle)),
      body: ListView(
        key: const Key('ai-preview-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          switch (preview) {
            AsyncData(:final value) => value.match(
              (err) => _DegradedCard(error: err),
              (response) => _TypedPreviewBody(jobId: jobId, response: response),
            ),
            AsyncError(:final error) => _DegradedCard(
              error: error is ProblemError
                  ? error
                  : ProblemError(code: 'unknown', detail: '$error'),
            ),
            _ => const SizedBox(
              key: Key('ai-preview-loading'),
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

/// The degraded error card, keyed on the stable problem `code` — unknown
/// kinds, missing previews and transport faults each render their honest
/// state; nothing is guessed.
class _DegradedCard extends StatelessWidget {
  const _DegradedCard({required this.error});

  final ProblemError error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final degraded = error.code == 'ai_import.preview_kind_unknown';
    return Card(
      key: const Key('ai-preview-degraded'),
      color: degraded ? scheme.tertiaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (degraded)
              Text(
                key: const Key('ai-preview-kind-unknown'),
                l10nOf(context).aiPreviewKindUnknown,
              )
            else if (error.code == 'ai_import.preview_missing' ||
                error.status == 404)
              Text(
                key: const Key('ai-preview-missing'),
                l10nOf(context).aiPreviewMissing,
              )
            else
              Text(l10nOf(context).aiPreviewLoadError(error.code)),
          ],
        ),
      ),
    );
  }
}

/// The typed preview body: dispatches on the payload's `kind`/`data`
/// variant and renders rows from the typed DTOs. Also seeds the apply
/// controller with the actionable rows (verbatim `draft_ref`s).
class _TypedPreviewBody extends ConsumerStatefulWidget {
  const _TypedPreviewBody({required this.jobId, required this.response});

  final String jobId;
  final AiImportPreviewResponse response;

  @override
  ConsumerState<_TypedPreviewBody> createState() => _TypedPreviewBodyState();
}

class _TypedPreviewBodyState extends ConsumerState<_TypedPreviewBody> {
  /// The payload the apply rows were last seeded from. A provider
  /// refresh rebuilds this widget with a NEW response while Flutter
  /// reuses the element — the seed must follow the payload identity,
  /// otherwise `AiApplySection` builds mappings from stale `draft_ref`s
  /// and refreshed rows never reach the apply request.
  AiImportPreviewResponse? _seededResponse;

  @override
  Widget build(BuildContext context) {
    // The generated oneOf carries the variant object; `value` is
    // NULLABLE — a null means the variant never resolved, which is the
    // same honest "kind unknown" degradation as an unrecognized kind
    // (never an `as Object` throw during build).
    final dynamic value = widget.response.preview.oneOf.value;
    if (value == null) {
      return const _DegradedCard(
        error: ProblemError(code: 'ai_import.preview_kind_unknown'),
      );
    }
    final payload = value;

    // Seed the apply controller once per payload (idempotent); the rows
    // carry the payload's verbatim draft_refs and the persisted episode
    // context (design §2.3). Re-seeds when the payload changes (a
    // provider refresh reuses this element — the rows must follow).
    if (!identical(_seededResponse, widget.response)) {
      _seededResponse = widget.response;
      unawaited(() async {
        final context = await ref.read(
          aiJobContextProvider(widget.jobId).future,
        );
        if (!mounted) return;
        ref
            .read(aiApplyControllerProvider(widget.jobId).notifier)
            .seedRows(_actionableRows(this.context, payload), context);
      }());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _payloadHeader(context, payload),
        const SizedBox(height: 12),
        ..._payloadRows(context, payload),
        const SizedBox(height: 24),
        // The apply action: rows + decisions + persisted episode context
        // (or the explicit picker) drive it.
        AiApplySection(jobId: widget.jobId),
      ],
    );
  }

  Widget _payloadHeader(BuildContext context, Object payload) {
    final (title, subtitle) = _headerOf(context, payload);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const Key('ai-preview-title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  (String, String) _headerOf(BuildContext context, Object payload) =>
      switch (payload) {
        AiPreviewPayloadOneOf() => (
          l10nOf(context).aiPreviewScriptTitle,
          l10nOf(context)
              .aiPreviewScriptSubtitle('${payload.data.scenes.length}'),
        ),
        AiPreviewPayloadOneOf1() => (
          l10nOf(context).aiPreviewScheduleTitle,
          l10nOf(context)
              .aiPreviewScheduleSubtitle('${payload.data.rows.length}'),
        ),
        AiPreviewPayloadOneOf2() => (
          l10nOf(context).aiPreviewMergedTitle,
          l10nOf(context)
              .aiPreviewMergedSubtitle('${payload.data.scenes.length}'),
        ),
        _ => (l10nOf(context).aiPreviewFallbackTitle, ''),
      };

  List<Widget> _payloadRows(
    BuildContext context,
    Object payload,
  ) => switch (payload) {
    AiPreviewPayloadOneOf() => [
      for (final scene in payload.data.scenes)
        _PreviewRowCard(
          jobId: widget.jobId,
          draftRef: scene.draftRef,
          label: l10nOf(context).aiPreviewSceneWithSummary(
            '${scene.sceneNumber ?? '?'}',
            scene.summary == null ? '' : ' — ${scene.summary}',
          ),
        ),
      for (final uncertainty in payload.data.uncertainties)
        _InfoRowCard(
          label: l10nOf(context)
              .aiPreviewUncertainty(uncertainty.field, uncertainty.note),
        ),
    ],
    AiPreviewPayloadOneOf1() => [
      // Pre-merge schedule rows are informative — the merge worker turns
      // them into actionable drafts; no decision chips on this shape.
      for (final row in payload.data.rows)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewRowRef(
            row.rowRef,
            '${row.sceneNumber == null ? '' : 'Szene ${row.sceneNumber} · '}'
            '${row.shootingDayLabel ?? row.date?.toString() ?? l10nOf(context).aiPreviewUnscheduled}',
          ),
        ),
    ],
    AiPreviewPayloadOneOf2() => [
      for (final merged in payload.data.scenes)
        _PreviewRowCard(
          jobId: widget.jobId,
          draftRef: merged.scene.id,
          label: l10nOf(context).aiPreviewSceneWithSummary(
            '${merged.scene.sceneNumber ?? merged.scene.id}',
            '${merged.scene.summary == null ? '' : ' — ${merged.scene.summary}'}'
                '${l10nOf(context).aiPreviewScheduledRowCount('${merged.scheduleRows.length}')}',
          ),
        ),
      // Unmatched rows render as NON-actionable info cards — they are
      // excluded from the decisions and from one-tap accept-all (no
      // silent coercion into fabricated typed rows).
      for (final row in payload.data.unmatchedScheduleRows)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewUnmatchedScheduleRow(row.rowRef),
        ),
      for (final scene in payload.data.unmatchedScriptScenes)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewUnmatchedScriptScene(scene.id),
        ),
    ],
    _ => [_InfoRowCard(label: l10nOf(context).aiPreviewUnrecognizedShape)],
  };

  /// The actionable rows (never the info cards): script scenes carry
  /// their `draft_ref`s; merged previews act on the merged scene ids.
  List<PreviewRow> _actionableRows(BuildContext context, Object payload) =>
      switch (payload) {
        AiPreviewPayloadOneOf() => [
          for (final scene in payload.data.scenes)
            PreviewRow(
              draftRef: scene.draftRef,
              label: l10nOf(context)
                  .sceneTileLabel('${scene.sceneNumber ?? '?'}'),
            ),
        ],
        AiPreviewPayloadOneOf2() => [
          for (final merged in payload.data.scenes)
            PreviewRow(
              draftRef: merged.scene.id,
              label: l10nOf(context).sceneTileLabel(
                '${merged.scene.sceneNumber ?? merged.scene.id}',
              ),
            ),
        ],
        // Pre-merge schedule previews expose no actionable drafts yet.
        _ => const <PreviewRow>[],
      };
}

/// One actionable preview row: the verbatim `draft_ref` with its decision
/// chips (Create / Update / skip).
class _PreviewRowCard extends ConsumerWidget {
  const _PreviewRowCard({
    required this.jobId,
    required this.draftRef,
    required this.label,
  });

  final String jobId;
  final String draftRef;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiApplyControllerProvider(jobId));
    final controller = ref.read(aiApplyControllerProvider(jobId).notifier);
    RowDecision decision = const CreateDecision();
    for (final row in state.rows) {
      if (row.draftRef == draftRef) {
        decision = row.decision;
        break;
      }
    }
    return Card(
      key: Key('ai-preview-row-$draftRef'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: Key('ai-row-decision-$draftRef'),
              segments: [
                ButtonSegment(
                  value: 'create',
                  label: Text(l10nOf(context).aiPreviewCreate),
                ),
                ButtonSegment(
                  value: 'update',
                  label: Text(l10nOf(context).aiPreviewUpdate),
                ),
                ButtonSegment(
                  value: 'skip',
                  label: Text(l10nOf(context).aiPreviewSkip),
                ),
              ],
              selected: {
                switch (decision) {
                  UpdateDecision() => 'update',
                  SkipDecision() => 'skip',
                  _ => 'create',
                },
              },
              onSelectionChanged: (selection) async {
                switch (selection.first) {
                  case 'create':
                    controller.decide(draftRef, const CreateDecision());
                  case 'skip':
                    controller.decide(draftRef, const SkipDecision());
                  case 'update':
                    // The Update target is picked from the episode's
                    // existing aggregates (ids + versions from the read
                    // DTOs — never invented).
                    final picked = await showExistingScenePicker(
                      context,
                      ref,
                      jobId,
                    );
                    if (picked != null) {
                      controller.decide(
                        draftRef,
                        UpdateDecision(
                          aggregateId: picked.id,
                          version: picked.version,
                        ),
                      );
                    }
                }
              },
            ),
            if (decision is UpdateDecision)
              Text(
                key: Key('ai-preview-row-picked-$draftRef'),
                l10nOf(context).aiPreviewUpdatesScene(
                  decision.aggregateId,
                  '${decision.version}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Non-actionable preview row card (info only — excluded from the
/// decisions and from accept-all).
class _InfoRowCard extends StatelessWidget {
  const _InfoRowCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('ai-preview-info-row'),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}
