// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

import '../../../../design/spacing.dart';
import '../../../../l10n/app_localizations_provider.dart';
import '../setup_wizard_state.dart';

/// The wizard's block templates as suggestion chips (spec `Block Draft
/// With Templates`; the presets are consts per design.md D-risks —
/// data-driven from the backend is speculative now). Golden/semantic copy
/// keyed via the glossary (`wizard.blocks.template4x8` /
/// `wizard.blocks.template3x6`).
const wizardTemplates = <({int blocks, int episodes, String label})>[
  (blocks: 4, episodes: 8, label: '4 Blöcke à 8 Episoden'),
  (blocks: 3, episodes: 6, label: '3 Blöcke à 6 Episoden'),
];

/// Blocks step of the setup wizard (task 4.2): repeatable block drafts
/// (episode count with a default, optional title, removal) and the
/// template suggestions as expandable chips.
///
/// Riverpod-free presentation (design D1): drafts + callbacks in; the
/// per-draft text fields' editing state is widget state, re-synced when
/// the draft list structurally changes (add/remove/template). Reports
/// step validity via [WizardBlocksStep.onValidityChanged] (≥ 1 draft,
/// every episode count a positive integer) — the screen gates "Weiter"
/// on it.
class WizardBlocksStep extends StatefulWidget {
  const WizardBlocksStep({
    super.key,
    required this.firstBlockNumber,
    required this.blocks,
    required this.onAddBlock,
    required this.onRemoveBlockAt,
    required this.onEpisodeCountChanged,
    required this.onTitleChanged,
    required this.onApplyTemplate,
    required this.onValidityChanged,
  });

  /// The first free series-scoped block number (derived from the series'
  /// existing blocks at wizard open); draft `i` renders as block
  /// `firstBlockNumber + i` — READ-ONLY information (a headline, never a
  /// field): the backend enforces block-number uniqueness per series, so
  /// the wizard derives it (team decision: derive at dispatch, display
  /// read-only).
  final int firstBlockNumber;

  final List<BlockDraft> blocks;
  final VoidCallback onAddBlock;
  final ValueChanged<int> onRemoveBlockAt;
  final void Function(int index, int count) onEpisodeCountChanged;
  final void Function(int index, String title) onTitleChanged;
  final void Function({required int count, required int episodesPerBlock})
  onApplyTemplate;
  final ValueChanged<bool> onValidityChanged;

  @override
  State<WizardBlocksStep> createState() => _WizardBlocksStepState();
}

class _WizardBlocksStepState extends State<WizardBlocksStep> {
  /// Per-draft field controllers (position-keyed); re-synced when the
  /// draft list structurally changes.
  List<TextEditingController> _counts = [];
  List<TextEditingController> _titles = [];

