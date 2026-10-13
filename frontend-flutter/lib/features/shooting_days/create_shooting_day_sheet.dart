// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/create_error_banner.dart';
import '../../l10n/app_localizations_provider.dart';
import 'shooting_days_controller.dart';

/// Opens the Create Shooting Day form as a modal bottom sheet — the
/// in-context FAB presentation. The quick-create sheet reaches the same form
/// through the full-screen `CreateShootingDayScreen` (issue #624).
Future<void> showCreateShootingDaySheet(
  BuildContext context,
  EpisodeView episode,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CreateShootingDayForm(episodeId: episode.id),
  );
}

/// The Create Shooting Day form body, keyed by the episode id the command
/// sources its `episode_id` from.
///
/// Shared by the in-context sheet ([showCreateShootingDaySheet]) and the
/// quick-create full-screen page (`CreateShootingDayScreen`, issue #624).
/// Owns its controllers in widget state so they dispose exactly when the
/// form unmounts (a `whenComplete` chain would race the sheet's exit
/// transition).
class CreateShootingDayForm extends ConsumerStatefulWidget {
  const CreateShootingDayForm({super.key, required this.episodeId});

  final String episodeId;

  @override
  ConsumerState<CreateShootingDayForm> createState() =>
      _CreateShootingDayFormState();
}

class _CreateShootingDayFormState extends ConsumerState<CreateShootingDayForm> {
  late final TextEditingController _label;
  late final GlobalKey<FormState> _formKey;
  Date? _date;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController();
    _formKey = GlobalKey<FormState>();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Handled: failures surface via the command-error provider (keyed copy
    // in the inline banner below).
    final createResult = await ref
        .read(shootingDaysControllerProvider(widget.episodeId).notifier)
        .create(
          label: _label.text.trim().isEmpty ? null : _label.text.trim(),
          date: _date,
        );
    if (!mounted) return;
    // Stay open on failure: the inline banner renders the failure (the
    // full-screen create page must not pop away its own error surface).
    if (createResult.match((_) => false, (_) => true)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final error = ref.watch(shootingDaysCommandErrorProvider(widget.episodeId));
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                CreateErrorBanner(
                  key: const Key('create-shooting-day-error-banner'),
                  text: shootingDayErrorCopy(l10n, error),
                  dismissKey: const Key('create-shooting-day-error-dismiss'),
                  onDismiss: () => ref
                      .read(
                        shootingDaysCommandErrorProvider(widget.episodeId)
                            .notifier,
                      )
                      .clear(),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                l10n.shootingDayCreateTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextFormField(
                key: const Key('create-shooting-day-label'),
                controller: _label,
                decoration: InputDecoration(
                  labelText: l10n.shootingDayLabelHint,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _date == null
                          ? l10n.shootingDayNoDate
                          : l10n.shootingDayDate('$_date'),
                      key: const Key('create-shooting-day-date-text'),
                    ),
                  ),
                  TextButton(
                    key: const Key('create-shooting-day-date-pick'),
                    onPressed: () async {
                      // Material date utilities localize the picker (no
                      // hand-rolled date math for locale — spec §5).
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _date = picked.toDate());
                      }
                    },
                    child: Text(l10n.shootingDayPickDate),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create-shooting-day-submit'),
                onPressed: _submit,
                child: Text(l10n.blocksCreateButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
