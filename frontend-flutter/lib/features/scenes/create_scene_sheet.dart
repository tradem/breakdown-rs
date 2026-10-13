// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/create_error_banner.dart';
import '../../l10n/app_localizations_provider.dart';
import 'scenes_controller.dart';

/// Opens the Create Scene form: a centered dialog on macOS (side-sheet
/// width cap 480 dp, Escape-closable) and a bottom sheet on Android.
///
/// The in-context FAB presentation. The quick-create sheet reaches the same
/// form through the full-screen [CreateSceneScreen] (issue #624) — one form
/// implementation, two presentations.
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
          child: CreateSceneForm(episodeId: episode.id),
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
        child: CreateSceneForm(episodeId: episode.id),
      ),
    ),
  );
}

/// The Create Scene form body, keyed by the episode id the command sources
/// its `episode_id` from.
///
/// Shared by the in-context sheet ([showCreateSceneSheet]) and the
/// quick-create full-screen page (`CreateSceneScreen`, issue #624). The
/// episode id is the acted-on `EpisodeView`'s id (CQRS boundary).
class CreateSceneForm extends ConsumerStatefulWidget {
  const CreateSceneForm({super.key, required this.episodeId});

  final String episodeId;

  @override
  ConsumerState<CreateSceneForm> createState() => _CreateSceneFormState();
}

class _CreateSceneFormState extends ConsumerState<CreateSceneForm> {
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
        .read(scenesControllerProvider(widget.episodeId).notifier)
        .create(
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
    // Stay open on failure: the inline banner renders the failure (the
    // full-screen create page must not pop away its own error surface) and
    // the submit button is re-enabled so the user can retry.
    if (result.match((_) => false, (_) => true)) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final error = ref.watch(scenesCommandErrorProvider(widget.episodeId));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                CreateErrorBanner(
                  key: const Key('create-scene-error-banner'),
                  text: sceneCreateErrorCopy(l10n, error),
                  dismissKey: const Key('create-scene-error-dismiss'),
                  onDismiss: () => ref
                      .read(
                        scenesCommandErrorProvider(widget.episodeId).notifier,
                      )
                      .clear(),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                l10n.scenesCreateTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-scene-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.sceneNumberLabel),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return int.tryParse(t) == null
                      ? l10n.blocksNumberRequired
                      : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-summary'),
                controller: _summaryController,
                decoration: InputDecoration(labelText: l10n.sceneSummaryLabel),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-mood'),
                controller: _moodController,
                decoration: InputDecoration(labelText: l10n.sceneMoodLabel),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-location'),
                controller: _locationController,
                decoration: InputDecoration(labelText: l10n.sceneLocationLabel),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-scene-script-day'),
                controller: _scriptDayController,
                decoration: InputDecoration(
                  labelText: l10n.sceneScriptDayLabel,
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
