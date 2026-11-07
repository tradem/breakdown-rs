// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../design/scene_mood_label.dart';
import '../../design/spacing.dart';
import '../../design/gen/design_tokens.g.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';

/// A submitted edit-sheet payload: the full `SceneDetails` the sheet would
/// dispatch, with the `version` echo resolved by the caller (the sheet never
/// invents locking state — it receives the acted-on read DTO).
class SceneEditResult {
  const SceneEditResult({required this.details});

  final SceneDetails details;
}

/// „Szene bearbeiten" sheet (issue #834): ONE sheet for every editable
/// scene field — number, location, mood, script day, synopsis — dispatched
/// through `SceneRepository.updateDetails` by the CALLER with the `version`
/// echoed from the acted-on `SceneView` (optimistic locking, #473).
///
/// Mood input is STRUCTURED (issue #834 decision): the canonical set as
/// chips ([canonicalSceneMoods]) plus a free-text fallback. An existing
/// value OUTSIDE the canonical set renders as its own selected chip next to
/// the canonical options and is never destroyed by a save — selecting a
/// canonical chip replaces it, clearing the selection restores the free
/// text, and saving with no selection saves `null`.
///
/// Number editing warns but invents no rule: the backend holds no
/// uniqueness/ordering invariant on `(episode, scene_number)`, so the sheet
/// carries a hint line instead of a fake validation. Unparseable input is
/// rejected BEFORE closing — an invalid number must never silently clear
/// the stored one (CodeRabbit #868).
///
/// The sheet dispatches through [onSubmit] and stays OPEN on failure: the
/// localized error renders inside the sheet and the DRAFT survives
/// (CodeRabbit #868 — a network failure must not discard the user's edit).
/// It closes only on success; returns `null` when dismissed.
Future<SceneEditResult?> showSceneEditSheet(
  BuildContext context,
  SceneView scene, {
  required Future<String?> Function(SceneEditResult result) onSubmit,
}) => showModalBottomSheet<SceneEditResult>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  builder: (_) => SceneEditSheet(scene: scene, onSubmit: onSubmit),
);

class SceneEditSheet extends StatefulWidget {
  const SceneEditSheet({
    super.key,
    required this.scene,
    required this.onSubmit,
  });

  final SceneView scene;

  /// Dispatches the payload; returns the localized error copy on failure,
  /// `null` on success. While the future resolves non-null the sheet keeps
  /// its state (and shows the error) — the user can correct and retry.
  final Future<String?> Function(SceneEditResult result) onSubmit;

  @override
  State<SceneEditSheet> createState() => _SceneEditSheetState();
}

class _SceneEditSheetState extends State<SceneEditSheet> {
  late final TextEditingController _number;
  late final TextEditingController _location;
  late final TextEditingController _mood;
  late final TextEditingController _scriptDay;
  late final TextEditingController _summary;

  /// The mood chip selection: the stored value VERBATIM (a canonical
  /// shorthand OR an unrecognized value — untrimmed, so a save that touches
  /// nothing else echoes it byte-for-byte, CodeRabbit #868) or a chip the
  /// user picked. Never `null` while the stored mood exists, so the editor
  /// cannot silently drop an unrecognized value.
  String? _selectedMood;

  /// Localized failure copy of the last submit — rendered INSIDE the sheet
  /// so a failed save keeps the draft editable (CodeRabbit #868).
  String? _error;
  bool _submitting = false;
  String? _numberError;

