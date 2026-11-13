// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../design/components/ai_provenance_badge.dart';
import '../../design/components/ai_score_stars.dart';
import '../../design/components/section_card.dart';
import '../../design/material_icons.dart';
import '../../design/scene_mood_label.dart';
import '../../design/spacing.dart';
import '../../domain/ai_provenance.dart';
import '../../l10n/app_localizations_provider.dart';
import '../characters/characters_controller.dart';
import '../characters/role_extract_screen.dart';
import '../outfits/outfits_controller.dart';
import '../pieces/piece_identity.dart';
import '../pieces/widgets/pieces_widgets.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../scene_shoots/scene_shoots_screen.dart';
import '../shell/planning_location.dart';
import '../shooting_days/create_shooting_day_sheet.dart';
import '../shooting_days/shooting_days_controller.dart';
import 'pick_outfit_sheet.dart';
import 'scene_beats.dart';
import 'scene_edit_sheet.dart';
import 'scenes_controller.dart';
import 'scenes_state.dart';
import '../../design/components/breakdown_app_bar.dart';

/// `SceneDetailScreen` — compact header + divider-free, collapsed-by-default
/// sections (issue #834 redesign; design §4).
///
/// The Phase 1 scenes screen keeps two sections here:
/// * **Characters** (5.2): assigned characters resolved from
///   `SceneView.assignedCharacters` ids via the characters projection
///   (read-DTO join only — never aggregate reconstruction); assign (picker
///   over the season's characters, scene `version` from the acted-on
///   `SceneView`) and unassign (DELETE), optimistic-after-2xx on the scene
///   row's id list.
/// * **Shooting days** (6.2): scheduled days from
///   `SceneView.shootingDayIds` via the episode's day projection; schedule
///   (picker over the parent episode's not-yet-archived days, scene
///   version echo) and unschedule (DELETE), optimistic-after-2xx.
///
/// Any Soll/Ist affordance is absent rather than stubbed (D6 — the
/// follow-up `flutter-shoot-day-execution` owns it).
///
/// Pushed with the navigation-stack context ([seasonId] + [episode] +
/// [sceneId]); all ids come from the read DTOs the user acted on (never a
/// second projection lookup to fill in command context — CQRS boundary).
/// The parent [EpisodeView] rides along for the same reason: the shooting-
/// day empty-state affordance (issue #669) opens the quick-create form
/// sourced from the DTO the user navigated from, not a re-fetch.
class SceneDetailScreen extends ConsumerWidget {
  const SceneDetailScreen({
    super.key,
    required this.seasonId,
    required this.episode,
    required this.sceneId,
  });

  final String seasonId;
  final EpisodeView episode;
  String get episodeId => episode.id;
  final String sceneId;

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
    final scenesState = ref.watch(scenesControllerProvider(episodeId));
    final scene = _resolveScene(scenesState);

