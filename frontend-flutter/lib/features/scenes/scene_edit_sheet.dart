// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../design/scene_mood_label.dart';
import '../../design/spacing.dart';
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
/// carries a hint line instead of a fake validation.
///
/// Returns `null` when dismissed; otherwise a [SceneEditResult].
Future<SceneEditResult?> showSceneEditSheet(
  BuildContext context,
  SceneView scene,
) => showModalBottomSheet<SceneEditResult>(
  context: context,
  isScrollControlled: true,
  builder: (_) => SceneEditSheet(scene: scene),
);

class SceneEditSheet extends StatefulWidget {
  const SceneEditSheet({super.key, required this.scene});

  final SceneView scene;

  @override
  State<SceneEditSheet> createState() => _SceneEditSheetState();
}

class _SceneEditSheetState extends State<SceneEditSheet> {
  late final TextEditingController _number;
  late final TextEditingController _location;
  late final TextEditingController _mood;
  late final TextEditingController _scriptDay;
  late final TextEditingController _summary;

  /// The mood chip selection: a value from [canonicalSceneMoods] OR the
  /// stored (non-canonical) value — never `null` while the stored mood
  /// exists, so the editor cannot silently drop an unrecognized value.
  String? _selectedMood;

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
      _selectedMood = stored;
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
      _selectedMood = mood;
      if (mood != null) {
        // The canonical chips and the free-text field stay in sync: picking
        // a chip fills the field; editing the field drops the chip.
        _mood.text = mood;
      }
    });
  }

  SceneDetails _buildDetails() {
    final numberText = _number.text.trim();
    final number = numberText.isEmpty ? null : int.tryParse(numberText);
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
            const SizedBox(height: AppSpacing.space16),
            TextFormField(
              key: const Key('scene-edit-number'),
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailEditNumber,
                helperText: l10n.sceneDetailEditNumberHint,
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: AppSpacing.space8),
                FilledButton(
                  key: const Key('scene-edit-save'),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(SceneEditResult(details: _buildDetails())),
                  child: Text(l10n.commonSave),
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
