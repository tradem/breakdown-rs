// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'scene_shoots_controller.dart';
import 'scene_shoots_state.dart';
import 'widgets/continuity_strip.dart';

/// `SceneShootsScreen` — the shooting day's scene shoots in server order
/// (`COALESCE(actual_order, planned_order) ASC` — the client never
/// re-sorts).
///
/// Entered from the scene context (scene detail's shooting-days section)
/// with the acted-on [day] and [scene] read DTOs plus the [seasonId]
/// scoping the continuity membership gate. All command context comes from
/// these DTOs — never from a second projection lookup (CQRS boundary).
///
/// Per-shoot start/finish/skip dispatch with the ids and `version` echoed
/// from the acted-on row, optimistic-after-2xx with bounded-retry
/// reconciliation. Ist semantics (status, actual order, day finality from
/// `wrapped_at`) render from the projection only — the client never
/// derives them (D2). Wrapping is a guarded day-level action: the confirm
/// dialog names the consequence and the absence of an undo (D3).
class SceneShootsScreen extends ConsumerWidget {
  const SceneShootsScreen({
    super.key,
    required this.day,
    required this.scene,
    required this.seasonId,
  });

  final ShootingDayView day;
  final SceneView scene;
  final String seasonId;

  SceneShootDayScope get _scope =>
      SceneShootDayScope(dayId: day.id, sceneId: scene.id, seasonId: seasonId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final scope = _scope;
    final state = ref.watch(sceneShootsControllerProvider(scope));
    final controller = ref.read(sceneShootsControllerProvider(scope).notifier);
    final rows = state.rows;
    final notFound = state.notFound;
    final wrapped = day.wrappedAt != null;

    return Scaffold(
      appBar: AppBar(title: Text(day.label ?? 'Shooting day')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('scene-shoot-command-error-banner'),
              text: sceneShootErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('scene-shoots-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          if (wrapped)
            const _Banner(
              key: Key('scene-shoots-wrapped-banner'),
              text: 'This day is wrapped — execution is final and read-only.',
            ),
          Expanded(
            child: notFound != null
                ? _NotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('scene-shoots-loading'),
                        ),
                      ),
                      AsyncError(:final error) when rows.isEmpty =>
                        _FetchErrorView(
                          code: error is ProblemError ? error.code : 'unknown',
                          onRetry: () => controller.refresh(),
                        ),
                      _ =>
                        rows.isEmpty
                            ? ListView(
                                key: const Key('scene-shoots-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  _EmptyView(
                                    onPlan: wrapped
                                        ? null
                                        : () => controller.plan(
                                            plannedOrder: _appendOrderKey(rows),
                                          ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('scene-shoots-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return switch (row) {
                                    ProjectedSceneShootRow(:final shoot) =>
                                      _ShootCard(
                                        shoot: shoot,
                                        scope: scope,
                                        wrapped: wrapped,
                                        onStart: _canStart(shoot) && !wrapped
                                            ? () =>
                                                  controller.start(shoot: shoot)
                                            : null,
                                        onFinish: _canFinish(shoot) && !wrapped
                                            ? () => controller.finish(
                                                shoot: shoot,
                                              )
                                            : null,
                                        onSkip: _canSkip(shoot) && !wrapped
                                            ? () =>
                                                  controller.skip(shoot: shoot)
                                            : null,
                                      ),
                                    OptimisticSceneShootRow(:final overlay) =>
                                      _ShootCard(
                                        shoot: overlay.overlay,
                                        scope: scope,
                                        wrapped: wrapped,
                                        pending: true,
                                        onStart: null,
                                        onFinish: null,
                                        onSkip: null,
                                      ),
                                  };
                                },
                              ),
                    },
                  ),
          ),
          if (!wrapped)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('scene-shoots-wrap'),
                  onPressed: () => _confirmWrap(context, ref, scope),
                  child: const Text('Wrap shooting day'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmWrap(
    BuildContext context,
    WidgetRef ref,
    SceneShootDayScope scope,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('wrap-confirm-dialog'),
        title: const Text('Wrap this shooting day?'),
        content: const Text(
          'Wrapping marks the day as final: started, finished and skipped '
          'states can no longer be changed. This cannot be undone — there '
          'is no unwrap in the contract.',
        ),
        actions: [
          TextButton(
            key: const Key('wrap-cancel-button'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('wrap-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wrap day'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(sceneShootsControllerProvider(scope).notifier)
          .wrap(dayVersion: day.version);
    }
  }
}

/// Whether the shoot offers a start action (planned → in progress).
bool _canStart(SceneShootView shoot) =>
    shoot.status == SceneShootStatus.planned ||
    shoot.status == SceneShootStatus.scheduled;

/// Whether the shoot offers a finish action (in progress → shot).
bool _canFinish(SceneShootView shoot) =>
    shoot.status == SceneShootStatus.inProgress;

/// Whether the shoot offers a skip action (only non-terminal rows).
bool _canSkip(SceneShootView shoot) =>
    shoot.status != SceneShootStatus.shot &&
    shoot.status != SceneShootStatus.skipped;

/// Derives a planned-order key appended after the board projection.
/// The key space is opaque lexicographic (`planned_order`); appending after
/// the last row's key keeps the server sequence stable without renumbering.
String _appendOrderKey(List<SceneShootRow> rows) {
  String? last;
  for (final row in rows) {
    final shoot = switch (row) {
      ProjectedSceneShootRow(:final shoot) => shoot,
      OptimisticSceneShootRow(:final overlay) => overlay.overlay,
    };
    last = shoot.plannedOrder;
  }
  return '${last ?? 'a'}0';
}

/// One day-board card: the scene shoot in sequence with its Ist strip
/// (status chip, actual vs planned position, notes/continuity counts) and
/// the per-shoot execution actions. Renders the read model only.
class _ShootCard extends StatelessWidget {
  const _ShootCard({
    required this.shoot,
    required this.scope,
    required this.wrapped,
    this.pending = false,
    this.onStart,
    this.onFinish,
    this.onSkip,
  });

  final SceneShootView shoot;
  final SceneShootDayScope scope;
  final bool wrapped;
  final bool pending;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Short scene reference: safe truncation (ids are opaque UUIDv7 —
    // tests and short fixtures must never hit a RangeError).
    final sceneRef = shoot.sceneId.length > 8
        ? shoot.sceneId.substring(0, 8)
        : shoot.sceneId;
    return Card(
      key: Key('scene-shoot-card-${shoot.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Scene $sceneRef',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _StatusChip(status: shoot.status),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              shoot.actualOrder != null
                  ? 'Actual ${shoot.actualOrder} (planned ${shoot.plannedOrder})'
                  : 'Planned ${shoot.plannedOrder}',
              key: Key('scene-shoot-order-${shoot.id}'),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${shoot.notes.length} notes · '
              '${shoot.continuityPhotoIds.length} continuity photos',
              style: theme.textTheme.bodySmall,
            ),
            _ShootNotes(shoot: shoot, scope: scope, enabled: !wrapped),
            ContinuityStrip(shoot: shoot, scope: scope, enabled: !wrapped),
            if (!wrapped)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onStart != null)
                    TextButton(
                      key: Key('scene-shoot-start-${shoot.id}'),
                      onPressed: onStart,
                      child: const Text('Start'),
                    ),
                  if (onFinish != null)
                    TextButton(
                      key: Key('scene-shoot-finish-${shoot.id}'),
                      onPressed: onFinish,
                      child: const Text('Finish'),
                    ),
                  if (onSkip != null)
                    TextButton(
                      key: Key('scene-shoot-skip-${shoot.id}'),
                      onPressed: onSkip,
                      child: const Text('Skip'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Notes on the shoot card: free-text list with add/edit/remove,
/// dispatching through the controller with the acted-on row's version.
/// `SerializedNote` carries `{id, body}` only — the backend resolves
/// audit metadata server-side, so no author line renders (the design
/// prose predates the landed contract; the contract wins).
class _ShootNotes extends ConsumerWidget {
  const _ShootNotes({
    required this.shoot,
    required this.scope,
    required this.enabled,
  });

  final SceneShootView shoot;
  final SceneShootDayScope scope;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sceneShootsControllerProvider(scope).notifier);
    return ExpansionTile(
      key: Key('scene-shoot-notes-${shoot.id}'),
      title: Text('Notes (${shoot.notes.length})'),
      children: [
        for (final note in shoot.notes)
          ListTile(
            key: Key('scene-shoot-note-${note.id}'),
            title: Text(note.body),
            trailing: enabled
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('scene-shoot-note-edit-${note.id}'),
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit note',
                        onPressed: () => _editNote(context, controller, note),
                      ),
                      IconButton(
                        key: Key('scene-shoot-note-delete-${note.id}'),
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete note',
                        onPressed: () =>
                            _confirmDelete(context, controller, note),
                      ),
                    ],
                  )
                : null,
          ),
        if (enabled)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('scene-shoot-note-add-${shoot.id}'),
              icon: const Icon(Icons.add),
              label: const Text('Add note'),
              onPressed: () => _addNote(context, controller),
            ),
          ),
      ],
    );
  }

  Future<void> _addNote(
    BuildContext context,
    SceneShootsController controller,
  ) async {
    final body = await _NoteEditorDialog.show(context);
    if (body != null && body.isNotEmpty) {
      await controller.addNote(shoot: shoot, body: body);
    }
  }

  Future<void> _editNote(
    BuildContext context,
    SceneShootsController controller,
    SerializedNote note,
  ) async {
    final body = await _NoteEditorDialog.show(context, initial: note.body);
    if (body != null && body.isNotEmpty && body != note.body) {
      await controller.updateNote(shoot: shoot, noteId: note.id, body: body);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SceneShootsController controller,
    SerializedNote note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('note-delete-confirm-dialog'),
        title: const Text('Delete this note?'),
        content: Text('“${note.body}” will be removed from the shoot.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('note-delete-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeNote(shoot: shoot, noteId: note.id);
    }
  }
}

/// Free-text note editor (add + edit share the dialog; edit prefills).
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.initial});