    return Scaffold(
      appBar: BreakdownAppBar(
        // „Szene {n}" — the summary is page content, never the app-bar
        // title (issue #834: a whole sentence clipped into the bar read
        // like a bug).
        title: scene == null
            ? l10nOf(context).sceneDetailTitleFallback
            : l10nOf(context).sceneDetailTitle('${scene.sceneNumber ?? ''}'),
        actions: [
          if (scene != null)
            IconButton(
              key: const Key('scene-detail-edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10nOf(context).sceneDetailEditTooltip,
              onPressed: () => _openEditor(context, ref, scene),
            ),
        ],
      ),
      body: switch ((scene, scenesState.projected)) {
        // Resolved scene with its collapsible sections.
        (final s?, _) => _SceneDetailBody(
          seasonId: seasonId,
          episode: episode,
          scene: s,
        ),
        // First snapshot still in flight.
        (null, AsyncLoading()) => const Center(
          child: CircularProgressIndicator(key: Key('scene-detail-loading')),
        ),
        // Settled with an error and no retained row: retry affordance.
        (null, AsyncError(:final error)) => _SceneDetailErrorView(
          code: error is ProblemError ? error.code : 'unknown',
          onRetry: () =>
              ref.read(scenesControllerProvider(episodeId).notifier).refresh(),
        ),
        // Settled without the scene (deleted): unavailable, not a spinner.
        (null, _) => _SceneDetailGoneView(
          onBack: () => Navigator.of(context).pop(),
        ),
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    SceneView scene,
  ) async {
    // The l10n object is captured BEFORE the await: the screen can unmount
    // while the dispatch is in flight (sign-out pops to the first route)
    // and a post-await `l10nOf(context)` would touch a defunct context
    // (CodeRabbit #868 re-review).
    final l10n = l10nOf(context);
    // The sheet dispatches THROUGH this callback and stays open on failure
    // (the draft survives, the localized error renders inside — CodeRabbit
    // #868). The version echo MUST come from the SNAPSHOT THE DRAFT WAS
    // BUILT FROM: resolving a newer cached row at submission time would
    // attach a version the user never saw to a stale draft — the classic
    // lost-update path (CodeRabbit #868 re-review). A version mismatch
    // surfaces as the localized conflict narrative instead; the user then
    // reopens the sheet on the refreshed projection. The controller runs
    // the client-side AUTHZ-GATE, the details overlay and the bounded
    // refetch.
    await showSceneEditSheet(
      context,
      scene,
      onSubmit: (result) async {
        final err = await ref
            .read(scenesControllerProvider(episodeId).notifier)
            .updateDetails(scene: scene, details: result.details);
        return err.fold(
          (problem) => sceneUpdateErrorCopy(l10n, problem),
          (_) => null,
        );
      },
    );
  }

  SceneView? _resolveScene(ScenesScreenState state) {
    for (final s in state.cachedRows) {
      if (s.id == sceneId) return s;
    }
    return null;
  }
}

/// The scene's body: identity, synopsis, then the two operational sections —
/// **shooting days FIRST** (a scene is planned before it is cast, and the day
/// is what the dispo is built from), then the merged cast/look table (issue
/// #834 follow-up).
///
/// It owns the day-candidate resolution because two places need it: the
/// section's own actions and the script-day chip in the header, which binds the
/// day the SCRIPT states ("Tag 1") to a real shooting day of this episode. One
/// list feeds both, so the affordances cannot disagree about what is available.
class _SceneDetailBody extends ConsumerWidget {
  const _SceneDetailBody({
    required this.seasonId,
    required this.episode,
    required this.scene,
  });

  final String seasonId;
  final EpisodeView episode;
  final SceneView scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(shootingDaysViewProvider(episode.id));
    final candidates = _realDayCandidates(days.rows, scene);
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(scenesControllerProvider(episode.id).notifier).refresh(),
      child: ListView(
        key: Key('scene-detail-${scene.id}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Page identity, not a tile (issue #834): no card border around the
          // header block. The script day's assign affordance lives on the chip.
          _SceneHeader(
            scene: scene,
            onAssignScriptDay: candidates.isEmpty
                ? null
                : () => unawaited(
                    _pickDayAndSchedule(
                      context,
                      ref,
                      episodeId: episode.id,
                      scene: scene,
                      candidates: candidates,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.space12),
          _SceneSynopsisSection(scene: scene),
          const SizedBox(height: AppSpacing.space8),
          _SceneShootingDaysSection(
            seasonId: seasonId,
            episode: episode,
            scene: scene,
            candidates: candidates,
          ),
          const SizedBox(height: AppSpacing.space8),
          _SceneCastLooksSection(
            seasonId: seasonId,
            episodeId: episode.id,
            scene: scene,
          ),
        ],
      ),
    );
  }
}

/// The identity block (issue #834): the number as a large numeral, the
/// location as the title line, and the metadata chip row — mood (#721
/// icons), script day, geplant/ungeplant, and the AI-provenance badge from
/// `SceneView.source`. No card border: this reads as page identity.
class _SceneHeader extends StatelessWidget {
  const _SceneHeader({required this.scene, this.onAssignScriptDay});

  final SceneView scene;

  /// Binds the day the SCRIPT states ("Tag 1") to a **real** shooting day of
  /// the episode (issue #834 follow-up): the chip is the only place the script's
  /// own wording is visible, so the affordance that maps it onto a planned day
  /// belongs next to it — not only inside the days section, which a scene
  /// without a day never shows. `null` disables it (no candidate day, or the
  /// day projection is unreadable): the icon never opens a picker that cannot
  /// offer anything.
  final VoidCallback? onAssignScriptDay;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Column(
      key: const Key('scene-detail-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${scene.sceneNumber ?? ""}',
          key: const Key('scene-detail-header-number'),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        if (scene.location case final location?)
          Text(
            location,
            key: const Key('scene-detail-header-location'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        const SizedBox(height: AppSpacing.space8),
        Wrap(
          key: const Key('scene-detail-header-chips'),
          spacing: AppSpacing.space8,
          runSpacing: AppSpacing.space4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Set-shorthand mood with its reinforcing icons (issue #721):
            // the icons render NEXT TO the visible text, never instead of it.
            if (scene.mood case final mood?)
              SceneMoodLabel(
                key: Key('scene-mood-${scene.id}'),
                mood: mood,
                label: l10n.sceneMood(mood),
              ),
            if (scene.scriptDay case final day?)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderChip(label: l10n.sceneDay(day)),
                  IconButton(
                    key: Key('scene-script-day-assign-${scene.id}'),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    tooltip: l10n.sceneDetailAssignScriptDayTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: onAssignScriptDay,
                  ),
                ],
              ),
            _HeaderChip(
              key: Key('scene-schedule-flag-${scene.id}'),
              label: scene.isScheduleSet
                  ? l10n.sceneScheduled
                  : l10n.sceneUnscheduled,
            ),
            // EU-AI-Act provenance (issue #834): the shared badge keyed on
            // the read DTO's discriminator; Manual/absent render nothing.
            switch (sceneProvenance(scene.source_)) {
              AiProvenanceVariant.aiExtracted => AiProvenanceBadge(
                semanticKey: 'scene-ai-badge-${scene.id}',
              ),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ],
    );
  }
}

/// One metadata chip of the header row: a bordered pill on
/// `surfaceContainerHigh` — tokens only, no inline colors.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.space8,
      vertical: AppSpacing.space2,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

/// The synopsis section (issue #834): the full summary in its own area —
/// NOT the app-bar title — with the AI-provenance badge when applicable,
/// the persisted Decision-Model ratings ([AiScoreStars]; absent values
/// render nothing, never a fabricated star), and the honest „Keine
/// Synopsis" empty state.
class _SceneSynopsisSection extends StatelessWidget {
  const _SceneSynopsisSection({required this.scene});

  final SceneView scene;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final summary = scene.summary;
    final hasScores = scene.sceneScore != null || scene.synopsisScore != null;
    return Card(
      key: Key('scene-synopsis-${scene.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space12),
        child: Column(
          key: const Key('scene-synopsis-body'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap, not Row+Spacer: on a narrow screen with enlarged text,
            // the badge wraps BELOW the title instead of overflowing the
            // heading (CodeRabbit #868).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: AppSpacing.space4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.sceneDetailSynopsisTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                switch (sceneProvenance(scene.source_)) {
                  AiProvenanceVariant.aiExtracted => AiProvenanceBadge(
                    semanticKey: 'scene-synopsis-ai-badge-${scene.id}',
                  ),
                  _ => const SizedBox.shrink(),
                },
              ],
            ),
            const SizedBox(height: AppSpacing.space8),
            if (summary == null || summary.isEmpty)
              Text(
                l10n.sceneDetailNoSynopsis,
                key: const Key('scene-synopsis-empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Text(
                summary,
                key: const Key('scene-synopsis-text'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            // The Decision-Model ratings (issue #834): one star row per
            // PRESENT score — `AiScoreStars` renders nothing for `null`, so
            // an unscored scene shows no stars at all (honest absence).
            if (hasScores) ...[
              const SizedBox(height: AppSpacing.space8),
              if (scene.synopsisScore case final score?)
                Row(
                  key: const Key('scene-synopsis-rating-synopsis'),
                  children: [
                    Text(
                      l10n.sceneDetailRatingSynopsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    AiScoreStars(score: score),
                  ],
                ),
              if (scene.sceneScore case final score?) ...[
                const SizedBox(height: AppSpacing.space4),
                Row(
                  key: const Key('scene-synopsis-rating-scene'),
                  children: [
                    Text(
                      l10n.sceneDetailRatingScene,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: AppSpacing.space4),
                    AiScoreStars(score: score),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The scene's CAST: one row per (figure, look) — the figure and the look it
/// wears in THIS scene in the same table row (issue #834 follow-up).
///
/// The separate "Figuren" and "Looks" sections made the reader join two lists
/// by hand: a look row named only the look, and a figure without a look was a
/// dead end one section away from the affordance that fixes it. One card
/// answers both questions at a glance, and the header keeps both counts
/// ("Figuren (2) · Looks (3)") so even the collapsed state is informative.
///
/// A figure with several looks (a change inside the scene) renders one row per
/// look: the first carries the figure's own actions (edit in the Cast view,
/// remove from the scene), every further row is its change step (`→`), and each
/// look row carries its own removal — both targets stay removable, and the
/// counts stay honest.
///
/// // AUTHZ-GATE: assign/unassign and the beat commands run the membership
/// capability check inside the controllers BEFORE any network call (same
/// send-as-read story as the piece-assign surface).
class _SceneCastLooksSection extends ConsumerWidget {
  const _SceneCastLooksSection({
    required this.seasonId,
    required this.episodeId,
    required this.scene,
  });

  final String seasonId;
  final String episodeId;
  final SceneView scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final characters = ref.watch(charactersViewProvider(seasonId));
    final names = {for (final c in characters.rows) c.id: c.name};
    // Defensive dedup (issue #550): the read-model fan-out is fixed
    // backend-side, but a future regression must not render a contradictory
    // screen — count, rows and the picker filter share one distinct list.
    final groups = groupSceneBeats(
      assignedCharacters: scene.assignedCharacters,
      beats: scene.outfitBeats?.toList() ?? const [],
    );
    final lookCount = [for (final g in groups) ...g.beats].length;
    final assigned = scene.assignedCharacters.toSet();
    final hasCandidates = characters.rows.any((c) => !assigned.contains(c.id));
    // The Cast route dispatches commands that take a `SeasonView`. Every
    // hierarchy push carries the acted-on `SeasonView` in its route
    // `SceneLocation` (CQRS boundary — zero extra reads); direct-pumped tests
    // and cold routes fall back to the fenced `seasonsView` cache/list
    // projection. `null` disables the edit icon without hiding it.
    final routeLocation = locationFromArguments(
      ModalRoute.of(context)?.settings.arguments,
    );
    final routeSeason = switch (routeLocation) {
      SceneLocation(:final season) when season.id == seasonId => season,
      _ => null,
    };
    final season =
        routeSeason ??
        ref.watch(seasonsView).rows.where((s) => s.id == seasonId).firstOrNull;
    // Ephemeral reconciliation indicator for this scene's optimistic beat
    // overlay (reconciling spinner / stale cloud-off + warning).
    final beatOverlay = ref
        .watch(scenesControllerProvider(episodeId))
        .beatOverlays
        .where((o) => o.id == scene.id)
        .firstOrNull;

    // One table row per (figure, look) — flattened out of the groups so the
    // zebra banding has ONE index source: a figure's change steps are its own
    // rows, exactly as the reader counts them (issue #902).
    final rows = <_CastRowSpec>[
      for (final group in groups)
        if (group.beats.isEmpty)
          _CastRowSpec(group: group)
        else
          for (var index = 0; index < group.beats.length; index++)
            _CastRowSpec(group: group, beatIndex: index),
    ];

    // Always-visible section (issue #902): the cast is page CONTENT ("who is
    // in this scene, in which look"), not a secondary detail that earns
    // collapsing. A cold open shows the table, and the counts stay in the
    // header where the reader looks for them. `SectionCard` keeps its
    // no-divider contract for the sections that legitimately collapse (the
    // shooting days).
    return Column(
      key: Key('scene-cast-${scene.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sceneDetailCastTitle('${groups.length}', '$lookCount'),
          key: const Key('scene-cast-title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.space8),
        Card(
          key: const Key('scene-cast-table'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          // Table chrome from `ColorScheme` roles ONLY (issue #902, AGENTS
          // §9): the card sits ON the page surface, so the label band and the
          // zebra rows carry the structure. In dark mode the M3 default card
          // colour (`surfaceContainerLow`) is indistinguishable from
          // `surface` — that was the reported defect.
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              const _CastTableHeader(),
              if (groups.isEmpty)
                ListTile(
                  key: const Key('scene-cast-empty'),
                  title: Text(l10n.sceneDetailNoCharacters),
                )
              else
                for (final (index, spec) in rows.indexed)
                  _castRowWidget(
                    context,
                    ref,
                    spec: spec,
                    zebra: index.isOdd,
                    names: names,
                    season: season,
                  ),
            ],
          ),
        ),
        if (beatOverlay != null &&
            beatOverlay.status != OverlayStatus.acknowledged) ...[
          // The status is a TABLE-level row, never a cell: it renders BELOW
          // the table, separated from it (issue #902).
          const SizedBox(height: AppSpacing.space4),
          ListTile(
            key: const Key('scene-pieces-overlay-status'),
            leading: beatOverlay.status == OverlayStatus.stale
                ? const Icon(
                    Icons.cloud_off,
                    key: Key('scene-pieces-overlay-warning'),
                  )
                : const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            // Status-specific copy keyed on the overlay status: the
            // "Created" stale warning would lie for piece updates and
            // removals, and the raw `warning` CODE is never user copy.
            title: Text(
              beatOverlay.status == OverlayStatus.stale
                  ? l10n.sceneBeatOverlayStale
                  : l10n.sceneBeatOverlaySyncing,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.space8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: Key('scene-character-assign-${scene.id}'),
              onPressed: hasCandidates
                  ? () => _assignFigureAndLook(context, ref, characters.rows)
                  : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.sceneDetailAssignCharacterAndLook),
            ),
          ),
        ),
      ],
    );
  }

  /// One rendered row of the cast table (issue #902).
  ///
  /// The figure's own actions (Bearbeiten, Figur entfernen) belong to its FIRST
  /// row; every row can add a look (the command appends the beat, so the row
  /// that opened the menu does not change the outcome) and every row that
  /// carries a beat can remove exactly THAT beat.
  Widget _castRowWidget(
    BuildContext context,
    WidgetRef ref, {
    required _CastRowSpec spec,
    required bool zebra,
    required Map<String, String> names,
    required SeasonView? season,
  }) {
    final l10n = l10nOf(context);
    final group = spec.group;
    final beatIndex = spec.beatIndex;
    final beat = beatIndex == null ? null : group.beats[beatIndex];
    return _CastRow(
      characterId: group.characterId,
      characterName:
          names[group.characterId] ?? l10n.sceneDetailUnknownCharacter,
      isFirstRow: beatIndex == null || beatIndex == 0,
      beatOrder: beat?.order,
      zebra: zebra,
      lookLabel: beat == null
          ? l10n.sceneDetailNoOutfitInScene
          : sceneBeatOutfitLabel(
              outfitName: beat.outfitName,
              genericFallback: l10n.pieceTileLabelFallback,
            ),
      lookKey: beat == null
          ? Key('scene-piece-empty-${group.characterId}')
          : null,
      lookIsPlaceholder: beat == null,
      lookIcon: beat == null
          ? null
          : BreakdownMaterialIcons.forCostumeCategory(beat.outfitName),
      lookNote: beat?.note,
      changeArrow: beat != null && beat.order > 0,
      // `null` renders the menu item DISABLED (never absent) when no
      // `SeasonView` resolves — an absent control is indistinguishable from
      // "not supported".
      onEdit: beatIndex == null || beatIndex == 0
          ? (season == null
                ? null
                : () => _openCharacter(context, ref, season, group))
          : null,
      onRemoveCharacter: beatIndex == null || beatIndex == 0
          ? () => _confirmRemoveCharacter(
              context,
              ref,
              group.characterId,
              names[group.characterId],
            )
          : null,
      onRemoveLook: beat == null
          ? null
          : () => _confirmRemoveLook(context, ref, group, beat),
      onAddLook: () => _assignLook(
        context,
        ref,
        group.characterId,
        names[group.characterId],
      ),
      addLookLabel: beat == null
          ? l10n.sceneDetailAssignOutfit
          : l10n.sceneDetailAddChange,
    );
  }

  /// Opens the figure's Cast screen (the character detail behind the Cast
  /// view's entry point, issue #611) so the look itself is edited where looks
  /// live. On return the scene projection is refreshed: a renamed or removed
  /// look must not keep rendering its old label here.
  Future<void> _openCharacter(
    BuildContext context,
    WidgetRef ref,
    SeasonView season,
    SceneBeatGroup group,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RoleExtractScreen(season: season, characterId: group.characterId),
      ),
    );
    if (!context.mounted) return;
    await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
  }

  /// The ONE assign flow of this section: figure first, then its look.
  ///
  /// The two commands stay two commands (a figure can legitimately be cast
  /// without a look — the planner knows the role, not yet the costume), so a
  /// cancelled look picker leaves the figure assigned instead of silently
  /// rolling the assignment back. The order is the aggregate's: a beat belongs
  /// to an assigned character, so the look can only be added afterwards.
  Future<void> _assignFigureAndLook(
    BuildContext context,
    WidgetRef ref,
    List<CharacterView> characters,
  ) async {
    final assigned = scene.assignedCharacters.toSet();
    final candidates = [
      for (final c in characters)
        if (!assigned.contains(c.id)) c,
    ];
    if (candidates.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AssignCharacterSheet(
        characters: [
          for (final c in candidates)
            (
              id: c.id,
              name: c.name,
              category: serializers
                  .serializeWith(CharacterCategory.serializer, c.category)
                  .toString(),
            ),
        ],
        assignedId: null,
      ),
    );
    if (picked == null || !context.mounted) return;
    final result = await ref
        .read(charactersControllerProvider(seasonId).notifier)
        .assignToScene(
          sceneId: scene.id,
          sceneVersion: scene.version,
          characterId: picked,
        );
    if (!context.mounted) return;
    final newVersion = result.match((_) => null, (version) => version);
    if (newVersion == null) {
      // Reconcile the version even on conflict: the next action must echo the
      // current projection version, not the rejected one (no re-dispatch).
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
      if (!context.mounted) return;
      result.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(characterErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
      return;
    }
    await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    if (!context.mounted) return;
    final name = candidates
        .where((c) => c.id == picked)
        .map((c) => c.name)
        .firstOrNull;
    // The assignment ACK advanced the scene version: the second command must
    // echo THAT version, never the one the row was rendered from (a projector
    // that has not caught up yet would answer 409 otherwise).
    final updatedScene = scene.rebuild(
      (b) => b
        ..version = newVersion
        ..assignedCharacters.add(picked),
    );
    // Straight into the look picker: the reviewer asked for "Figur UND Look",
    // so the second half must not need a second trip.
    await _assignLook(context, ref, picked, name, actingScene: updatedScene);
  }

  /// Picks a look of [characterId] and appends it as that figure's next beat.
  ///
  /// [actingScene] overrides the rendered row for the beat command's version
  /// echo (the combined assign flow casts first and must not send the
  /// pre-assignment version).
  Future<void> _assignLook(
    BuildContext context,
    WidgetRef ref,
    String characterId,
    String? characterName, {
    SceneView? actingScene,
  }) async {
    // The picker lists the character's own looks (a scene casts an outfit,
    // never a bare piece). The list is the API edge's read model — fetched
    // lazily here, cached per character.
    final outfitsResult = await ref.read(
      characterOutfitsProvider(characterId).future,
    );
    if (!context.mounted) return;
    final outfits = outfitsResult.match((err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sceneBeatErrorCopy(l10nOf(context), err))),
      );
      return null;
    }, (r) => r);
    // A failed read is NOT an empty wardrobe: reporting "no look yet" for a
    // transport failure would send the user to create a look that exists.
    if (outfits == null) return;
    if (outfits.isEmpty) {
      // No look to pick is stated, not silent: the looks live in the Cast view.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).sceneDetailNoLooksForFigure)),
      );
      return;
    }
    final targetScene = actingScene ?? scene;
    final picked = await showPickOutfitSheet(context, outfits);
    if (picked == null || !context.mounted) return;
    final pickedOutfit = outfits
        .where((o) => o.id == picked.outfitId)
        .firstOrNull;
    final result = await ref
        .read(scenesControllerProvider(episodeId).notifier)
        .addOutfitBeat(
          seasonId: seasonId,
          scene: targetScene,
          characterId: characterId,
          outfitId: picked.outfitId,
          note: picked.note,
          characterName: characterName,
          outfitName: pickedOutfit?.name,
        );
    if (result.isRight()) return; // optimistic overlay + reconcile own the UI.
    if (!context.mounted) return;
    // Reconcile the version even on conflict: the next action must echo the
    // current projection version, not the rejected one. The command itself is
    // never re-dispatched automatically.
    await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    if (!context.mounted) return;
    result.match(
      (err) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sceneBeatErrorCopy(l10nOf(context), err))),
      ),
      (_) {},
    );
  }

  Future<void> _confirmRemoveCharacter(
    BuildContext context,
    WidgetRef ref,
    String characterId,
    String? name,
  ) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sceneDetailRemoveCharacterTitle),
        content: Text(
          l10n.sceneDetailRemoveCharacterMessage(
            name ?? l10n.sceneDetailThisCharacter,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('scene-character-remove-confirm-$characterId'),
            onPressed: () async {
              final result = await ref
                  .read(charactersControllerProvider(seasonId).notifier)
                  .unassignFromScene(
                    sceneId: scene.id,
                    sceneVersion: scene.version,
                    characterId: characterId,
                  );
              // A failed command (non-2xx) leaves the projected id in place —
              // no local edit was made before the ack, so there is nothing to
              // roll back — and surfaces the error keyed on `code`.
              if (result.isRight()) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
              } else if (dialogContext.mounted) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
                if (!dialogContext.mounted) return;
                result.match(
                  (err) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      // The captured copy: the section may be gone after the
                      // refresh, and `l10nOf(context)` would throw then.
                      content: Text(characterErrorCopy(l10n, err)),
                    ),
                  ),
                  (_) {},
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveLook(
    BuildContext context,
    WidgetRef ref,
    SceneBeatGroup group,
    SceneOutfitBeatView beat,
  ) {
    final l10n = l10nOf(context);
    final label = sceneBeatOutfitLabel(
      outfitName: beat.outfitName,
      genericFallback: l10n.pieceTileLabelFallback,
    );
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sceneDetailRemoveOutfitTitle),
        content: Text(l10n.sceneDetailRemoveOutfitMessage(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key(
              'scene-piece-remove-confirm-${group.characterId}-${beat.order}',
            ),
            onPressed: () async {
              final controller = ref.read(
                scenesControllerProvider(episodeId).notifier,
              );
              // The only remaining beat IS the clear-all ("no look in this
              // scene"); otherwise a single-beat removal.
              final result = group.beats.length <= 1
                  ? await controller.clearOutfitBeats(
                      seasonId: seasonId,
                      scene: scene,
                      characterId: group.characterId,
                    )
                  : await controller.removeOutfitBeat(
                      seasonId: seasonId,
                      scene: scene,
                      characterId: group.characterId,
                      order: beat.order,
                    );
              if (result.isRight()) {
                // Optimistic overlay + reconciliation own the UI.
              } else if (dialogContext.mounted) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
                if (!dialogContext.mounted) return;
                result.match(
                  (err) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      // The captured copy: the section may be gone after the
                      // refresh, and `l10nOf(context)` would throw then.
                      content: Text(sceneBeatErrorCopy(l10n, err)),
                    ),
                  ),
                  (_) {},
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// The trailing affordance column of a cast row (issue #902): ONE width,
/// shared by the row's chevron and the label band's trailing spacer, so the
/// look column starts at the same x under its label at every screen width.
const double _castActionColumnWidth = AppSpacing.space24;

/// The interactive minimum height of a cast row (issue #902): the row is ONE
/// tap target, and the four inline icon buttons it replaces measured ~32 dp —
/// below the 48 dp minimum (AGENTS §5).
const double _castRowMinHeight = 48;

/// The `<order>` segment of the row/menu keys for the row that carries NO beat
/// (a figure without a look): it has no beat order to name.
const String _castNoLookOrder = 'none';

/// One row of the cast table, flattened out of a [SceneBeatGroup] (issue
/// #902): the figure's first look (`beatIndex == 0`), one of its change steps,
/// or its "no look yet" placeholder (`beatIndex == null`).
class _CastRowSpec {
  const _CastRowSpec({required this.group, this.beatIndex});

  final SceneBeatGroup group;

  /// The index into [SceneBeatGroup.beats]; `null` renders the placeholder row
  /// of a figure this scene casts without a look.
  final int? beatIndex;
}

/// The actions a cast row offers (issue #902): labelled items of the row's
/// context menu instead of four icon-only buttons squeezed into the cells.
enum _CastRowMenuAction { edit, addLook, removeLook, removeCharacter }

/// Column labels of the cast table (issue #902): the band names the two cells
/// AND carries the table's own surface treatment.
///
/// Contrast is a SCHEME property (`surfaceContainerHighest` vs
/// `onSurfaceVariant`), never a drawn stroke — the same band reads in light
/// and dark mode, where the M3 default card colour stops implying a surface.
class _CastTableHeader extends StatelessWidget {
  const _CastTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      key: const Key('scene-cast-header-band'),
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space12,
        vertical: AppSpacing.space8,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              l10n.sceneDetailCastColumnCharacter,
              key: const Key('scene-cast-column-character'),
              style: style,
            ),
          ),
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            flex: 6,
            child: Text(
              l10n.sceneDetailCastColumnLook,
              key: const Key('scene-cast-column-look'),
              style: style,
            ),
          ),
          // Same trailing width as a row's chevron column, so the labels sit
          // EXACTLY over their columns.
          const SizedBox(width: _castActionColumnWidth),
        ],
      ),
    );
  }
}

