// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_de.dart';
import '../../design/material_icons.dart';
import '../../auth/active_block.dart';
import '../../auth/active_episode.dart';
import '../../auth/auth_providers.dart';
import 'quick_create_sheet.dart';
import 'active_episode_chip.dart';
import 'active_scope_chip.dart';
import 'cast_tab_screen.dart';
import 'location_strip.dart';
import 'planning_location_route_observer.dart';
import 'schedule_tab_screen.dart';
import 'script_tab_screen.dart';
import 'season_scope_chip.dart';
import 'shell_controller.dart';
import 'window_size_class.dart';

/// Semantic traversal labels: Material's NavigationBar/Rail/Drawer add the
/// framework `MaterialLocalizations.tabLabel` semantics to every destination
/// automatically, so the "Cast, Tab 1 von 3" traversal pattern is announced
/// without hand-rolled Semantics wrappers. This helper builds the
/// concatenated form for the NavigationBar tooltip (carried into its
/// semantics) and documents the contract for tests.
///
/// The destination TOTAL is a placeholder, not a baked-in literal (issue
/// #610 reduced the shell from four destinations to three): it is derived
/// from the destination-list length, so a future destination change updates
/// the announcement by construction. The placeholder is deliberately named
/// `total`, not `count` — `count` is reserved by the ICU message parser and
/// would be read as a plural selector.
String tabSemanticLabel(
  AppLocalizations l10n,
  int index,
  String label, {
  int total = kDestinationCount,
}) => l10n.seasonTabSemantic(label, index + 1, total);

/// How many destinations the shell renders (issue #610: three).
const int kDestinationCount = 3;

/// Bottom clearance the compact morphology reserves for the shell's
/// extended plus FAB (CodeRabbit review #623): the FAB's 56 height + its
/// 16 docked margin above the bar + 8 breathing room, so the tab lists'
/// last row never renders beneath the persistent FAB.
const double kShellFabBottomClearance = 80;

/// The adaptive three-destination navigation shell (issue #610, spec
/// `flutter-navigation-shell`, design D1–D3).
///
/// Resolves the window size class from the window width (MediaQuery, no
/// extra package) and renders the navigation suite in the matching
/// morphology: bottom [NavigationBar] (compact), side [NavigationRail]
/// (medium) or permanent [NavigationDrawer] (expanded). Every destination
/// renders a VISIBLE label (glossary rule — icon-only navigation is
/// forbidden).
///
/// Destinations are TASK-oriented (issue #610): Cast (roster + costumes +
/// category vocabulary), Script (the season's chronological scenes) and
/// Schedule/Dispo (the season's shooting days). The former Season, Planen,
/// Kleidung and Mehr tabs are dissolved: seasons and the production spine
/// are reached from the season scope chip's picker, and the profile entries
/// from each view's app-bar profile action (issue #613 owns the final
/// top-bar design).
///
/// Tab content: an [IndexedStack] keeps all three nested navigators alive,
/// so switching destinations preserves each one's position (design D2).
/// System back pops within the active destination's navigator first; at a
/// destination root it never hops destinations — at the initial (Cast)
/// destination root it issues the app-exit intent per platform convention
/// (D3).
///
/// The shell renders only for a resolved authenticated session (it sits
/// below `AuthGate`; the gate contract is unchanged).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Root screen per destination (issue #610): Cast = roster/costumes,
  /// Script = chronological scene overview, Schedule/Dispo = day board.
  static const List<Widget> _tabRoots = [
    CastTabScreen(),
    ScriptTabScreen(),
    ScheduleTabScreen(),
  ];

  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

class AppShellState extends ConsumerState<AppShell> {
  /// Nested-navigator keys, one per tab — INSTANCE state (CodeRabbit
  /// review fix: `static final` keys would throw the duplicate-GlobalKey
  /// assertion if two shells were ever mounted side by side, e.g. a
  /// preview or a lingering test tree).
  final List<GlobalKey<NavigatorState>> tabNavigatorKeys = [
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-0-cast'),
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-1-script'),
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-2-schedule'),
  ];

