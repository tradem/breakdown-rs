// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'planning_location.dart';

export 'planning_location.dart';

/// Tracks the route stack of ONE nested tab navigator so the shell's
/// context bar can resolve the topmost route's [PlanningLocation].
///
/// The location travels in `RouteSettings.arguments` (issue #548) — this
/// observer is only the *reactive seam*: Flutter's `NavigatorState` does
/// not expose its route stack, so the observer bookkeeps push/pop/remove/
/// replace callbacks into a stack and notifies listeners (the context bar
/// subscribes). Properties that make this the right transport:
///
/// - **Pop is free.** The route disappears, the location with it — the
///   strip updates in the same frame, no stale level, no `PopScope`
///   bookkeeping, no shell state to clear on pop paths.
/// - **Tab switches are free.** Each tab has its own nested navigator with
///   its own observer, so the strip shows the active tab's location with no
///   cross-tab state.
/// - Routes without a location argument (tab roots, sheets, config screens)
///   resolve to `null` — the strip hides.
class LocationRouteObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<Object?>> _stack = <Route<Object?>>[];

  /// Topmost tracked route, or `null` while the navigator has no routes.
  Route<Object?>? get topRoute => _stack.isEmpty ? null : _stack.last;

  /// The topmost route's [PlanningLocation], or `null`.
  PlanningLocation? get location {
    final route = topRoute;
    if (route == null) return null;
    return locationFromArguments(route.settings.arguments);
  }

  bool _deferred = false;

  /// Notifies listeners; a notification arriving DURING a build (the
  /// navigator mounts its initial route inside the build phase) is
  /// deferred to just after that frame — `markNeedsBuild` is forbidden
  /// mid-build, and the strip still paints the new location in the same
  /// frame.
  void _notify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      if (!_deferred) {
        _deferred = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _deferred = false;
          notifyListeners();
        });
      }
      return;
    }
    notifyListeners();
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _stack.add(route);
    _notify();
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _stack.remove(route);
    _notify();
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    _stack.remove(route);
    _notify();
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    if (oldRoute == null) {
      if (newRoute != null) _stack.add(newRoute);
    } else {
      final index = _stack.indexOf(oldRoute);
      if (index >= 0) {
        if (newRoute != null) {
          _stack[index] = newRoute;
        } else {
          _stack.removeAt(index);
        }
      } else if (newRoute != null) {
        _stack.add(newRoute);
      }
    }
    _notify();
  }
}

/// Pure resolution of the active location from a navigator: walks the
/// `LocationRouteObserver` registered on that navigator and reads its
/// topmost route's `RouteSettings.arguments`.
///
/// Returns `null` when the navigator has no observer (never in the shell)
/// or the topmost route carries no location — the strip hides.
PlanningLocation? locationOf(NavigatorState nav) {
  for (final observer in nav.widget.observers) {
    if (observer is LocationRouteObserver) {
      return observer.location;
    }
  }
  return null;
}
