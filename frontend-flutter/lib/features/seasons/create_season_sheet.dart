// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import 'seasons_controller.dart';

/// Opens the bottom-sheet Create Season form (task 3.2).
Future<void> showCreateSeasonSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      // Cap the sheet below the viewport so the form's submit button is
      // reachable (the unbounded default pushes it off short screens).
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
        ),
        child: const _CreateSeasonForm(),
      ),
    ),
  );
}

/// The Create Season form.
///
/// A `ConsumerStatefulWidget` on purpose: the no-`StatefulWidget`/`setState`
/// rule (task 3.1) governs the *screen*; ephemeral text-field editing state
/// is widget state, not domain state. The submit dispatches the command
/// through [SeasonsController] — the form itself contains no domain logic.
class _CreateSeasonForm extends ConsumerStatefulWidget {
  const _CreateSeasonForm();

  @override
  ConsumerState<_CreateSeasonForm> createState() => _CreateSeasonFormState();
}

class _CreateSeasonFormState extends ConsumerState<_CreateSeasonForm> {
  final _formKey = GlobalKey<FormState>();
  final _seriesIdController = TextEditingController();
  final _numberController = TextEditingController();
  final _titleController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The series id is env-sourced (`--dart-define=DEFAULT_SERIES_ID`),
    // never hardcoded (AGENTS.md §5); the field stays editable for builds
    // without the define.
    final config = ref.read(appConfigProvider);
    _seriesIdController.text = config.defaultSeriesId;
  }

  @override
  void dispose() {
    _seriesIdController.dispose();
    _numberController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final number = int.parse(_numberController.text.trim());
    setState(() => _busy = true);
    // Command dispatch; failures surface through the screen's
    // `commandError` banner keyed on the stable problem code (D3), so on
    // both Ok and Err the sheet simply closes.
    await ref
        .read(seasonsControllerProvider.notifier)
        .create(
          seriesId: _seriesIdController.text.trim(),
          number: number,
          title: _titleController.text.trim(),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable so the form stays reachable on short screens / with the
    // soft keyboard open (the sheet itself is unbounded with
    // isScrollControlled).
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
                'Create season',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-series-id'),
                controller: _seriesIdController,
                decoration: const InputDecoration(labelText: 'Series id'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Series id is required'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Number'),
                validator: (v) => int.tryParse((v ?? '').trim()) == null
                    ? 'A whole number is required'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-title'),
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create-submit'),
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
