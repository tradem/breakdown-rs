// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/settings/easter_eggs_store.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../design/spacing.dart';
import 'clippy_trigger.dart';
import 'karl_klammer_figure.dart';

/// Karl Klammer overlay (issue #516, capability `flutter-easter-eggs`):
/// wraps an AI-Import screen's body and shows the clothes-hanger
/// assistant reacting to the given [ClippyFlowState].
///
/// Hard requirements (spec `flutter-easter-eggs`):
/// - **Visible only while Easter eggs are enabled** — `ref.watch`es
///   [easterEggsProvider]; toggled off, the bubble (and any running
///   timers/animations) disappear immediately without residue.
/// - **Non-modal** — an `Align(bottomLeft)` bubble above the content;
///   primary CTAs (FAB, bottom actions) are never covered; tap
///   dismisses for the session (until the next flow-state change).
/// - **Deterministic** — tips fire on flow-state changes; idle jokes on
///   a [Timer.periodic] whose zone is the widget-test fake-async clock
///   (`tester.pump(duration)` controls it — no wall clock, no random).
///   The idle period is injectable for tests.
/// - **Accessible** — one semantics node: a dismissible button whose
///   label announces the tip; the figure internals are excluded. The
///   system "remove animations" setting renders a static pose.
/// - No network calls, no event tracking.
class KarlKlammerOverlay extends ConsumerStatefulWidget {
  const KarlKlammerOverlay({
    required this.flowState,
    required this.child,
    this.idlePeriod,
    super.key,
  });

  /// The AI-Import flow state this screen is in (derived by the host
  /// screen from its own providers — never from a second projection
  /// call).
  final ClippyFlowState flowState;

  final Widget child;

  /// Idle-joke period. Test seam: widget tests pass a short period and
  /// drive it with `tester.pump` (fake-async deterministic). Defaults
  /// to 45 s of screen-idle in production.
  final Duration? idlePeriod;

  @override
  ConsumerState<KarlKlammerOverlay> createState() => _KarlKlammerOverlayState();
}

class _KarlKlammerOverlayState extends ConsumerState<KarlKlammerOverlay> {
  static const _defaultIdlePeriod = Duration(seconds: 45);

  bool _dismissed = false;
  ClippyTip? _tip;
  int _triggerCount = 0;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _onFlowState();
  }

  @override
  void didUpdateWidget(KarlKlammerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flowState != widget.flowState) {
      _onFlowState();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onFlowState() {
    _idleTimer?.cancel();
    _idleTimer = null;
    setState(() {
      // A new flow state is new content: re-show even if dismissed.
      _dismissed = false;
      // Idle is OCCASIONAL: no tip on entering idle — only the periodic
      // joke ticks (deterministically cycled). Concrete trigger states
      // (noConfig/running/error/success) react immediately.
      _tip = widget.flowState == ClippyFlowState.idle
          ? null
          : clippyTipFor(widget.flowState, triggerCount: _triggerCount++);
      if (widget.flowState == ClippyFlowState.idle) {
        _idleTimer = Timer.periodic(
          widget.idlePeriod ?? _defaultIdlePeriod,
          (_) => _onIdleTick(),
        );
      }
    });
  }

  void _onIdleTick() {
    if (_dismissed || widget.flowState != ClippyFlowState.idle) return;
    setState(() {
      _tip = clippyTipFor(widget.flowState, triggerCount: _triggerCount++);
    });
  }

  void _dismiss() {
    _idleTimer?.cancel();
    _idleTimer = null;
    setState(() {
      _dismissed = true;
      _tip = null;
    });
  }

  String _tipText(ClippyTipKey key) {
    final l10n = l10nOf(context);
    return switch (key) {
      ClippyTipKey.noConfig => l10n.aiImportClippyNoConfig,
      ClippyTipKey.running => l10n.aiImportClippyRunning,
      ClippyTipKey.error => l10n.aiImportClippyError,
      ClippyTipKey.success => l10n.aiImportClippySuccess,
      ClippyTipKey.idle1 => l10n.aiImportClippyIdle1,
      ClippyTipKey.idle2 => l10n.aiImportClippyIdle2,
      ClippyTipKey.idle3 => l10n.aiImportClippyIdle3,
    };
  }

  @override
  Widget build(BuildContext context) {
    final easterEggsEnabled = ref.watch(easterEggsProvider);
    if (!easterEggsEnabled) {
      // Immediate, residue-free disappearance: no bubble, no skeleton,
      // no placeholder — and the timers are torn down on dispose below.
      return widget.child;
    }

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final tip = _tip;
    final l10n = l10nOf(context);

    return Stack(
      children: [
        widget.child,
        if (tip != null && !_dismissed)
          // Bottom-leading: primary CTAs (FABs, bottom action rows) sit
          // bottom-leading→bottom-center on these screens; the bubble is
          // compact and tap-dismissible, never blocking.
          Positioned(
            left: AppSpacing.space12,
            bottom: AppSpacing.space16,
            child: Semantics(
              button: true,
              label: l10n.aiImportClippyDismissTooltip,
              onTap: _dismiss,
              child: ExcludeSemantics(
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.space12),
                  elevation: 2,
                  child: InkWell(
                    key: const Key('karl-klammer-bubble'),
                    borderRadius: BorderRadius.circular(AppSpacing.space12),
                    onTap: _dismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          KarlKlammerFigure(
                            key: const Key('karl-klammer-figure'),
                            pose: tip.pose,
                            animate: !disableAnimations,
                          ),
                          const SizedBox(width: AppSpacing.space8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(_tipText(tip.key)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
