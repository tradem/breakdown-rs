// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'episodes_controller.dart';

/// Opens the Create Episode form: a centered dialog on macOS (side-sheet
/// width cap 480 dp, Escape-closable) and a bottom sheet on Android.
Future<void> showCreateEpisodeSheet(
  BuildContext context,
  WidgetRef ref,
  BlockView block,
) {
  final isMacOs = Theme.of(context).platform == TargetPlatform.macOS;
  if (isMacOs) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _CreateEpisodeForm(block: block),
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
        child: _CreateEpisodeForm(block: block),
      ),
    ),
  );
}

class _CreateEpisodeForm extends ConsumerStatefulWidget {
  const _CreateEpisodeForm({required this.block});

  final BlockView block;

  @override
  ConsumerState<_CreateEpisodeForm> createState() => _CreateEpisodeFormState();
}

class _CreateEpisodeFormState extends ConsumerState<_CreateEpisodeForm> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final nameText = _nameController.text.trim();
    final result = await ref
        .read(
          episodesControllerProvider(
            widget.block.id,
            widget.block.seasonId,
          ).notifier,
        )
        .create(
          block: widget.block,
          number: int.parse(_numberController.text.trim()),
          name: nameText.isEmpty ? null : nameText,
        );
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
                'Create episode',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-episode-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Number'),
                validator: (v) => int.tryParse((v ?? '').trim()) == null
                    ? 'A whole number is required'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-episode-name'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create-episode-submit'),
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