  @override
  void initState() {
    super.initState();
    final scene = widget.scene;
    _number = TextEditingController(text: scene.sceneNumber?.toString() ?? '');
    _location = TextEditingController(text: scene.location ?? '');
    _mood = TextEditingController(text: scene.mood ?? '');
    _scriptDay = TextEditingController(text: scene.scriptDay ?? '');
    _summary = TextEditingController(text: scene.summary ?? '');
    final stored = scene.mood?.trim();
    if (stored != null && stored.isNotEmpty) {
      // A non-canonical stored mood keeps its OWN chip selected — it stays
      // selectable and the save echoes it verbatim unless the user picks a
      // canonical shorthand (issue #834: never destroy a stored value).
      _selectedMood = scene.mood;
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _location.dispose();
    _mood.dispose();
    _scriptDay.dispose();
    _summary.dispose();
    super.dispose();
  }

  void _selectMood(String? mood) {
    setState(() {
      // Deselect: the field must not keep secretly submitting the chip's
      // value (CodeRabbit #868) — clear it when it still holds the chip's
      // text, keep the user's own text when they already edited past it.
      if (mood == null && _mood.text == _selectedMood) {
        _mood.clear();
      }
      _selectedMood = mood;
      if (mood != null) {
        // The canonical chips and the free-text field stay in sync: picking
        // a chip fills the field; editing the field drops the chip.
        _mood.text = mood;
      }
    });
  }

  /// Parses the number field: `null` input clears the stored number (the
  /// intentional case), unparseable NON-empty input is a validation error
  /// that must NOT silently clear the stored number (CodeRabbit #868).
  int? _parseNumber() {
    final numberText = _number.text.trim();
    if (numberText.isEmpty) return null;
    return int.tryParse(numberText);
  }

  SceneDetails _buildDetails() {
    final number = _parseNumber();
    final mood = _selectedMood ?? _mood.text.trim().nullIfEmpty;
    return SceneDetails(
      (b) => b
        ..sceneNumber = number
        ..location = _location.text.trim().nullIfEmpty
        // Preserve the aggregate-owned schedule flag from the read DTO: the
        // sheet edits details, not scheduling.
        ..isScheduleSet = widget.scene.isScheduleSet
        ..summary = _summary.text.trim().nullIfEmpty
        ..scriptDay = _scriptDay.text.trim().nullIfEmpty
        // Echo the read DTO's Decision-Model scores verbatim (issue #834):
        // the projector ignores them on update, so this is provenance
        // hygiene — the sheet must not be the place that drops them.
        ..sceneScore = widget.scene.sceneScore
        ..synopsisScore = widget.scene.synopsisScore
        ..mood = mood,
    );
  }

  Future<void> _submit() async {
    final l10n = l10nOf(context);
    final numberText = _number.text.trim();
    if (numberText.isNotEmpty && _parseNumber() == null) {
      setState(() {
        _numberError = l10n.sceneDetailEditNumberError;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _numberError = null;
    });
    final error = await widget.onSubmit(
      SceneEditResult(details: _buildDetails()),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      // Success closes the sheet; failure keeps it open with the DRAFT
      // intact and the localized error inside (CodeRabbit #868).
      _error = error;
    });
    if (error == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Padding(
      // Keyboard-safe inset: the sheet scrolls above the software keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          key: const Key('scene-edit-sheet'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sceneDetailEditTooltip,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            // Failed submits render INSIDE the sheet — the draft survives
            // and stays editable (CodeRabbit #868).
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space8),
              Material(
                key: const Key('scene-edit-error'),
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(
                  DesignTokens.sizeRadiusSmall,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: AppSpacing.space8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.space16),
            TextFormField(
              key: const Key('scene-edit-number'),
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditNumber,
                helperText: l10n.sceneDetailEditNumberHint,
                errorText: _numberError,
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            TextFormField(
              key: const Key('scene-edit-location'),
              controller: _location,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditLocation,
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(
              l10n.sceneDetailEditMood,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.space8),
            Wrap(
              key: const Key('scene-edit-mood-chips'),
              spacing: AppSpacing.space8,
              runSpacing: AppSpacing.space8,
              children: [
                for (final mood in canonicalSceneMoods) _moodChip(mood, l10n),
                // A stored value outside the canonical set stays selectable
                // — its own chip, rendered like any other (issue #834: an
                // unrecognized stored value is never destroyed).
                if (_selectedMood != null &&
                    !canonicalSceneMoods.contains(_selectedMood))
                  _moodChip(_selectedMood!, l10n),
              ],
            ),
            const SizedBox(height: AppSpacing.space12),
            TextFormField(
              key: const Key('scene-edit-mood-custom'),
              controller: _mood,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditMoodCustom,
              ),
              onChanged: (_) {
                // Free-text edits drop the chip selection (the field wins).
                if (_selectedMood != _mood.text.trim() &&
                    _selectedMood != null) {
                  setState(() => _selectedMood = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.space12),
            TextFormField(
              key: const Key('scene-edit-script-day'),
              controller: _scriptDay,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditScriptDay,
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            TextFormField(
              key: const Key('scene-edit-summary'),
              controller: _summary,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditSummary,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('scene-edit-cancel'),
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: AppSpacing.space8),
                FilledButton(
                  key: const Key('scene-edit-save'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.commonSave),
                ),
              ],
            ),
            // Keep the save row clear of the home indicator.
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _moodChip(String mood, AppLocalizations l10n) => FilterChip(
    key: Key('scene-edit-mood-$mood'),
    label: Text(mood),
    selected: _selectedMood == mood,
    // The chip's face is the shorthand itself; the parser's icons would
    // duplicate the [SceneMoodLabel] reinforcement rule in an input
    // surface — the sheet stays text-only (icons reinforce visible text,
    // glossary rule).
    tooltip: l10n.sceneMood(mood),
    onSelected: (selected) => _selectMood(selected ? mood : null),
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