/// One table row of the cast section (issue #902): the figure cell, the look
/// cell, and ONE tap target that opens the row's labelled menu.
///
/// The look cell carries the beat identity (`scene-piece-beat-{character}-
/// {order}` — a read DTO, never aggregate reconstruction), the arrow of a
/// change step, the category icon and the wardrobe cue. The row renders banded
/// (`surface` / `surfaceContainerLow`) plus an `outlineVariant` hairline: the
/// hairline is a `DecoratedBox` border, NEVER a `Divider` widget, so issue
/// #834's no-divider rule keeps holding for section chrome while the table
/// gets its own.
class _CastRow extends StatelessWidget {
  const _CastRow({
    required this.characterId,
    required this.characterName,
    required this.lookLabel,
    required this.zebra,
    required this.addLookLabel,
    required this.onAddLook,
    this.isFirstRow = true,
    this.beatOrder,
    this.lookKey,
    this.lookIcon,
    this.lookNote,
    this.lookIsPlaceholder = false,
    this.changeArrow = false,
    this.onEdit,
    this.onRemoveCharacter,
    this.onRemoveLook,
  });

  final String characterId;

  /// The figure's name. Rendered in the figure cell of the figure's FIRST row
  /// only (a change step keeps the column empty, like a table); the row menu
  /// names the figure on every row.
  final String characterName;

