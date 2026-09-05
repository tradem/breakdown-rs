// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scenes_controller.dart';

/// Opens the Create Scene form: a centered dialog on macOS (side-sheet
/// width cap 480 dp, Escape-closable) and a bottom sheet on Android.
Future<void> showCreateSceneSheet(
  BuildContext context,
  WidgetRef ref,
  EpisodeView episode,
) {
  final isMacOs = Theme.of(context).platform == TargetPlatform.macOS;
  if (isMacOs) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _CreateSceneForm(episode: episode),
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
        child: _CreateSceneForm(episode: episode),
      ),
    ),
  );
}

class _CreateSceneForm extends ConsumerStatefulWidget {
  const _CreateSceneForm({required this.episode});

  final EpisodeView episode;

  @override
  ConsumerState<_CreateSceneForm> createState() => _CreateSceneFormState();
}

class _CreateSceneFormState extends ConsumerState<_CreateSceneForm> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _summaryController = TextEditingController();
  final _moodController = TextEditingController();
  final _locationController = TextEditingController();
  final _scriptDayController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _numberController.dispose();
    _summaryController.dispose();
    _moodController.dispose();
    _locationController.dispose();
    _scriptDayController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final numberText = _numberController.text.trim();
    final result = await ref
        .read(scenesControllerProvider(widget.episode.id).notifier)
        .create(
          episode: widget.episode,
          details: SceneDetails(
            (b) => b
              ..isScheduleSet = false
              ..sceneNumber = numberText.isEmpty ? null : int.parse(numberText)
              ..summary = text(_summaryController)
              ..mood = text(_moodController)
              ..location = text(_locationController)
              ..scriptDay = text(_scriptDayController),
          ),
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
                'Create scene',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-scene-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Scene number (optional)',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return int.tryParse(t) == null
                      ? 'A whole number is required'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-summary'),
                controller: _summaryController,
                decoration: const InputDecoration(
                  labelText: 'Summary (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-mood'),
                controller: _moodController,
                decoration: const InputDecoration(labelText: 'Mood (optional)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-location'),
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-script-day'),
                controller: _scriptDayController,
                decoration: const InputDecoration(
                  labelText: 'Script day (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create-scene-submit'),
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
