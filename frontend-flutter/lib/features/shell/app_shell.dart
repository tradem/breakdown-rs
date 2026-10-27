// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_de.dart';
import '../../design/material_icons.dart';
import '../../auth/active_episode.dart';
import '../../auth/active_episode_store.dart';
import '../../auth/auth_providers.dart';
import 'quick_create_sheet.dart';
import 'account_drawer.dart';
import 'cast_tab_screen.dart';
import 'planning_location_route_observer.dart';
import 'offline_pill.dart';
import 'schedule_tab_screen.dart';
import 'script_tab_screen.dart';
import 'shell_controller.dart';
import 'shell_top_bar.dart';
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
/// Destinations are TASK-oriented (issue #610): Cast (roster + pieces +
/// category vocabulary), Script (the season's chronological scenes) and
/// Schedule/Dispo (the season's shooting days). The former Season, Planen,
/// Kleidung and Mehr tabs are dissolved: seasons and the production spine
/// are reached from the season scope pill's picker, and the profile entries
/// from the shell's top-bar profile action (issue #638 owns the top bar —
/// row 1: profile + scope pills, row 2: view title + breadcrumb + search).
///
/// Tab content: an [IndexedStack] keeps all three nested navigators
/// alive (fast re-entry, per-tab state such as scroll offsets survives
/// a switch). Since issue #707 the position MEMORY is gone (former
/// design D2, consciously overridden): every destination selection —
/// switching OR re-tapping the active destination — pops the TARGET
/// tab's nested navigator back to its root route, so the destination's
/// start screen is always what you land on (Material convention "re-tap
/// = back to start"). System back pops within the active destination's
/// navigator first; at a destination root it never hops destinations —
/// at the initial (Cast) destination root it issues the app-exit intent
/// per platform convention (D3).
///
/// The shell renders only for a resolved authenticated session (it sits
/// below `AuthGate`; the gate contract is unchanged).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Root screen per destination (issue #610): Cast = roster/pieces,
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

    // Issue #624 (CodeRabbit review): restore the persisted active-episode
    // scope for the active season on cold start. Watched unconditionally so
    // the shell rebuilds once the persisted map resolves.
    final episodePersisted = ref.watch(activeEpisodePersistedProvider);
    _restoreEpisodeScope(state.activeSeason?.id, episodePersisted);

    // Issue #707: the destination-selection seam for ALL three
    // morphologies (bar / rail / drawer go through this one handler).
    // The controller distinguishes switch vs re-tap vs rejected; both
    // valid kinds reset the TARGET tab's nested navigator to its root,
    // so a switch always shows the destination's start screen and a
    // re-tap follows the Material "back to start" convention. At a tab
    // root `popUntil` is a no-op, not an error. Settings/About/Jobs
    // pushed by the AccountDrawer onto a tab's navigator (#653 seam)
    // are therefore never "stuck" across tab switches.
    void onDestinationSelected(int index) {
      final selection = controller.selectTab(index);
      if (selection == ShellTabSelection.rejected) return;
      tabNavigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    }

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
        // Issue #638: the shell owns the sticky two-row top bar (row 1:
        // profile + scope pills, row 2: view title + breadcrumb + search)
        // and insets it below the system status bar. The title comes from
        // the destination spec so it can never drift from the destinations.
        ShellTopBar(
          title: ShellDestinations.viewTitle(state.selectedIndex, l10n),
          navigatorKey: tabNavigatorKeys[state.selectedIndex],
          observer: tabLocationObservers[state.selectedIndex],
        ),
        // Issue #654: the offline pill lives in the shell content column —
        // one surface visible on every destination and every pushed route
        // inside the tabs; it animates in/out with connectivity changes.
        const OfflinePill(),
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
              onPressed: () {
                final activeSeasonId = ref
                    .read(shellControllerProvider)
                    .activeSeason
                    ?.id;
                final scope = ref.read(activeEpisodeProvider);
                unawaited(
                  showQuickCreateSheet(
                    context,
                    actions: shellQuickCreateActions(
                      l10n,
                      // Never offer scene/day for a scope whose season differs
                      // from the active season (foreign-scope guard).
                      episode: scope != null && scope.seasonId == activeSeasonId
                          ? scope
                          : null,
                    ),
                  ),
                );
              },
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
    // Issue #653: the shell hosts the user ACCOUNT DRAWER (M3
    // NavigationDrawer, Spotify-style side overlay — never a bottom
    // sheet) on every morphology's Scaffold. It sits on the ROOT
    // navigator (its scrim covers top bar + destination bar), and its
    // About/Settings pushes target the ACTIVE destination's nested
    // navigator, which is passed here so the drawer can never drift from
    // the shell's destination state.
    Widget accountDrawer() =>
        AccountDrawer(navigatorKey: tabNavigatorKeys[state.selectedIndex]);

    return switch (sizeClass) {
      WindowSizeClass.compact => Scaffold(
        drawer: accountDrawer(),
        body: contentWithLocation(
          // CodeRabbit review #623: the extended FAB sits docked above the
          // bar (its 56 height + the 16 docked margin); without clearance
          // the final list row renders BENEATH it. Gated: without a FAB
          // there is nothing to avoid (auth-gate symmetry).
          bottomClearance: canCreate ? kShellFabBottomClearance : 0,
        ),
        bottomNavigationBar: ShellDestinations.navigationBar(
          selectedIndex: state.selectedIndex,
          onSelected: onDestinationSelected,
          l10n: l10n,
        ),
        floatingActionButton: plusFab,
      ),
      WindowSizeClass.medium => Scaffold(
        drawer: accountDrawer(),
        body: Row(
          children: [
            ShellDestinations.navigationRail(
              selectedIndex: state.selectedIndex,
              onSelected: onDestinationSelected,
              l10n: l10n,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: contentWithLocation()),
          ],
        ),
        floatingActionButton: plusFab,
      ),
      WindowSizeClass.expanded => Scaffold(
        drawer: accountDrawer(),
        body: Row(
          children: [
            ShellDestinations.navigationDrawer(
              selectedIndex: state.selectedIndex,
              onSelected: onDestinationSelected,
              l10n: l10n,
            ),
            Expanded(child: contentWithLocation()),
          ],
        ),
        floatingActionButton: plusFab,
      ),
    };
  }

  /// Cold-start restore of the persisted active-episode scope (issue #624,
  /// CodeRabbit review): the in-memory scope starts `null`, so seed it from
  /// the persisted per-season document for the active season. Deferred to a
  /// microtask (never mutate a provider during build); double-guarded so the
  /// resulting rebuilds converge.
  ///
  /// Season switch: the guard compares the current scope's season, not mere
  /// presence — when the active season changes, the new season's remembered
  /// scope replaces a scope from the previous season (or the stale scope is
  /// dropped when the new season has none).
  void _restoreEpisodeScope(
    String? seasonId,
    AsyncValue<Map<String, PersistedEpisodeScope>> persisted,
  ) {
    if (seasonId == null) return;
    final current = ref.read(activeEpisodeProvider);
    // Already showing the right season's scope.
    if (current != null && current.seasonId == seasonId) return;
    final saved = switch (persisted) {
      AsyncData(:final value) => value[seasonId],
      _ => null,
    };
    if (saved == null) {
      // The new season has no remembered episode: drop the previous
      // season's in-memory scope so its foreign chip does not linger. The
      // persisted documents are untouched (each season keeps its own).
      if (current == null) return;
      unawaited(
        Future.microtask(() {
          if (!mounted) return;
          final live = ref.read(activeEpisodeProvider);
          if (live == null || live.seasonId == seasonId) return;
          ref.read(activeEpisodeProvider.notifier).discard();
        }),
      );
      return;
    }
    unawaited(
      Future.microtask(() {
        if (!mounted) return;
        if (ref.read(activeEpisodeProvider)?.seasonId == seasonId) return;
        ref
            .read(activeEpisodeProvider.notifier)
            .set(
              seasonId: seasonId,
              blockId: saved.blockId,
              episodeId: saved.episodeId,
              episodeNumber: saved.episodeNumber,
              episodeName: saved.episodeName,
            );
      }),
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

  /// The visible view-bar title for a destination (issue #638): the same
  /// glossary label the destination renders, so the shell's sticky top bar
  /// can never drift from the destination list.
  ///
  /// Issue #709: the Script destination is the one exception — its bottom
  /// bar label stays the short "Script" while the view bar carries the
  /// descriptive "Szenen aus dem Skript" (a long nav label would stretch
  /// the bottom bar). Every other destination keeps label == view title.
  static String viewTitle(int index, AppLocalizations l10n) =>
      index == 1 ? l10n.viewTitleScript : _DestinationSpec._label(index, l10n);

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