  final String lookLabel;

  /// Whether this row is banded (`surfaceContainerLow`) instead of `surface`.
  final bool zebra;

  /// Menu label of the add-look action: „Look zuweisen" for a figure without a
  /// look, „+ Lookwechsel" for a figure that already has one.
  final String addLookLabel;

  /// Opens the look picker — a first look or one more change step.
  final VoidCallback onAddLook;

  /// Whether this row is the FIRST row of its figure. The figure cell (name
  /// and the figure's own actions) is written once per figure — the change
  /// steps below it keep the column empty, like a table.
  final bool isFirstRow;
  final int? beatOrder;

  /// Explicit key for the LOOK cell, for the rows that name no beat (the
  /// "no look yet" placeholder keeps its own stable key).
  final Key? lookKey;
  final IconData? lookIcon;
  final String? lookNote;
  final bool lookIsPlaceholder;
  final bool changeArrow;

  /// `null` renders the menu item DISABLED, never absent: the edit route needs
  /// a `SeasonView`, and "no season row resolved" is a state, not an
  /// unsupported feature.
  final VoidCallback? onEdit;
  final VoidCallback? onRemoveCharacter;
  final VoidCallback? onRemoveLook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final scheme = theme.colorScheme;
    final lookStyle = lookIsPlaceholder
        ? theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)
        : theme.textTheme.bodyMedium;
    return Semantics(
      // The whole row is one button-like tap target (issue #902): a context
      // menu without a cue is a hidden affordance, so the row also carries the
      // decorative chevron below.
      button: true,
      hint: l10n.sceneDetailCastMenuHint,
      child: Material(
        // Zebra banding (issue #902): a row reads as a unit in dark mode
        // WITHOUT a single drawn line; the hairline reinforces it.
        color: zebra ? scheme.surfaceContainerLow : scheme.surface,
        child: InkWell(
          key: Key(
            'scene-cast-row-$characterId-${beatOrder ?? _castNoLookOrder}',
          ),
          // Tap and long-press open the SAME menu — one implementation, two
          // triggers (long-press is the secondary habit, not a second menu).
          onTap: () => unawaited(_openMenu(context)),
          onLongPress: () => unawaited(_openMenu(context)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space12,
                vertical: AppSpacing.space8,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _castRowMinHeight),
                child: Row(
                  // The figure's row identity for the widget tests and the
                  // Gherkin steps (unchanged key, issue #669).
                  key: isFirstRow ? Key('scene-character-$characterId') : null,
                  // The look column of every row starts at the same x as the
                  // label band's: the figure's actions live in the MENU now,
                  // never beside the table.
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Column 1 — the figure, written once per figure.
                    Expanded(
                      flex: 4,
                      child: isFirstRow
                          ? Text(
                              characterName,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: AppSpacing.space8),
                    // Column 2 — the look.
                    Expanded(
                      flex: 6,
                      child: Row(
                        key:
                            lookKey ??
                            (beatOrder == null
                                ? null
                                : Key(
                                    'scene-piece-beat-$characterId-$beatOrder',
                                  )),
                        children: [
                          if (changeArrow)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '→',
                                key: Key(
                                  'scene-piece-arrow-$characterId-$beatOrder',
                                ),
                              ),
                            ),
                          if (lookIcon != null) ...[
                            Icon(lookIcon, size: 18),
                            const SizedBox(width: AppSpacing.space4),
                          ],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  lookLabel,
                                  style: lookStyle,
                                  // Wrapping, not ellipsis (issue #902): with
                                  // the action icons gone, a long look label
                                  // gets a second line on a 360 dp phone
                                  // instead of stubbing to a few characters.
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (lookNote case final note?
                                    when note.isNotEmpty)
                                  Text(note, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The affordance cue of the tap target — decorative, never
                    // an action (issue #902).
                    SizedBox(
                      width: _castActionColumnWidth,
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the row menu and dispatches the chosen action.
  ///
  /// The sheet closes BEFORE the action runs, so a confirm dialog or a picker
  /// never stacks on top of an animating sheet.
  Future<void> _openMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_CastRowMenuAction>(
      context: context,
      builder: (_) => _CastRowMenu(
        characterId: characterId,
        characterName: characterName,
        beatOrder: beatOrder,
        isFirstRow: isFirstRow,
        addLookLabel: addLookLabel,
        onEdit: onEdit,
        onRemoveCharacter: onRemoveCharacter,
        onRemoveLook: onRemoveLook,
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _CastRowMenuAction.edit:
        onEdit?.call();
      case _CastRowMenuAction.addLook:
        onAddLook();
      case _CastRowMenuAction.removeLook:
        onRemoveLook?.call();
      case _CastRowMenuAction.removeCharacter:
        onRemoveCharacter?.call();
    }
  }
}

/// The row's context menu (issue #902): the four actions as LABELLED items.
///
/// `showModalBottomSheet` with `ListTile`s is this screen's mobile-first
/// pattern (`showPickOutfitSheet`, `AssignCharacterSheet`), and it is a net
/// accessibility improvement over the inline icon row it replaces: every action
/// now carries a visible label (glossary rule, AGENTS §5), and nothing is
/// icon-only any more.
class _CastRowMenu extends StatelessWidget {
  const _CastRowMenu({
    required this.characterId,
    required this.characterName,
    required this.isFirstRow,
    required this.addLookLabel,
    this.beatOrder,
    this.onEdit,
    this.onRemoveCharacter,
    this.onRemoveLook,
  });

  final String characterId;
  final String characterName;
  final bool isFirstRow;
  final String addLookLabel;
  final int? beatOrder;

  /// `null` disables the edit item (`SeasonView` unresolved) — it stays
  /// visible.
  final VoidCallback? onEdit;
  final VoidCallback? onRemoveCharacter;
  final VoidCallback? onRemoveLook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final order = beatOrder ?? _castNoLookOrder;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          key: Key('scene-cast-menu-$characterId-$order'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16,
                AppSpacing.space12,
                AppSpacing.space16,
                AppSpacing.space4,
              ),
              child: Text(
                l10n.sceneDetailCastMenuTitle(characterName),
                style: theme.textTheme.titleSmall,
              ),
            ),
            // Bearbeiten: on the figure's first row, ALWAYS rendered — with no
            // resolvable `SeasonView` it is disabled, never absent.
            if (isFirstRow)
              ListTile(
                key: Key('scene-cast-menu-edit-$characterId'),
                enabled: onEdit != null,
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.sceneDetailEditCharacterTooltip),
                onTap: onEdit == null
                    ? null
                    : () => Navigator.of(context).pop(_CastRowMenuAction.edit),
              ),
            ListTile(
              key: Key('scene-cast-menu-add-look-$characterId'),
              leading: const Icon(Icons.add),
              title: Text(addLookLabel),
              onTap: () =>
                  Navigator.of(context).pop(_CastRowMenuAction.addLook),
            ),
            // Look entfernen: ONLY on a row that carries a beat — the row's
            // own beat is the target, and a figure without a look has nothing
            // to remove.
            if (onRemoveLook != null)
              ListTile(
                key: Key('scene-cast-menu-remove-look-$characterId-$order'),
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.sceneDetailRemoveOutfitTooltip),
                onTap: () =>
                    Navigator.of(context).pop(_CastRowMenuAction.removeLook),
              ),
            // Figur entfernen: ONLY on the figure's first row — one place to
            // unassign a figure, not one per change step.
            if (onRemoveCharacter != null)
              ListTile(
                key: Key('scene-cast-menu-remove-character-$characterId'),
                leading: const Icon(Icons.person_remove_outlined),
                title: Text(l10n.sceneDetailRemoveCharacterTooltip),
                onTap: () =>
                    Navigator.of(context)
                        .pop(_CastRowMenuAction.removeCharacter),
              ),
          ],
        ),
      ),
    );
  }
}

