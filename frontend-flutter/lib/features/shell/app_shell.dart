// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_de.dart';
import '../../design/material_icons.dart';
import 'more_tab_screen.dart';
import 'planning_tab_screen.dart';
import '../seasons/seasons_screen.dart';
import 'costuming_tab_screen.dart';
import 'shell_controller.dart';
import 'window_size_class.dart';

/// Semantic traversal labels: Material's NavigationBar/Rail/Drawer add the
/// framework `MaterialLocalizations.tabLabel` ("Tab N of 4") semantics to
/// every destination automatically, so the "Season, Tab 1 of 4" traversal
/// pattern is announced without hand-rolled Semantics wrappers. This helper
/// builds the concatenated form for the NavigationBar tooltip (carried into
/// its semantics) and documents the contract for tests.
String tabSemanticLabel(AppLocalizations l10n, int index, String label) =>
    l10n.seasonTabSemantic(label, index + 1);

/// The adaptive four-tab navigation shell (spec `flutter-navigation-shell`,
/// design D1–D3).
///
/// Resolves the window size class from the window width (MediaQuery, no
/// extra package) and renders the navigation suite in the matching
/// morphology: bottom [NavigationBar] (compact), side [NavigationRail]
/// (medium) or permanent [NavigationDrawer] (expanded). Every destination
/// renders a VISIBLE label (glossary rule — icon-only navigation is
/// forbidden).
///
/// Tab content: an [IndexedStack] keeps all four nested navigators alive,
/// so switching tabs preserves each tab's position (design D2). System
/// back pops within the active tab's navigator first; at a tab root it
/// never hops tabs — at the initial (Season) tab root it issues the
/// app-exit intent per platform convention (D3).
///
/// The shell renders only for a resolved authenticated session (it sits
/// below `AuthGate`; the gate contract is unchanged).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Root screen per tab (design D2/task 3.2): Season = the seasons
  /// overview, Planen = hierarchy entry (+ AI import), Garderobe = costume
  /// domains scope, Mehr = secondary destinations.
  static const List<Widget> _tabRoots = [
    SeasonsScreen(),
    PlanningTabScreen(),
    CostumingTabScreen(),
    MoreTabScreen(),
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
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-0-season'),
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-1-planen'),
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-2-kleidung'),
    GlobalKey<NavigatorState>(debugLabel: 'shell-tab-3-mehr'),
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
        // At the tab root: NO tab hopping (D3). The initial (Season) tab
        // issues the app-exit intent per platform convention; any other
        // tab root stays on the tab (the OS back intent is consumed —
        // back is never a tab-history step).
        if (state.selectedIndex == kSeasonTabIndex) {
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
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => AppShell._tabRoots[i],
              ),
            ),
        ],
      ),
    );

    return switch (sizeClass) {
      WindowSizeClass.compact => Column(
        children: [
          Expanded(child: content),
          ShellDestinations.navigationBar(
            selectedIndex: state.selectedIndex,
            onSelected: controller.selectTab,
            l10n: l10n,
          ),
        ],
      ),
      WindowSizeClass.medium => Row(
        children: [
          ShellDestinations.navigationRail(
            selectedIndex: state.selectedIndex,
            onSelected: controller.selectTab,
            l10n: l10n,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: content),
        ],
      ),
      WindowSizeClass.expanded => Row(
        children: [
          ShellDestinations.navigationDrawer(
            selectedIndex: state.selectedIndex,
            onSelected: controller.selectTab,
            l10n: l10n,
          ),
          Expanded(child: content),
        ],
      ),
    };
  }
}

/// The shell navigation suite: the three M3 morphologies built from ONE
/// destination list (glossary icons + visible labels + "Tab N of 4"
/// semantics). Public (non-private) so the semantics/touch-target widget
/// tests pump the EXACT suite widgets the shell renders — the framework's
/// test semantics pipeline prunes sibling-subtree annotations when an
/// IndexedStack hosts nested Navigators, so the traversal contract is
/// asserted against the suite standalone (same widget code).
class ShellDestinations {
  ShellDestinations._();

  static List<_DestinationSpec> _specs(AppLocalizations l10n) => [
    for (var i = 0; i < 4; i++) _DestinationSpec.tab(i, l10n),
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
/// and the "Tab N of 4" semantics label.
class _DestinationSpec {
  _DestinationSpec.tab(int index, AppLocalizations l10n)
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
    0 => l10n.navSeasons,
    1 => l10n.navPlanen,
    2 => l10n.navCostumes,
    _ => l10n.navMore,
  };
  static const _keySuffixes = [
    'shell-destination-0',
    'shell-destination-1',
    'shell-destination-2',
    'shell-destination-3',
  ];
  // Glossary (`docs/design/glossary.md`): home_outlined/Season,
  // edit_calendar_outlined/Planen, checkroom/Garderobe, more_horiz/Mehr.
  static const _outlineIcons = [
    BreakdownMaterialIcons.shellHomeOutline,
    BreakdownMaterialIcons.shellPlanenOutline,
    BreakdownMaterialIcons.shellCostumesOutline,
    BreakdownMaterialIcons.shellMore,
  ];
  static const _filledIcons = [
    BreakdownMaterialIcons.shellHomeFilled,
    BreakdownMaterialIcons.shellPlanenFilled,
    BreakdownMaterialIcons.shellCostumesFilled,
    BreakdownMaterialIcons.shellMore,
  ];
}
