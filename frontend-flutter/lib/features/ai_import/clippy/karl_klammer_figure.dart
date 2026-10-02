// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'clippy_trigger.dart';

/// Karl Klammer — the clothes-hanger assistant (issue #516, Decision D2):
/// a self-drawn [CustomPainter] figure geometrically based on the app
/// icon's `checkroom` hanger glyph (Material Symbols, Apache-2.0 — the
/// same source the launcher icon uses; the drawing and its animation are
/// our own AGPL-3.0 work). Clippy's *behavior* on a hanger body.
///
/// All colors come from the ambient Material 3 color-scheme roles — no
/// hardcoded colors (design-token rule). When [animate] is false (the
/// system "remove animations" setting is active) the figure renders its
/// static pose — no controller runs at all.
class KarlKlammerFigure extends StatefulWidget {
  const KarlKlammerFigure({
    required this.pose,
    required this.animate,
    this.size = 72,
    super.key,
  });

  final ClippyPose pose;

  /// False when the system "remove animations" setting is active — the
  /// figure renders its static pose (spec `flutter-easter-eggs`).
  final bool animate;

  final double size;

  @override
  State<KarlKlammerFigure> createState() => _KarlKlammerFigureState();
}

class _KarlKlammerFigureState extends State<KarlKlammerFigure>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(KarlKlammerFigure oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final shouldAnimate = widget.animate && widget.pose == ClippyPose.excited;
    if (shouldAnimate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
    } else if (!shouldAnimate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = _controller;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _HangerPainter(
          // The controller doubles as the repaint listenable: every tick
          // re-schedules a paint (CodeRabbit fix — a plain field read in
          // build never repaints the wobble).
          repaint: controller,
          pose: widget.pose,
          body: scheme.primary,
          face: scheme.onSurfaceVariant,
          outline: scheme.outline,
        ),
      ),
    );
  }
}

/// Draws the hanger: hook with a small face on it (Karl's head),
/// shoulder bar, and the bottom triangle. Poses rotate/tilt the figure:
/// `excited` swings by the controller phase read inside [paint],
/// `droop` leans sideways with a downturned mouth, `proud` tilts
/// slightly upright with a smiling face.
class _HangerPainter extends CustomPainter {
  _HangerPainter({
    Animation<double>? repaint,
    required this.pose,
    required this.body,
    required this.face,
    required this.outline,
  }) : _wobble = repaint,
       // Wires the live phase to the render object: every controller
       // tick marks the paint dirty (the repaint proof test pins this).
       super(repaint: repaint);

  /// Live animation phase (the excited wobble); `null` = static poses.
  final Animation<double>? _wobble;

  final ClippyPose pose;

  final Color body;
  final Color face;
  final Color outline;

  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 72;
    canvas.scale(scale);

    final wobble = _wobble?.value ?? 0.0;

    // Pose transform (applied around the hook anchor at the top center).
    final angle = switch (pose) {
      ClippyPose.excited => math.sin(wobble * 2 * math.pi) * 0.12,
      ClippyPose.droop => 0.35, // permanent lean — the hanger droops
      ClippyPose.proud => -0.08, // slight proud tilt back
      ClippyPose.neutral => 0.0,
    };
    final dy = switch (pose) {
      // Drooping also sinks a little.
      ClippyPose.droop => 4.0,
      _ => 0.0,
    };
    canvas.translate(36 + angle * 20, 8 + dy);
    canvas.rotate(angle);
    canvas.translate(-36, -8);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = body;

    // ── Hook (Karl's "head"): bezier hook opening to the left. ──
    final hook = Path()
      ..moveTo(36, 34)
      ..lineTo(36, 18)
      ..cubicTo(36, 10, 27, 8, 25, 14)
      ..cubicTo(24, 18, 28, 21, 32, 19);
    canvas.drawPath(hook, paint);

    // ── Face on the hook: two eyes + a mouth. ──
    final facePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = face;
    final smile = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = face;
    // Eyes sit on the hook stem.
    canvas.drawCircle(const Offset(33.6, 22), 1.1, facePaint);
    canvas.drawCircle(const Offset(38.4, 22), 1.1, facePaint);
    // Mouth: downturned when drooping, wide smile otherwise.
    final mouth = Path()
      ..moveTo(33, 27)
      ..quadraticBezierTo(
        36,
        pose == ClippyPose.droop ? 25.5 : 30,
        39,
        pose == ClippyPose.droop ? 27 : 27,
      );
    canvas.drawPath(mouth, smile);

    // ── Shoulders: from the stem down to the two bar tips. ──
    final shoulders = Path()
      ..moveTo(36, 34)
      ..lineTo(6, 46)
      ..moveTo(36, 34)
      ..lineTo(66, 46);
    canvas.drawPath(shoulders, paint);

    // ── Bottom bar connecting the tips. ──
    canvas.drawLine(const Offset(6, 46), const Offset(66, 46), paint);
  }

  @override
  bool shouldRepaint(_HangerPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.body != body ||
      oldDelegate.face != face ||
      oldDelegate.outline != outline;
}
