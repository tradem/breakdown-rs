// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/locale_formatters.dart';
import 'blocks_controller.dart';

/// Opens the Create Block form: a centered dialog on macOS (side-sheet
/// width cap 480 dp, Escape-closable) and a bottom sheet on Android.
Future<void> showCreateBlockSheet(
  BuildContext context,
  WidgetRef ref,
  SeasonView season,
) {
  final isMacOs = Theme.of(context).platform == TargetPlatform.macOS;
  if (isMacOs) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _CreateBlockForm(season: season),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
        ),
        child: _CreateBlockForm(season: season),
      ),
    ),
  );
}

/// Whether an optionally-set span is a legal range. The backend stores both
/// bounds unchecked (`block::aggregate`), so the form is the only guard
/// against an inverted span (issues #832/#833).
bool blockDateOrderValid(DateTime? start, DateTime? end) =>
    start == null || end == null || !end.isBefore(start);

/// The wire value for a picked day: `Date(y, m, d)` (no time component, so a
/// DST or timezone boundary can never shift the calendar day the user
/// tapped).
Date? blockWireDate(DateTime? picked) =>
    picked == null ? null : Date(picked.year, picked.month, picked.day);

/// The Create Block form: ephemeral picker state only — the submit
/// dispatches through [BlocksController]; ids are pre-filled from the
/// `SeasonView` navigation context, never from a second lookup.
///
/// Both dates are entered through Material day pickers (issue #833): the
/// free-text `YYYY-MM-DD` fields and their hand-written parser are gone, so
/// the user picks a day instead of encoding one. Both bounds stay optional
/// (each picked day can be cleared again) and the display is read-only
/// rendered text, never an editable field.
class _CreateBlockForm extends ConsumerStatefulWidget {
  const _CreateBlockForm({required this.season});

  final SeasonView season;

  @override
  ConsumerState<_CreateBlockForm> createState() => _CreateBlockFormState();
}

class _CreateBlockFormState extends ConsumerState<_CreateBlockForm> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pick(
    DateTime? current,
    void Function(DateTime) onPicked, {
    DateTime? fallback,
  }) async {
    final initial = current ?? fallback ?? _today;
    // Material date utilities localize the picker (no hand-rolled date math
    // for the locale — design.md §5).
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    // The form may have been disposed while the picker was open — never
    // setState on a disposed State.
    if (!mounted || picked == null) return;
    setState(() => onPicked(DateTime(picked.year, picked.month, picked.day)));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // The inverted-range state is already visible as a field message; the
    // submit never dispatches a span the backend would store unchecked.
    if (!blockDateOrderValid(_start, _end)) return;
    setState(() => _busy = true);
    final result = await ref
        .read(blocksControllerProvider(widget.season.id).notifier)
        .create(
          season: widget.season,
          number: int.parse(_numberController.text.trim()),
          startDate: blockWireDate(_start),
          endDate: blockWireDate(_end),
        );
    // Explicitly consumed: Ok renders as the optimistic overlay row, Err
    // renders in the screen's code-keyed banner — no local reaction needed.
    result.match<void>((_) {}, (_) {});
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// One optional day: a visible label, the read-only rendered value (never
  /// an input), the picker button, and a clear affordance once a day is set.
  Widget _dayRow({
    required AppLocalizations l10n,
    required String label,
    required Key textKey,
    required Key pickKey,
    required Key clearKey,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? l10n.blocksNoDate
                    : formatMediumDate(context, value),
                key: textKey,
              ),
            ),
            TextButton(
              key: pickKey,
              onPressed: _busy ? null : onPick,
              child: Text(l10n.blocksPickDate),
            ),
            if (value != null)
              IconButton(
                key: clearKey,
                onPressed: _busy ? null : onClear,
                tooltip: l10n.blocksClearDate,
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final orderValid = blockDateOrderValid(_start, _end);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.blocksCreateTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-block-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.blocksNumberLabel),
                validator: (v) => int.tryParse((v ?? '').trim()) == null
                    ? l10n.blocksNumberRequired
                    : null,
              ),
              const SizedBox(height: 8),
              _dayRow(
                l10n: l10n,
                label: l10n.blocksStartDate,
                textKey: const Key('create-block-start-text'),
                pickKey: const Key('create-block-start-pick'),
                clearKey: const Key('create-block-start-clear'),
                value: _start,
                onPick: () => _pick(_start, (d) => _start = d),
                onClear: () => setState(() => _start = null),
              ),
              _dayRow(
                l10n: l10n,
                label: l10n.blocksEndDate,
                textKey: const Key('create-block-end-text'),
                pickKey: const Key('create-block-end-pick'),
                clearKey: const Key('create-block-end-clear'),
                value: _end,
                // The end picker opens on the start day when one is set: the
                // common case is a span that begins and ends nearby.
                onPick: () => _pick(_end, (d) => _end = d, fallback: _start),
                onClear: () => setState(() => _end = null),
              ),
              if (!orderValid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.blocksDateOrderError,
                    key: const Key('create-block-date-order-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('create-block-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.blocksCreateButton),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