/// The episode's **real** shooting days this scene is not planned on yet:
/// not archived, and not already on the scene's own list.
///
/// One function feeds every affordance that schedules this scene (the section's
/// button, a row's "move" icon and the script-day chip), so none of them can
/// offer a day another one would filter out.
List<ShootingDayView> _realDayCandidates(
  List<ShootingDayView> rows,
  SceneView scene,
) {
  // Defensive dedup (issue #550): a duplicated id would inflate the header
  // count and render the day twice while the set-based filter saw no candidate.
  final scheduled = scene.shootingDayIds.toSet();
  return [
    for (final day in rows)
      if (!day.archived && !scheduled.contains(day.id)) day,
  ];
}

/// Shooting-days section — the FIRST operational section (issue #834
/// follow-up: a scene is planned before it is cast, and the dispo is built from
/// the days, not from the looks).
///
/// Lists the days from `SceneView.shootingDayIds` resolved against the
/// episode's day projection (read-DTO join only). Per row: the day board, the
/// "move to another day" action and unscheduling; at the bottom the schedule
/// action. A scene whose days are all ineligible states why instead of leaving
/// a silently disabled button.
class _SceneShootingDaysSection extends ConsumerWidget {
  const _SceneShootingDaysSection({
    required this.seasonId,
    required this.episode,
    required this.scene,
    required this.candidates,
  });

