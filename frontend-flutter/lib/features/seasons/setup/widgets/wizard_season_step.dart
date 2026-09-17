// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

import '../../../../design/spacing.dart';
import '../setup_wizard_state.dart';

/// Season step of the setup wizard (task 4.1): the number field with the
/// smart default, the optional name, and the live "Season n" preview.
///
/// Riverpod-free presentation (design D1): data + callbacks in; the text
/// fields' ephemeral editing state is widget state. The number field's
/// validator shows the inline copy keyed on the pure
/// [validatePositiveCount] error code — never a platform dialog.
class WizardSeasonStep extends StatefulWidget {
  const WizardSeasonStep({
    super.key,
    required this.seasonNumber,
    required this.seasonName,
    required this.onNumberChanged,
    required this.onNameChanged,
    required this.onValidityChanged,
  });

  final int seasonNumber;
  final String seasonName;

  /// Commits the parsed number (only called with a valid value).
  final ValueChanged<int> onNumberChanged;

  /// Commits the optional name.
  final ValueChanged<String> onNameChanged;

  /// Reports whether the step currently validates — the screen gates
  /// "Weiter" on it. Validity derives ONLY from the pure validation
  /// functions ([validatePositiveCount]), never widget-local rules.
  final ValueChanged<bool> onValidityChanged;

  @override
  State<WizardSeasonStep> createState() => _WizardSeasonStepState();
}

class _WizardSeasonStepState extends State<WizardSeasonStep> {
  late final TextEditingController _number;
  late final TextEditingController _name;

  /// The parsed validity of the number field (inline error copy source).
  WizardFieldError? _numberError;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: '${widget.seasonNumber}');
    _name = TextEditingController(text: widget.seasonName);
    _numberError = validatePositiveCount(_number.text);
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WizardSeasonStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A seeded/programmatically-changed number must land in the field
    // (the smart default seeds one frame after the first build); user
    // typing already matches and is therefore a no-op.
    final newText = '${widget.seasonNumber}';
    if (widget.seasonNumber != oldWidget.seasonNumber &&
        _number.text != newText) {
      _number.text = newText;
      _number.selection = TextSelection.collapsed(offset: _number.text.length);
    }
  }

  void _onNumberChanged(String raw) {
    final error = validatePositiveCount(raw);
    setState(() => _numberError = error);
    widget.onValidityChanged(error == null);
    final value = int.tryParse(raw.trim());
    if (error == null && value != null) widget.onNumberChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('wizard-step-season'),
      padding: const EdgeInsets.all(AppSpacing.space16),
      children: [
        TextFormField(
          key: const Key('wizard-number-field'),
          controller: _number,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Nummer',
            errorText: _numberError == null
                ? null
                : wizardErrorCopyForField(_numberError!),
          ),
          onChanged: _onNumberChanged,
        ),
        const SizedBox(height: AppSpacing.space16),
        TextFormField(
          key: const Key('wizard-name-field'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name (optional)'),
          onChanged: widget.onNameChanged,
        ),
        const SizedBox(height: AppSpacing.space24),
        // Live preview of the resulting season title (glossary
        // `wizard.season.preview`): number + optional name.
        Text(
          _preview,
          key: const Key('wizard-live-preview'),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }

  String get _preview {
    final name = widget.seasonName.trim();
    return name.isEmpty
        ? 'Season ${widget.seasonNumber}'
        : 'Season ${widget.seasonNumber} · $name';
  }
}