  /// Per-draft inline validity (episode count parse) — the inline copy
  /// source, keyed per error code.
  List<WizardFieldError?> _countErrors = [];

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant WizardBlocksStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blocks.length != widget.blocks.length) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    _disposeControllers();
    _counts = [
      for (var i = 0; i < widget.blocks.length; i++)
        TextEditingController(text: '${widget.blocks[i].episodeCount}'),
    ];
    _titles = [
      for (var i = 0; i < widget.blocks.length; i++)
        TextEditingController(text: widget.blocks[i].title),
    ];
    _countErrors = List<WizardFieldError?>.filled(
      widget.blocks.length,
      null,
      growable: false,
    );
    // The structural re-sync CLEARS the per-draft errors (a stale invalid
    // count from before the add/template must not keep "Weiter" disabled
    // forever) — but it runs during build phases, so the single validity
    // report is deferred to after the frame (never invoked synchronously
    // during build; the parent's stepValid stays fresh event-driven).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportValidity();
    });
    // NO synchronous validity report here — syncControllers runs during
    // build phases; the post-frame callback above owns the one report.
  }

  void _disposeControllers() {
    for (final c in [..._counts, ..._titles]) {
      c.dispose();
    }
  }

  void _onCountChanged(int index, String raw) {
    final error = validatePositiveCount(raw);
    setState(() {
      if (index < _countErrors.length) {
        _countErrors[index] = error;
      }
    });
    _reportValidity();
    final value = int.tryParse(raw.trim());
    if (error == null && value != null) {
      widget.onEpisodeCountChanged(index, value);
    }
  }

  void _reportValidity() {
    final valid =
        widget.blocks.isNotEmpty && _countErrors.every((e) => e == null);
    widget.onValidityChanged(valid);
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('wizard-step-blocks'),
      padding: const EdgeInsets.all(AppSpacing.space16),
      children: [
        Text(l10nOf(context).navBlocks, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.space8),
        // Inline submit-time validation copy (spec: "Weiter" disabled
        // WITH inline copy keyed per error code — noBlocks).
        if (widget.blocks.isEmpty)
          Text(
            l10nOf(context).wizardFieldBlocks,
            key: const Key('wizard-blocks-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        for (var i = 0; i < widget.blocks.length; i++)
          _DraftCard(
            index: i,
            blockNumber: widget.firstBlockNumber + i,
            countController: _counts[i],
            titleController: _titles[i],
            countError: i < _countErrors.length ? _countErrors[i] : null,
            onCountChanged: (raw) => _onCountChanged(i, raw),
            onTitleChanged: (title) => widget.onTitleChanged(i, title),
            onRemove: () => widget.onRemoveBlockAt(i),
          ),
        const SizedBox(height: AppSpacing.space12),
        OutlinedButton.icon(
          key: const Key('wizard-add-draft'),
          onPressed: widget.onAddBlock,
          icon: const Icon(Icons.add),
          label: Text(l10nOf(context).blocksAddFab),
        ),
        const SizedBox(height: AppSpacing.space16),
        Text(
          l10nOf(context).wizardTemplates,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.space8),
        Wrap(
          spacing: AppSpacing.space8,
          children: [
            for (final template in wizardTemplates)
              ActionChip(
                key: Key(
                  'wizard-apply-template-'
                  '${template.blocks}x${template.episodes}',
                ),
                avatar: const Icon(Icons.bolt, size: 18),
                label: Text(template.label),
                onPressed: () => widget.onApplyTemplate(
                  count: template.blocks,
                  episodesPerBlock: template.episodes,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space24),
      ],
    );
  }
}

/// One block draft card: episode count + optional title + removal.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.index,
    required this.blockNumber,
    required this.countController,
    required this.titleController,
    required this.countError,
    required this.onCountChanged,
    required this.onTitleChanged,
    required this.onRemove,
  });

  final int index;

  /// The derived series-scoped number this draft will dispatch under —
  /// shown as read-only information (headline), never editable.
  final int blockNumber;
  final TextEditingController countController;
  final TextEditingController titleController;
  final WizardFieldError? countError;
  final ValueChanged<String> onCountChanged;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('wizard-block-draft-$index'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10nOf(context).blockTileLabel('$blockNumber'),
                    key: Key('wizard-block-number-$index'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('wizard-remove-draft-$index'),
                  tooltip: l10nOf(context).wizardRemoveBlock,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              key: Key('wizard-episode-count-$index'),
              controller: countController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10nOf(context).navEpisodes,
                errorText: countError == null
                    ? null
                    : wizardErrorCopyForField(l10nOf(context), countError!),
              ),
              onChanged: onCountChanged,
            ),
            const SizedBox(height: AppSpacing.space8),
            TextFormField(
              key: Key('wizard-draft-title-$index'),
              controller: titleController,
              decoration: InputDecoration(
                labelText: l10nOf(context).wizardEpisodeTitlePlaceholder,
              ),
              onChanged: onTitleChanged,
            ),
          ],
        ),
      ),
    );
  }
}
