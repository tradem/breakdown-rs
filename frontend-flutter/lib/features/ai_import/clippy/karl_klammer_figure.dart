// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'clippy_trigger.dart';

/// Karl Klammer — the clothes-hanger assistant (issue #516, Decision D2;
/// redesigned as a comic-vector character in issue #614): a self-drawn
/// [CustomPainter] figure geometrically based on the app icon's
/// `checkroom` hanger glyph (Material Symbols, Apache-2.0 — the same
/// source the launcher icon uses; the drawing and its animation are our
/// own AGPL-3.0 work). Clippy's *behavior* on a hanger body.
///
/// Since issue #614 the figure is a **filled comic-vector silhouette**
/// with a clearly visible expressive face (sclera + pupils, eyebrows,
/// per-pose mouth). It blinks and shows per-pose motion. All colors come
/// from the ambient Material 3 color-scheme roles — no hardcoded colors
/// (design-token rule). When [animate] is false (the system "remove
/// animations" setting is active) the figure renders its static pose —
/// no controller runs at all.
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

/// Whether the eyes are closed at the given animation [phase] (`0..1`).
///
/// Pure and deterministic: the blink is a narrow window inside the
/// single controller cycle (issue #614), so a widget test can pump to a
/// known phase and reproduce the exact frame — no wall clock, no random.
bool karlEyesClosed(double phase) => phase >= 0.48 && phase <= 0.52;

/// Length of one full animation cycle in milliseconds. Every per-pose
/// motion period is a divisor of this value, so `bodyPhase` is
/// continuous across the controller restart (no jump at the cycle
/// boundary — CodeRabbit review #627).
const int _karlCycleMs = 4200;

/// Per-pose body-motion period in milliseconds. Each value is a divisor
/// of [_karlCycleMs] so the motion completes whole cycles per controller
/// restart (continuous phase — CodeRabbit review #627).
double _posePeriodMs(ClippyPose pose) => switch (pose) {
  ClippyPose.neutral => 2100, // 2 cycles — gentle bob
  ClippyPose.excited => 1050, // 4 cycles — energetic swing
  ClippyPose.droop => 4200, // 1 cycle — slow sag
  ClippyPose.proud => 1400, // 3 cycles — upright bounce
  ClippyPose.thinking => 2100, // 2 cycles — thoughtful sway
};

/// The body-motion phase (`0..1`) for [pose] at the controller [phase].
///
/// Every pose period divides the cycle, so this is continuous across the
/// controller restart: `karlBodyPhase(pose, 1) == karlBodyPhase(pose, 0)`
/// (CodeRabbit review #627). Pure and deterministic.
double karlBodyPhase(ClippyPose pose, double phase) =>
    (phase * _karlCycleMs / _posePeriodMs(pose)) % 1.0;

class _KarlKlammerFigureState extends State<KarlKlammerFigure>
    with SingleTickerProviderStateMixin {
  /// One full motion cycle. Body motion derives its per-pose phase from
  /// this value; the blink window sits at 0.48–0.52 of it.
  static const _cycle = Duration(milliseconds: _karlCycleMs);

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
    // Every pose now has a motion signature (issue #614), so the
    // controller runs whenever animations are enabled.
    final shouldAnimate = widget.animate;
    if (shouldAnimate && _controller == null) {
      _controller = AnimationController(vsync: this, duration: _cycle)
        ..repeat();
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
          // re-schedules a paint (the repaint proof test pins this).
          repaint: controller,
          pose: widget.pose,
          body: scheme.primary,
          sclera: scheme.onPrimary,
          pupil: scheme.primary,
          features: scheme.onPrimary,
          outline: scheme.outline,
        ),
      ),
    );
  }
}

/// Draws the comic-vector hanger (issue #614): a filled triangle body
/// (hook, head, shoulders, bottom bar / lower triangle) carrying a large
/// expressive head. Poses change the expression (eyes, eyebrows, mouth)
/// and the motion signature; [karlEyesClosed] drives the periodic blink.
class _HangerPainter extends CustomPainter {
  _HangerPainter({
    Animation<double>? repaint,
    required this.pose,
    required this.body,
    required this.sclera,
    required this.pupil,
    required this.features,
    required this.outline,
  }) : _motion = repaint,
       // Wires the live phase to the render object: every controller
       // tick marks the paint dirty (the repaint proof test pins this).
       super(repaint: repaint);