  /// One location observer per destination navigator (issue #548): the
  /// context bar resolves the ACTIVE destination's location from its
  /// topmost route's `RouteSettings.arguments`; pop/switch updates come
  /// free.
  final List<LocationRouteObserver> tabLocationObservers = [
    for (var i = 0; i < 3; i++) LocationRouteObserver(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shellControllerProvider);
    final controller = ref.read(shellControllerProvider.notifier);
    final widthDp = MediaQuery.sizeOf(context).width;
    final sizeClass = resolveWindowSizeClass(widthDp);
    // Standalone shell previews/tests use the canonical German suite;
    // the production App supplies resolved delegates for the device locale.
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizationsDe();

    final content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Inner navigator pops first (task 3.3): within-tab back.
        final navigator = tabNavigatorKeys[state.selectedIndex].currentState;
        final popped = await navigator?.maybePop() ?? false;
        if (popped) return;
        // At the destination root: NO destination hopping (D3). The
        // initial (Cast) destination issues the app-exit intent per
        // platform convention; any other root stays put (the OS back
        // intent is consumed — back is never a destination-history step).
        if (state.selectedIndex == kCastTabIndex) {
          await SystemNavigator.pop();
        }
      },
      child: IndexedStack(
        key: const Key('shell-tab-stack'),
        index: state.selectedIndex,
        children: [
          for (var i = 0; i < AppShell._tabRoots.length; i++)
            Navigator(
              key: tabNavigatorKeys[i],
              restorationScopeId: 'shell-tab-$i',
              observers: [tabLocationObservers[i]],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => AppShell._tabRoots[i],
              ),
            ),
        ],
      ),
    );

    // Issue #548: the hierarchy context surface lives in the SHELL (not in
    // each screen's app bar) — one surface, all three morphologies, the
    // ~60 per-feature goldens pump their screens directly and stay
    // untouched. [bottomClearance] reserves space under the shell's
    // persistent plus FAB so the LAST list row never renders beneath it
    // (CodeRabbit review #623 — compact-only: the medium/expanded FAB
    // floats over the content area's bottom-right where no tab list ends).
    Widget contentWithLocation({double bottomClearance = 0}) => Column(
      children: [
        ShellContextBar(
          navigatorKey: tabNavigatorKeys[state.selectedIndex],
          observer: tabLocationObservers[state.selectedIndex],
        ),
        Expanded(child: content),
        if (bottomClearance > 0) SizedBox(height: bottomClearance),
      ],
    );

    // AUTHZ-GATE (issue #612, client-side mirror, Decision D6): the
    // quick-create sheet is `Requirement::Authenticated`-gated UI — the
    // backend create/import handlers are auth-gated server-side, so the
    // shell plus action renders only for a RESOLVED authenticated session
    // (a pending/erroring session shows nothing, same rule as the seasons
    // FAB). The pushed flows gate further inside their controllers BEFORE
    // any network call; the sheet itself issues no request, so the
    // `grep AUTHZ-GATE` contract travels with this comment.
    final session = ref.watch(authSessionControllerProvider);
    final canCreate = session is AsyncData && session.value != null;
    // Explicit accessible BUTTON role (CodeRabbit review #623):
    // FloatingActionButton.extended builds on RawMaterialButton/InkWell,
    // which expose the tap action but NOT the semantics button flag —
    // screen readers announce the affordance without the "Schaltfläche"
    // role. One wrapping Semantics fixes that at the affordance's root.
    final plusFab = canCreate
        ? Semantics(
            button: true,
            child: FloatingActionButton.extended(
              key: const Key('shell-plus-fab'),
              onPressed: () => unawaited(
                showQuickCreateSheet(
                  context,
                  actions: shellQuickCreateActions(
                    l10n,
                    episode: ref.read(activeEpisodeProvider),
                  ),
                ),
              ),
              // One Spotify-style plus action across ALL three morphologies
              // (issue #612, settled decision): the FAB is an ACTION, not a
              // destination — the destination contract (kDestinationCount,
              // `shell-destination-*` keys) stays untouched.
              icon: const Icon(Icons.add),
              label: Text(l10n.shellPlusFabLabel),
            ),
          )
        : null;

    // The shell carries its own Scaffold so the FAB is a shell-level
    // affordance: in the compact morphology it sits on `bottomNavigationBar`
    // and DOCKS above the bar (Material's FAB slot); in medium/expanded it
    // floats at the content's bottom-right (no tab root carries its own FAB
    // since #610, so there is no overlap).
    return switch (sizeClass) {
      WindowSizeClass.compact => Scaffold(
        body: contentWithLocation(
          // CodeRabbit review #623: the extended FAB sits docked above the
          // bar (its 56 height + the 16 docked margin); without clearance
          // the final list row renders BENEATH it. Gated: without a FAB
          // there is nothing to avoid (auth-gate symmetry).
          bottomClearance: canCreate ? kShellFabBottomClearance : 0,
        ),
        bottomNavigationBar: ShellDestinations.navigationBar(
          selectedIndex: state.selectedIndex,
          onSelected: controller.selectTab,
          l10n: l10n,
        ),
        floatingActionButton: plusFab,
      ),
      WindowSizeClass.medium => Scaffold(
        body: Row(
          children: [
            ShellDestinations.navigationRail(
              selectedIndex: state.selectedIndex,
              onSelected: controller.selectTab,
              l10n: l10n,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: contentWithLocation()),
          ],
        ),
        floatingActionButton: plusFab,
      ),
      WindowSizeClass.expanded => Scaffold(
        body: Row(
          children: [
            ShellDestinations.navigationDrawer(
              selectedIndex: state.selectedIndex,
              onSelected: controller.selectTab,
              l10n: l10n,
            ),
            Expanded(child: contentWithLocation()),
          ],
        ),
        floatingActionButton: plusFab,
      ),
    };
  }
}