  final String? initial;

  static Future<String?> show(BuildContext context, {String? initial}) =>
      showDialog<String>(
        context: context,
        builder: (context) => _NoteEditorDialog(initial: initial),
      );

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('note-editor-dialog'),
    title: Text(widget.initial == null ? 'Add note' : 'Edit note'),
    content: TextField(
      key: const Key('note-editor-field'),
      controller: _field,
      autofocus: true,
      maxLines: 4,
      decoration: const InputDecoration(hintText: 'Note text'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('note-editor-save'),
        onPressed: _field.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_field.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Status chip rendering the projection's status verbatim (D2 — the client
/// never derives Ist state).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SceneShootStatus status;

  @override
  Widget build(BuildContext context) {
    // Direct enum comparison (same rationale as `photoRowStatus`):
    // `SceneShootStatus` is a built_value EnumClass, not a sealed enum,
    // so the label resolves through identity checks and renders the
    // projection's status verbatim (D2).
    final label = status == SceneShootStatus.inProgress
        ? 'In progress'
        : status == SceneShootStatus.shot
        ? 'Shot'
        : status == SceneShootStatus.skipped
        ? 'Skipped'
        : status == SceneShootStatus.scheduled
        ? 'Scheduled'
        : 'Planned';
    return Chip(
      key: Key('scene-shoot-status-${status.name}'),
      label: Text(label),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    // Plain banner (same shape as the shooting-days `_Banner`):
    // `MaterialBanner` asserts non-empty actions, so dismissable and
    // static banners share this ColoredBox instead.
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                color: scheme.onErrorContainer,
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({this.onPlan});

  final VoidCallback? onPlan;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('No scene shoots planned for this day yet.'),
      const SizedBox(height: 12),
      if (onPlan != null)
        FilledButton.tonal(
          key: const Key('scene-shoots-plan-first'),
          onPressed: onPlan,
          child: const Text('Plan first shoot'),
        ),
    ],
  );
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, required this.onRetry});

  final String code;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Could not load the day board ($code).'),
        const SizedBox(height: 12),
        FilledButton.tonal(
          key: const Key('scene-shoots-retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({required this.code, required this.onBack});

  final String code;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('No longer available ($code).'),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onBack, child: const Text('Back')),
      ],
    ),
  );
}