  /// Live animation phase (body motion + blink); `null` = static pose.
  final Animation<double>? _motion;

  final ClippyPose pose;

  final Color body;
  final Color sclera;
  final Color pupil;
  final Color features;
  final Color outline;

  static const _edge = 2.4;
  static const _headCenter = Offset(36, 23);
  static const _eyeLeft = Offset(31, 22);
  static const _eyeRight = Offset(41, 22);
  static const _eyeRadius = 3.4;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 72;
    canvas.scale(scale);

    final phase = _motion?.value ?? 0.0;
    final bodyPhase = karlBodyPhase(pose, phase);
    final wave = math.sin(bodyPhase * 2 * math.pi);

    // Pose transform (applied around the hook anchor at the top center).
    final angle = switch (pose) {
      ClippyPose.neutral => wave * 0.05,
      ClippyPose.excited => wave * 0.18,
      ClippyPose.droop => 0.32 + wave * 0.04, // slow permanent sag
      ClippyPose.proud => -0.07 + wave * 0.03, // upright bounce
      ClippyPose.thinking => 0.12 + wave * 0.04, // thoughtful sway
    };
    final dy = switch (pose) {
      ClippyPose.neutral => wave * 1.5,
      ClippyPose.excited => -wave.abs() * 3.5,
      ClippyPose.droop => 4.0 + wave * 1.0,
      ClippyPose.proud => -wave * 2.5,
      ClippyPose.thinking => wave * 1.0,
    };
    canvas.translate(36 + angle * 18, 8 + dy);
    canvas.rotate(angle);
    canvas.translate(-36, -8);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = body;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _edge
      ..strokeJoin = StrokeJoin.round
      ..color = outline;
    final hookPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = outline;

    // ── Hook: an OPEN clothes-hanger hook above the head (issue #641).
    // The stem rises from the head top, arcs over to the left and ends
    // in a small under-curl whose tip stays clearly above the head
    // outline and well away from the stem — the visible gap is what
    // makes the silhouette read as a hanger instead of a closed "bun".
    // (Head-stadium top point: (36, 11); the old curl ended at (32, 13)
    // INSIDE the head, which closed the loop.)
    final hook = Path()
      ..moveTo(36, 13)
      ..lineTo(36, 7)
      ..cubicTo(36, 2, 28, 1, 26, 5.5)
      ..cubicTo(24.5, 9, 26, 11, 28.5, 9.5);
    canvas.drawPath(hook, hookPaint);

    // ── Body: the filled hanger triangle (shoulders + bottom bar). ──
    final bodyPath = Path()
      ..moveTo(36, 30)
      ..quadraticBezierTo(20, 38, 9, 50)
      ..quadraticBezierTo(8, 52, 11, 52)
      ..lineTo(61, 52)
      ..quadraticBezierTo(64, 52, 63, 50)
      ..quadraticBezierTo(52, 38, 36, 30)
      ..close();
    canvas.drawPath(bodyPath, fill);
    canvas.drawPath(bodyPath, edge);