/// The shell's context bar (issue #548 + #610): the [LocationStrip] for the
/// active destination's topmost route location plus the SEASON and BLOCK
/// scope chips — WHERE YOU NAVIGATED (per-route) and WHAT FILTERS YOUR
/// REQUESTS (sticky) as separate widgets with separate lifetimes. Hidden
/// entirely when neither has anything to say (destination roots without a
/// pushed location and no scope).
class ShellContextBar extends ConsumerWidget {
  const ShellContextBar({
    super.key,
    required this.navigatorKey,
    required this.observer,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final LocationRouteObserver observer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: observer,
      builder: (context, _) {
        final navigator = navigatorKey.currentState;
        final location = navigator == null ? null : locationOf(navigator);
        final scope = ref.watch(activeBlockProvider);
        final episode = ref.watch(activeEpisodeProvider);
        final season = ref.watch(shellControllerProvider).activeSeason;
        if (location == null &&
            scope == null &&
            episode == null &&
            season == null) {
          return const SizedBox.shrink();
        }

        final maxSegments =
            resolveWindowSizeClass(MediaQuery.sizeOf(context).width) ==
                WindowSizeClass.compact
            ? 3
            : 4;
        // ActionChip needs a Material ancestor; the bar sits OUTSIDE the
        // tab navigators' Scaffolds in all three morphologies, so it
        // provides its own transparent one.
        return Material(
          type: MaterialType.transparency,
          child: Container(
            key: const Key('shell-context-bar'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                if (location != null) ...[
                  Expanded(
                    child: LocationStrip(
                      location: location,
                      maxSegments: maxSegments,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                SeasonScopeChip(
                  onOpenPicker: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SeasonScopePickerScreen(),
                      ),
                    ),
                  ),
                ),
                ActiveScopeChip(
                  location: location,
                  onOpenPicker: (seasonId) => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ScopeChipPickerScreen(seasonId: seasonId),
                      ),
                    ),
                  ),
                ),
                ActiveEpisodeChip(
                  location: location,
                  onOpenPicker: (seasonId, blockId) => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EpisodeScopePickerScreen(
                          seasonId: seasonId,
                          blockId: blockId,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The shell navigation suite: the three M3 morphologies built from ONE
/// destination list (glossary icons + visible labels + "Tab N of 3"
/// semantics). Public (non-private) so the semantics/touch-target widget
/// tests pump the EXACT suite widgets the shell renders — the framework's
/// test semantics pipeline prunes sibling-subtree annotations when an
/// IndexedStack hosts nested Navigators, so the traversal contract is
/// asserted against the suite standalone (same widget code).
class ShellDestinations {
  ShellDestinations._();

  static List<_DestinationSpec> _specs(AppLocalizations l10n) => [
    for (var i = 0; i < kDestinationCount; i++)
      _DestinationSpec.destination(i, l10n),
  ];

  /// Compact morphology: bottom [NavigationBar].
  static Widget navigationBar({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    AppLocalizations? l10n,
  }) => NavigationBar(
    key: const Key('shell-navigation-bar'),
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelected,
    destinations: [
      for (final d in _specs(l10n ?? AppLocalizationsDe()))
        NavigationDestination(
          key: Key(d.keySuffix),
          icon: Icon(d.outlineIcon),
          selectedIcon: Icon(d.filledIcon),
          label: d.label,
          // Carries the "Tab N of 4" semantics (tooltip).
          tooltip: d.semanticLabel,
        ),
    ],
  );

  /// Medium morphology: side [NavigationRail] (labels always visible).
  static Widget navigationRail({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    AppLocalizations? l10n,
  }) => NavigationRail(
    key: const Key('shell-navigation-rail'),
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelected,
    labelType: NavigationRailLabelType.all,
    destinations: [
      for (final d in _specs(l10n ?? AppLocalizationsDe()))
        NavigationRailDestination(
          icon: Icon(d.outlineIcon),
          selectedIcon: Icon(d.filledIcon),
          // Explicit "<label>, Tab N of 4" traversal semantics on the
          // label node (excludeSemantics: the bare Text label would
          // otherwise be announced twice). The shared destination key
          // rides on this wrapper (NavigationRailDestination has no key
          // parameter) — one key per destination across ALL morphologies
          // (CodeRabbit review fix).
          label: Semantics(
            key: Key(d.keySuffix),
            label: d.semanticLabel,
            excludeSemantics: true,
            container: true,
            explicitChildNodes: true,
            child: Text(d.label),
          ),
        ),
    ],
  );

  /// Expanded morphology: permanent [NavigationDrawer].
  static Widget navigationDrawer({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    AppLocalizations? l10n,
  }) => NavigationDrawer(
    key: const Key('shell-navigation-drawer'),
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelected,
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text((l10n ?? AppLocalizationsDe()).appTitleBreakdown),
      ),
      for (final d in _specs(l10n ?? AppLocalizationsDe()))
        NavigationDrawerDestination(
          icon: Icon(d.outlineIcon),
          selectedIcon: Icon(d.filledIcon),
          // See the rail destination: explicit traversal semantics + the
          // shared destination key on the label wrapper.
          label: Semantics(
            key: Key(d.keySuffix),
            label: d.semanticLabel,
            excludeSemantics: true,
            container: true,
            explicitChildNodes: true,
            child: Text(d.label),
          ),
        ),
    ],
  );
}

/// One shell destination's static metadata: glossary icon, visible label
/// and the "Tab N of 3" semantics label.
class _DestinationSpec {
  _DestinationSpec.destination(int index, AppLocalizations l10n)
    : keySuffix = _keySuffixes[index],
      label = _label(index, l10n),
      outlineIcon = _outlineIcons[index],
      filledIcon = _filledIcons[index],
      semanticLabel = tabSemanticLabel(l10n, index, _label(index, l10n));

  /// Keys (`shell-destination-<n>`) for semantic/touch-target tests.
  final String keySuffix;
  final String label;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String semanticLabel;

  static String _label(int index, AppLocalizations l10n) => switch (index) {
    0 => l10n.navCast,
    1 => l10n.navScript,
    _ => l10n.navSchedule,
  };
  static const _keySuffixes = [
    'shell-destination-0',
    'shell-destination-1',
    'shell-destination-2',
  ];
  // Glossary (`docs/design/glossary.md`, issue #610): face/Cast,
  // menu_book/Script, calendar_month/Schedule/Dispo.
  static const _outlineIcons = [
    BreakdownMaterialIcons.shellCastOutline,
    BreakdownMaterialIcons.shellScriptOutline,
    BreakdownMaterialIcons.shellScheduleOutline,
  ];
  static const _filledIcons = [
    BreakdownMaterialIcons.shellCastFilled,
    BreakdownMaterialIcons.shellScriptFilled,
    BreakdownMaterialIcons.shellScheduleFilled,
  ];
}
