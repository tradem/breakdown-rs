// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The Create Block form (ephemeral text-field state only — the submit
/// dispatches through [BlocksController]; ids are pre-filled from the
/// `SeasonView` navigation context, never from a second lookup).
class _CreateBlockForm extends ConsumerStatefulWidget {
  const _CreateBlockForm({required this.season});

  final SeasonView season;

  @override
  ConsumerState<_CreateBlockForm> createState() => _CreateBlockFormState();
}

class _CreateBlockFormState extends ConsumerState<_CreateBlockForm> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _numberController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Date? _parseDate(String text) {
    final parts = text.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return Date(y, m, d);
  }

  String? _dateValidator(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return _parseDate(v) == null ? 'Use YYYY-MM-DD' : null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final startText = _startController.text.trim();
    final endText = _endController.text.trim();
    final result = await ref
        .read(blocksControllerProvider(widget.season.id).notifier)
        .create(
          season: widget.season,
          number: int.parse(_numberController.text.trim()),
          startDate: startText.isEmpty ? null : _parseDate(startText),
          endDate: endText.isEmpty ? null : _parseDate(endText),
        );
    // Explicitly consumed: Ok renders as the optimistic overlay row, Err
    // renders in the screen's code-keyed banner — no local reaction needed.
    result.match<void>((_) {}, (_) {});
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
                'Create block',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-block-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Number'),
                validator: (v) => int.tryParse((v ?? '').trim()) == null
                    ? 'A whole number is required'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-block-start'),
                controller: _startController,
                decoration: const InputDecoration(
                  labelText: 'Start date (YYYY-MM-DD, optional)',
                ),
                validator: _dateValidator,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-block-end'),
                controller: _endController,
                decoration: const InputDecoration(
                  labelText: 'End date (YYYY-MM-DD, optional)',
                ),
                validator: _dateValidator,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create-block-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