    // ── Head: a filled stadium carrying the face. ──
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(center: _headCenter, width: 22, height: 24),
      const Radius.circular(11),
    );
    canvas.drawRRect(head, fill);
    canvas.drawRRect(head, edge);

    _drawFace(canvas, phase);
  }

  void _drawFace(Canvas canvas, double phase) {
    final lid = Paint()
      ..style = PaintingStyle.fill
      ..color = body;
    final scleraPaint = Paint()..color = sclera;
    final pupilPaint = Paint()..color = pupil;
    final feature = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = features;

    // Eye opening + pupil gaze per pose (issue #614 expression table).
    final (open, gaze) = switch (pose) {
      ClippyPose.neutral => (1.0, const Offset(0, 0.2)),
      ClippyPose.excited => (1.0, const Offset(0, 0)),
      ClippyPose.droop => (0.55, const Offset(0, 0.8)),
      ClippyPose.proud => (1.0, const Offset(0, -0.3)),
      ClippyPose.thinking => (1.0, const Offset(0.3, -1.4)),
    };
    final openFraction = karlEyesClosed(phase) ? 0.0 : open;

    _drawEye(
      canvas,
      _eyeLeft,
      openFraction,
      gaze,
      scleraPaint,
      pupilPaint,
      lid,
    );
    _drawEye(
      canvas,
      _eyeRight,
      openFraction,
      gaze,
      scleraPaint,
      pupilPaint,
      lid,
    );

    // Eyebrows.
    final (leftBrowY, rightBrowY) = switch (pose) {
      ClippyPose.neutral => (15.6, 15.6),
      ClippyPose.excited => (13.6, 13.6),
      ClippyPose.droop => (17.0, 17.0),
      ClippyPose.proud => (13.8, 13.8),
      ClippyPose.thinking => (13.6, 15.8),
    };
    canvas.drawLine(Offset(27.5, leftBrowY), Offset(34.5, leftBrowY), feature);
    canvas.drawLine(
      Offset(37.5, rightBrowY),
      Offset(44.5, rightBrowY),
      feature,
    );

    // Mouth.
    _drawMouth(canvas, feature);
  }

  void _drawEye(
    Canvas canvas,
    Offset center,
    double openFraction,
    Offset gaze,
    Paint scleraPaint,
    Paint pupilPaint,
    Paint lid,
  ) {
    if (openFraction <= 0.02) {
      // Closed eye: a simple lash line.
      canvas.drawLine(
        Offset(center.dx - _eyeRadius, center.dy),
        Offset(center.dx + _eyeRadius, center.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = features,
      );
      return;
    }
    canvas.drawCircle(center, _eyeRadius, scleraPaint);
    canvas.drawCircle(center + gaze * 0.8, _eyeRadius * 0.48, pupilPaint);
    // Lids clip the sclera to the open fraction (half-lidded for droop).
    final top = center.dy - _eyeRadius * openFraction;
    final bottom = center.dy + _eyeRadius * openFraction;
    if (top > center.dy - _eyeRadius) {
      canvas.drawRect(
        Rect.fromLTRB(
          center.dx - _eyeRadius,
          center.dy - _eyeRadius,
          center.dx + _eyeRadius,
          top,
        ),
        lid,
      );
    }
    if (bottom < center.dy + _eyeRadius) {
      canvas.drawRect(
        Rect.fromLTRB(
          center.dx - _eyeRadius,
          bottom,
          center.dx + _eyeRadius,
          center.dy + _eyeRadius,
        ),
        lid,
      );
    }
  }

  void _drawMouth(Canvas canvas, Paint feature) {
    switch (pose) {
      case ClippyPose.excited:
        // Big open grin: a filled arc (the mouth interior).
        final grin = Path()
          ..moveTo(31, 28)
          ..quadraticBezierTo(36, 34, 41, 28)
          ..close();
        canvas.drawPath(
          grin,
          Paint()
            ..style = PaintingStyle.fill
            ..color = features,
        );
      case ClippyPose.droop:
        final frown = Path()
          ..moveTo(32, 31)
          ..quadraticBezierTo(36, 28, 40, 31);
        canvas.drawPath(frown, feature);
      case ClippyPose.proud:
        final smile = Path()
          ..moveTo(31.5, 28.5)
          ..quadraticBezierTo(36, 32, 40.5, 28.5);
        canvas.drawPath(smile, feature);
      case ClippyPose.thinking:
        canvas.drawLine(
          const Offset(33.5, 30),
          const Offset(38.5, 30),
          feature,
        );
      case ClippyPose.neutral:
        final smile = Path()
          ..moveTo(32, 29)
          ..quadraticBezierTo(36, 31.5, 40, 29);
        canvas.drawPath(smile, feature);
    }
  }

  @override
  bool shouldRepaint(_HangerPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.body != body ||
      oldDelegate.sclera != sclera ||
      oldDelegate.pupil != pupil ||
      oldDelegate.features != features ||
      oldDelegate.outline != outline ||
      // The controller can be disposed when `animate` flips to false
      // (static pose) — without this, CustomPaint may keep the last
      // animated frame (CodeRabbit review #627).
      oldDelegate._motion != _motion;
}
