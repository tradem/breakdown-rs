// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import 'seasons_controller.dart';

/// Opens the bottom-sheet manual Create Season form (task 3.2).
///
/// The manual/advanced create path (issue #511): the guided setup wizard
/// is the primary entry (seasons-home FAB), this sheet is the
/// alternative reached from the app bar's "Manuell" action. The series
/// is derived from the build config — never asked for.
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

/// The manual Create Season form.
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
  final _numberController = TextEditingController();
  final _titleController = TextEditingController();
  bool _busy = false;

  /// The build-misconfiguration guard (issue #511): the manual form no
  /// longer asks for a series id — it derives the env-sourced default.
  /// A build without `--dart-define=DEFAULT_SERIES_ID` therefore cannot
  /// create a season at all; the form says so instead of dispatching a
  /// request the backend can only answer with a blind validation error.
  /// Same problem `code` and copy as the wizard's pre-dispatch guard.
  bool _seriesIdMissing() =>
      ref.read(appConfigProvider).defaultSeriesId.trim().isEmpty;

  @override
  void dispose() {
    _numberController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Defensive only: the submit button is disabled while the build has no
    // default series (the notice renders instead).
    if (_seriesIdMissing()) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final number = int.parse(_numberController.text.trim());
    setState(() => _busy = true);
    // Command dispatch; failures surface through the screen's
    // `commandError` banner keyed on the stable problem code (D3), so on
    // both Ok and Err the sheet simply closes.
    final result = await ref
        .read(seasonsControllerProvider.notifier)
        .create(
          // Derived from the active build config (never a user input —
          // internal ids are not user-editable, issue #511). Never a
          // second projection lookup (CQRS boundary): the series is the
          // build's active project context.
          seriesId: ref.read(appConfigProvider).defaultSeriesId.trim(),
          number: number,
          title: _titleController.text.trim(),
        );
    // Explicitly consumed: Err is already surfaced by the screen's
    // code-keyed banner (state), Ok is already visible as the optimistic
    // overlay row — neither branch needs a local reaction here.
    result.match<void>((_) {}, (_) {});
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable so the form stays reachable on short screens / with the
    // soft keyboard open (the sheet itself is unbounded with
    // isScrollControlled).
    final missingSeriesId = _seriesIdMissing();
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
                l10nOf(context).createSeasonTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              // Build-misconfiguration notice (issue #511): shown instead
              // of the removed series-id field; the submit stays disabled.
              if (missingSeriesId) ...[
                const SizedBox(height: 16),
                Text(
                  l10nOf(context).seasonsCreateSeriesIdMissing,
                  key: const Key('create-series-id-missing'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-number'),
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10nOf(context).blocksNumberLabel,
                ),
                validator: (v) => int.tryParse((v ?? '').trim()) == null
                    ? l10nOf(context).blocksNumberRequired
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create-title'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10nOf(context).createSeasonTitleLabel,
                ),
              ),
              const SizedBox(height: 16),
              // The guided setup is the PRIMARY path (issue #511 — the
              // seasons-home FAB); this sheet is the manual alternative,
              // so the submit is the only action left here.
              FilledButton(
                key: const Key('create-submit'),
                onPressed: _busy || missingSeriesId ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10nOf(context).blocksCreateButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