  final String seasonId;
  final EpisodeView episode;
  String get episodeId => episode.id;
  final SceneView scene;

  /// The days the scene can be scheduled on — resolved ONCE by the body so the
  /// script-day chip in the header offers exactly the same list.
  final List<ShootingDayView> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final days = ref.watch(shootingDaysViewProvider(episodeId));
    final byId = {for (final d in days.rows) d.id: d};
    final scheduled = scene.shootingDayIds.toSet().toList();

    // SectionCard (issue #834): no divider chrome, collapsed by default.
    return SectionCard(
      key: Key('scene-shooting-days-${scene.id}'),
      pageStorageKey: 'scene-section-shooting-days',
      header: Text(l10n.sceneDetailShootingDaysTitle('${scheduled.length}')),
      children: [
        if (scheduled.isEmpty)
          ListTile(
            key: const Key('scene-shooting-days-empty'),
            title: Text(l10n.sceneDetailNoShootingDays),
            // Report provenance (issue #549): the reports entry lives on the
            // day board, and the day board is reachable only from a scheduled
            // day — so a 0-day scene showed no reports affordance and no reason
            // to expect one. The hint NAMES what becomes available once a day is
            // planned. It invents no report and adds no season-level entry: the
            // report routes are day-scoped in the contract itself, so this stays
            // copy, not an affordance that leads nowhere
            // (`flutter-reports-screen`, Report-Provenance Empty State).
            subtitle: Text(l10n.sceneDetailNoShootingDaysReportHint),
          )
        else
          for (final id in scheduled)
            ListTile(
              key: Key('scene-shooting-day-$id'),
              // Provenance badge keyed like the day list #538 — the scheduled
              // read-DTO join renders the day's wire source.
              title: switch (byId[id] == null
                  ? AiProvenanceVariant.absent
                  : dayProvenance(byId[id]!.source_)) {
                AiProvenanceVariant.aiExtracted => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AiProvenanceBadge(semanticKey: 'shooting-day-ai-badge-$id'),
                    Flexible(
                      child: Text(
                        byId[id]?.label ?? l10n.sceneShootDayFallback,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                _ => Text(byId[id]?.label ?? l10n.sceneShootDayFallback),
              },
              subtitle: byId[id]?.date != null
                  ? Text(l10n.shootingDayDate('${byId[id]!.date}'))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day-board entry (`flutter-shoot-day-execution` 2.1):
                  // opens the Soll/Ist execution board with the acted-on day +
                  // scene DTOs (never a second projection lookup). Gherkin
                  // contract key (`open-day-board-<day>`) for the shoot-day
                  // execution critical scenarios.
                  IconButton(
                    key: Key('open-day-board-$id'),
                    icon: const Icon(Icons.view_agenda_outlined),
                    tooltip: l10n.sceneDetailOpenDayBoard,
                    onPressed: byId[id] == null
                        ? null
                        : () => _openBoard(context, byId[id]!),
                  ),
                  // "Move to another day" (issue #834 follow-up): the reported
                  // gap was having to unschedule and re-schedule by hand, which
                  // left the scene without a day in between (and the Soll/Ist
                  // report without a row). Disabled when no other day exists.
                  IconButton(
                    key: Key('scene-shooting-day-move-$id'),
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: l10n.sceneDetailMoveToOtherDay,
                    onPressed: candidates.isEmpty
                        ? null
                        : () => _pickDayAndSchedule(
                            context,
                            ref,
                            episodeId: episodeId,
                            scene: scene,
                            candidates: candidates,
                            replaceDayId: id,
                          ),
                  ),
                  IconButton(
                    key: Key('scene-shooting-day-unschedule-$id'),
                    icon: const Icon(Icons.event_busy),
                    tooltip: l10n.shootingDayUnscheduleButton,
                    onPressed: () => _unschedule(context, ref, id),
                  ),
                ],
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: Key('scene-shooting-day-schedule-${scene.id}'),
            onPressed: candidates.isEmpty
                ? null
                : () => _pickDayAndSchedule(
                    context,
                    ref,
                    episodeId: episodeId,
                    scene: scene,
                    candidates: candidates,
                  ),
            icon: const Icon(Icons.event_available_outlined),
            label: Text(l10n.sceneDetailScheduleOnDay),
          ),
        ),
        // Issue #669: a fresh script import creates scenes but NO shooting days,
        // so the picker candidates are empty for every imported episode — the
        // disabled button was silent and non-actionable (same UX-defect class as
        // #665). When there is nothing to pick, keep the button disabled BUT make
        // the state explain itself. Two DISTINCT empty states (CodeRabbit
        // review): the episode has NO days at all → the hint names the missing
        // prerequisite and offers the quick-create path directly; the episode HAS
        // days but none eligible (already scheduled on this scene or archived) →
        // a factual note without the create affordance (creating another day
        // would not change anything).
        if (candidates.isEmpty)
          Padding(
            key: Key('scene-shooting-day-no-candidates-${scene.id}'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        days.rows.isEmpty
                            ? l10n.sceneDetailNoDayCandidatesHint
                            : l10n.sceneDetailAllDaysScheduled,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (days.rows.isEmpty) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    key: Key('scene-shooting-day-create-${scene.id}'),
                    onPressed: () =>
                        unawaited(showCreateShootingDaySheet(context, episode)),
                    child: Text(l10n.sceneDetailCreateFirstDay),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _openBoard(BuildContext context, ShootingDayView day) {
    // Fire-and-forget navigation (route push has no consumable result).
    // Issue #548: the day board rides on the SAME scene-level location chain
    // (from the route arguments) — display context only, the screen keeps
    // resolving its scene from the acted-on ids.
    final location = locationFromArguments(
      ModalRoute.of(context)?.settings.arguments,
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            arguments: location is SceneLocation ? location : null,
          ),
          builder: (_) =>
              SceneShootsScreen(day: day, scene: scene, seasonId: seasonId),
        ),
      ),
    );
  }

  Future<void> _unschedule(
    BuildContext context,
    WidgetRef ref,
    String shootingDayId,
  ) async {
    final result = await ref
        .read(shootingDaysControllerProvider(episodeId).notifier)
        .unscheduleScene(
          sceneId: scene.id,
          sceneVersion: scene.version,
          shootingDayId: shootingDayId,
        );
    if (result.isRight()) {
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    } else if (context.mounted) {
      // 409 (scene changed elsewhere): the local edit rolls back (nothing was
      // applied before the ack), the projection refreshes so the next action
      // echoes the current version, and conflict copy renders keyed on `code`;
      // no automatic version bump re-dispatch.
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
      if (!context.mounted) return;
      result.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(shootingDayErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
    }
  }
}

/// Opens the day picker over [candidates] and schedules the scene on the picked
/// day (issue #834 follow-up).
///
/// [replaceDayId] names a day the scene sits on RIGHT NOW — the "move" action.
/// It is unscheduled only AFTER the new schedule was acknowledged, so a refused
/// command leaves the scene where it was instead of on no day at all. The two
/// commands are chained on the ACK versions the API returns, never on the
/// stale one the row was rendered from.
Future<void> _pickDayAndSchedule(
  BuildContext context,
  WidgetRef ref, {
  required String episodeId,
  required SceneView scene,
  required List<ShootingDayView> candidates,
  String? replaceDayId,
}) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10nOf(context).sceneDetailScheduleTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (context, i) {
                final d = candidates[i];
                return ListTile(
                  key: Key('schedule-day-${d.id}'),
                  // Day picker provenance badge (issue #538): the picker
                  // carries the same AI framing as the day list.
                  title: switch (dayProvenance(d.source_)) {
                    AiProvenanceVariant.aiExtracted => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AiProvenanceBadge(
                          semanticKey: 'shooting-day-ai-badge-${d.id}',
                        ),
                        Flexible(
                          child: Text(
                            d.label ?? l10nOf(context).shootingDayUntitled,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    _ => Text(d.label ?? l10nOf(context).shootingDayUntitled),
                  },
                  subtitle: d.date != null
                      ? Text(l10nOf(context).shootingDayDate('${d.date}'))
                      : null,
                  onTap: () => Navigator.of(context).pop(d.id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final controller = ref.read(
    shootingDaysControllerProvider(episodeId).notifier,
  );
  final scheduled = await controller.scheduleScene(
    sceneId: scene.id,
    sceneVersion: scene.version,
    shootingDayId: picked,
  );
  final newVersion = scheduled.match((_) => null, (version) => version);
  if (newVersion == null) {
    // Reconcile the version even on conflict (never re-dispatch).
    await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    if (!context.mounted) return;
    scheduled.match(
      (err) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(shootingDayErrorCopy(l10nOf(context), err))),
      ),
      (_) {},
    );
    return;
  }
  if (replaceDayId != null && replaceDayId != picked) {
    final moved = await controller.unscheduleScene(
      sceneId: scene.id,
      sceneVersion: newVersion,
      shootingDayId: replaceDayId,
    );
    // The new day is acknowledged, so the scene IS planned either way. A failed
    // removal leaves it on both days — visible in the list (two rows, each
    // removable) instead of silently dropped — and says so with its code.
    if (moved.isLeft() && context.mounted) {
      moved.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(shootingDayErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
    }
  }
  await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
}

class _SceneDetailErrorView extends StatelessWidget {
  const _SceneDetailErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).sceneDetailFetchError(code),
          key: const Key('scene-detail-error'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('scene-detail-retry'),
          onPressed: onRetry,
          child: Text(l10nOf(context).commonRetry),
        ),
      ],
    ),
  );
}

class _SceneDetailGoneView extends StatelessWidget {
  const _SceneDetailGoneView({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).sceneDetailGone,
          key: const Key('scene-detail-gone'),
        ),
        if (onBack != null)
          FilledButton.tonal(
            onPressed: onBack,
            child: Text(l10nOf(context).commonBack),
          ),
      ],
    ),
  );
}
