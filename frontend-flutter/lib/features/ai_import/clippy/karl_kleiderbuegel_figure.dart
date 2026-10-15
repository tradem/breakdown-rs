// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'clippy_trigger.dart';

/// Karl Kleiderbügel — the clothes-hanger assistant (issue #516, Decision
/// D2; comic-vector redesign in issue #614; **approved-artwork redesign in
/// issue #670**, renamed from "Karl Klammer"): a hand-ported
/// [CustomPainter] of the user-drawn SVG artwork approved in the issue —
/// a classic wire-hanger silhouette with rounded triangle corners, a wire
/// twist at the neck, an inner strut below the apex, a wide sweeping hook
/// opening to the left, and an expressive face (big outlined eyes, bold
/// brows, open mouth). Clippy's *behavior* on a hanger body.
///
/// Rendering fidelity: every SVG construct maps 1:1 to Flutter painting
/// (per-element linear metal gradient, round caps/joins, group rotation)
/// except the SVG's `feDropShadow` filter on the face group, which is
/// **rebuilt Flutter-natively** as a blurred underlay
/// (`MaskFilter.blur`, σ=3, dy=3, 20% `#4a5568`) — decision D2 of
/// `670-easter-egg-redesign-karl-kleiderbuegel`. The colors are the
/// approved artwork's fixed palette (see [_Art], decision D3) chosen by
/// design to read on both themes; golden tests in light AND dark protect
/// that. Dev-time the port was pixel-compared against an `rsvg-convert`
/// reference render of the approved SVG.
///
/// The animation contracts are unchanged (issues #614/#615): five poses
/// with per-pose motion periods, a deterministic blink window, and the
/// static pose when [animate] is false (the system "remove animations"
/// setting) — only the drawn geometry was restyled (issue #670, D4).
class KarlKleiderbuegelFigure extends StatefulWidget {
  const KarlKleiderbuegelFigure({
    required this.pose,
    required this.animate,
    this.size = 72,
    super.key,
  });

  final ClippyPose pose;

  /// False when the system "remove animations" setting is active — the
  /// figure renders its static pose (spec `flutter-easter-eggs`).
  final bool animate;

  /// Logical box height; the box width follows the approved artwork's
  /// 900:500 viewBox aspect (`1.8 * size`) so the wide hanger silhouette
  /// is never squashed.
  final double size;

  @override
  State<KarlKleiderbuegelFigure> createState() =>
      _KarlKleiderbuegelFigureState();
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

class _KarlKleiderbuegelFigureState extends State<KarlKleiderbuegelFigure>
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
  void didUpdateWidget(KarlKleiderbuegelFigure oldWidget) {
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
    return SizedBox(
      width: widget.size * 1.8,
      height: widget.size,
      child: CustomPaint(
        painter: _HangerPainter(
          // The controller doubles as the repaint listenable: every tick
          // re-schedules a paint (the repaint proof test pins this).
          repaint: _controller,
          pose: widget.pose,
        ),
      ),
    );
  }
}

/// The approved artwork's fixed palette (issue #670, decision D3): the
/// user-drawn SVG was approved with exactly these colors, chosen to read
/// on light AND dark surfaces — the same exception as the launcher icon.
/// Do NOT add raw color literals outside this block (the token-discipline
/// test pins it).
abstract final class _Art {
  /// Dark wire outline / shadow stroke (`#606674`).
  static const outlineDark = Color(0xFF606674);

  /// 4-stop metal wire gradient (`#ffffff` → `#e8ecf1` → `#b6beca` →
  /// `#8a929f`, top to bottom).
  static const metalStops = [
    Color(0xFFFFFFFF),
    Color(0xFFE8ECF1),
    Color(0xFFB6BECA),
    Color(0xFF8A929F),
  ];
  static const metalStopOffsets = [0.0, 0.30, 0.65, 1.0];

  /// Glint line color (`#ffffff`, drawn with per-line opacity).
  static const glint = Color(0xFFFFFFFF);

  /// Cheek blush (`#f89ea4`, 60% opacity).
  static const cheek = Color(0xFFF89EA4);

  /// Eye sclera (`#ffffff`) and its outline (`#5d6574`).
  static const sclera = Color(0xFFFFFFFF);
  static const eyeStroke = Color(0xFF5D6574);

  /// Iris / brows (`#1b1f24`).
  static const iris = Color(0xFF1B1F24);
  static const brow = Color(0xFF1B1F24);

  /// Mouth interior (`#a43330`), its outline (`#5d6574`), teeth
  /// (`#ffffff`) and tongue (`#e26c68`).
  static const mouthFill = Color(0xFFA43330);
  static const mouthStroke = Color(0xFF5D6574);
  static const teeth = Color(0xFFFFFFFF);
  static const tongue = Color(0xFFE26C68);

  /// Rebuilt `feDropShadow` color: `#4a5568` at 20% (decision D2).
  static const faceShadow = Color(0x334A5568);
}

/// Draws the approved hanger artwork (issue #670) in the SVG's own
/// 900×500 coordinate space (group-rotated −3° around (450, 250), as in
/// the approved file). Poses change the expression (eyes, eyebrows,
/// mouth) and the motion signature; [karlEyesClosed] drives the periodic
/// blink. The wire shapes themselves never change with the pose.
class _HangerPainter extends CustomPainter {
  _HangerPainter({Animation<double>? repaint, required this.pose})
    : _motion = repaint,
      // Wires the live phase to the render object: every controller
      // tick marks the paint dirty (the repaint proof test pins this).
      super(repaint: repaint);

  /// Live animation phase (body motion + blink); `null` = static pose.
  final Animation<double>? _motion;

  final ClippyPose pose;

  /// Approved viewBox.
  static const _vw = 900.0;
  static const _vh = 500.0;

  /// Pose-transform pivot in SVG space: the hook base / neck, the same
  /// anatomical anchor the old figure rotated around (head top).
  static const _pivot = Offset(450, 130);

  /// Vertical-motion scale: the old table was tuned for a 72-unit box;
  /// the approved viewBox is 500 units tall, so the sag/bounce
  /// displacements keep their old fraction of the figure height (D4:
  /// same motion contracts, restyled geometry).
  static const _dyScale = _vh / 72;

  // ── Wire paths (verbatim from the approved SVG) ──────────────────────

  static Path _hook() => Path()
    ..moveTo(454, 178)
    ..cubicTo(458, 152, 452, 136, 446, 122)
    ..cubicTo(440, 108, 454, 94, 466, 78)
    ..cubicTo(478, 60, 472, 26, 438, 18)
    ..cubicTo(402, 10, 366, 26, 364, 64)
    ..cubicTo(362, 88, 384, 112, 402, 122);

  static Path _triangle() => Path()
    ..moveTo(450, 178)
    ..cubicTo(435, 180, 395, 215, 160, 348)
    ..cubicTo(130, 365, 140, 405, 175, 405)
    ..lineTo(760, 350)
    ..cubicTo(795, 347, 800, 305, 770, 292)
    ..cubicTo(525, 185, 465, 178, 450, 178)
    ..close();

  static Path _twist() => Path()
    ..moveTo(462, 172)
    ..quadraticBezierTo(448, 162, 440, 174)
    ..moveTo(460, 158)
    ..quadraticBezierTo(446, 148, 438, 160);

  static Path _strut() => Path()
    ..moveTo(418, 212)
    ..cubicTo(438, 185, 455, 185, 475, 210);

  static Path _hookGlint() => Path()
    ..moveTo(455, 120)
    ..cubicTo(453, 108, 464, 98, 472, 84)
    ..cubicTo(480, 70, 474, 34, 444, 26)
    ..cubicTo(414, 18, 378, 30, 376, 60);

  @override
  void paint(Canvas canvas, Size size) {
    // Fit the 900×500 viewBox into the box (box aspect is kept at 1.8,
    // so the two fits coincide; take the min for safety).
    final s = math.min(size.width / _vw, size.height / _vh);
    canvas.save();
    canvas.translate((size.width - _vw * s) / 2, (size.height - _vh * s) / 2);
    canvas.scale(s);

    // Pose transform around the hook pivot (outermost — the whole
    // figure moves; the values/periods are the #614 contracts).
    final phase = _motion?.value ?? 0.0;
    final bodyPhase = karlBodyPhase(pose, phase);
    final wave = math.sin(bodyPhase * 2 * math.pi);
    final angle = switch (pose) {
      ClippyPose.neutral => wave * 0.05,
      ClippyPose.excited => wave * 0.18,
      ClippyPose.droop => 0.32 + wave * 0.04, // slow permanent sag
      ClippyPose.proud => -0.07 + wave * 0.03, // upright bounce
      ClippyPose.thinking => 0.12 + wave * 0.04, // thoughtful sway
    };
    final dy = switch (pose) {
      ClippyPose.neutral => wave * 1.5 * _dyScale,
      ClippyPose.excited => -wave.abs() * 3.5 * _dyScale,
      ClippyPose.droop => 4.0 * _dyScale + wave * 1.0 * _dyScale,
      ClippyPose.proud => -wave * 2.5 * _dyScale,
      ClippyPose.thinking => wave * 1.0 * _dyScale,
    };
    canvas.translate(_pivot.dx + angle * 18 * _dyScale, _pivot.dy + dy);
    canvas.rotate(angle);
    canvas.translate(-_pivot.dx, -_pivot.dy);

    // The approved art's own −3° group rotation around (450, 250).
    canvas.translate(450, 250);
    canvas.rotate(-3 * math.pi / 180);
    canvas.translate(-450, -250);

    _drawWires(canvas);
    _drawFace(canvas, phase);

    canvas.restore();
  }

  void _drawWires(Canvas canvas) {
    // 1. Dark outer contour / shadow stroke, then 2. the metallic core
    // (draw order and widths verbatim from the approved SVG).
    void wire(
      Path path,
      double outlineWidth,
      double coreWidth, {
      bool roundJoin = false,
    }) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = roundJoin ? StrokeJoin.round : StrokeJoin.miter
          ..color = _Art.outlineDark,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = coreWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = roundJoin ? StrokeJoin.round : StrokeJoin.miter
          ..shader = _metalGradient(path.getBounds()),
      );
    }

    wire(_hook(), 20, 12);
    wire(_triangle(), 20, 12, roundJoin: true);
    wire(_twist(), 15, 9);
    wire(_strut(), 15, 8);

    // 3. Glint lines (white, per-line opacity, from the approved SVG).
    void glint(Path path, double width, double opacity) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = _Art.glint.withValues(alpha: opacity),
      );
    }

    glint(_hookGlint(), 3, 0.85);
    glint(
      Path()
        ..moveTo(430, 195)
        ..lineTo(165, 350),
      3,
      0.8,
    );
    glint(
      Path()
        ..moveTo(175, 400)
        ..lineTo(755, 347),
      2.5,
      0.6,
    );
  }

  /// The 4-stop metal gradient, evaluated over the path's own bounding
  /// box (the SVG's objectBoundingBox gradient semantics).
  Shader _metalGradient(Rect bounds) => ui.Gradient.linear(
    Offset(bounds.left, bounds.top),
    Offset(bounds.left, bounds.bottom),
    _Art.metalStops,
    _Art.metalStopOffsets,
  );

  void _drawFace(Canvas canvas, double phase) {
    final closed = karlEyesClosed(phase);

    // Expression table (issue #614 semantics, rescaled to the approved
    // face geometry): eye-opening fraction and pupil gaze per pose.
    final (open, gaze) = switch (pose) {
      ClippyPose.neutral => (1.0, const Offset(0, 0.2)),
      ClippyPose.excited => (1.0, const Offset(0, 0)),
      ClippyPose.droop => (0.55, const Offset(0, 0.8)),
      ClippyPose.proud => (1.0, const Offset(0, -0.3)),
      ClippyPose.thinking => (1.0, const Offset(0.3, -1.4)),
    };
    final openFraction = closed ? 0.0 : open;

    // Cheek blush (rotated ellipses, 60% — from the approved SVG).
    _cheek(canvas, const Offset(372, 336));
    _cheek(canvas, const Offset(546, 318));

    _drawEye(canvas, const Offset(406, 272), openFraction, gaze);
    _drawEye(canvas, const Offset(498, 264), openFraction, gaze);

    // Brows: the approved bold arcs, offset per pose (issue #614
    // expression table, rescaled: 1 old unit ≈ 7 SVG units).
    final (leftBrowDy, rightBrowDy) = switch (pose) {
      ClippyPose.neutral => (0.0, 0.0),
      ClippyPose.excited => (-14.0, -14.0),
      ClippyPose.droop => (10.0, 10.0),
      ClippyPose.proud => (-13.0, -13.0),
      ClippyPose.thinking => (-14.0, 1.4),
    };
    final browPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = _Art.brow;
    for (final (dyB, path) in [
      (leftBrowDy, _leftBrow()),
      (rightBrowDy, _rightBrow()),
    ]) {
      canvas.save();
      canvas.translate(0, dyB);
      canvas.drawPath(path, browPaint);
      canvas.restore();
    }

    _drawMouth(canvas);
  }

  static Path _leftBrow() => Path()
    ..moveTo(362, 240)
    ..cubicTo(375, 210, 412, 208, 428, 224);

  static Path _rightBrow() => Path()
    ..moveTo(466, 220)
    ..cubicTo(484, 200, 522, 202, 538, 226);

  void _cheek(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-6 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 40, height: 24),
      Paint()..color = _Art.cheek.withValues(alpha: 0.6),
    );
    canvas.restore();
  }

  /// One eye at [center]: rebuilt `feDropShadow` underlay (D2), sclera
  /// ellipse with outline, clipped to the [openFraction] (half-lidded
  /// for droop), iris + highlight dots offset by the gaze, or a closed
  /// lash line at the blink.
  void _drawEye(
    Canvas canvas,
    Offset center,
    double openFraction,
    Offset gaze,
  ) {
    const rx = 38.0;
    const ry = 46.0;
    final scleraRect = Rect.fromCenter(
      center: center,
      width: rx * 2,
      height: ry * 2,
    );

    // Rebuilt feDropShadow (σ=3, dy=3, 20% #4a5568) beneath the eye —
    // decision D2.
    canvas.drawOval(
      scleraRect.translate(0, 3),
      Paint()
        ..color = _Art.faceShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    if (openFraction <= 0.02) {
      // Closed eye (blink): a soft lash curve across the eye.
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - rx * 0.9, center.dy)
          ..quadraticBezierTo(
            center.dx,
            center.dy + 10,
            center.dx + rx * 0.9,
            center.dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = _Art.eyeStroke,
      );
      return;
    }

    // Outline + sclera: the outline always full, the interior clipped
    // to the open fraction (flat lid from the top — half-lidded droop).
    canvas.drawOval(
      scleraRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = _Art.eyeStroke,
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        scleraRect.left,
        center.dy - ry * openFraction,
        scleraRect.right,
        scleraRect.bottom,
      ),
    );
    canvas.drawOval(scleraRect, Paint()..color = _Art.sclera);

    // Iris + highlights (the approved pupil group, offset by the gaze).
    final pupilShift = Offset(gaze.dx * 30, gaze.dy * 24);
    canvas.save();
    canvas.translate(pupilShift.dx, pupilShift.dy);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 30, height: 40),
      Paint()..color = _Art.iris,
    );
    canvas.drawCircle(
      center + const Offset(-5, -8),
      5,
      Paint()..color = _Art.teeth,
    );
    canvas.drawCircle(
      center + const Offset(7, 10),
      2.5,
      Paint()..color = _Art.teeth,
    );
    canvas.restore();
    canvas.restore();
  }

  void _drawMouth(Canvas canvas) {
    switch (pose) {
      case ClippyPose.excited:
        // The approved big open grin: shadow + interior + teeth + tongue.
        final mouth = Path()
          ..moveTo(412, 342)
          ..cubicTo(445, 336, 470, 330, 504, 322)
          ..cubicTo(502, 360, 478, 382, 438, 376)
          ..cubicTo(422, 374, 414, 358, 412, 342)
          ..close();
        canvas.drawPath(
          mouth,
          Paint()
            ..color = _Art.faceShadow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawPath(mouth, Paint()..color = _Art.mouthFill);
        canvas.drawPath(
          mouth,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeJoin = StrokeJoin.round
            ..color = _Art.mouthStroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(420, 344)
            ..cubicTo(446, 340, 470, 334, 496, 329)
            ..cubicTo(488, 340, 435, 352, 420, 344)
            ..close(),
          Paint()..color = _Art.teeth,
        );
        canvas.drawPath(
          Path()
            ..moveTo(436, 364)
            ..cubicTo(455, 352, 476, 352, 488, 358)
            ..cubicTo(475, 376, 450, 376, 436, 364)
            ..close(),
          Paint()..color = _Art.tongue,
        );
      case ClippyPose.droop:
        _mouthStroke(
          canvas,
          Path()
            ..moveTo(430, 362)
            ..quadraticBezierTo(458, 338, 486, 362),
        );
      case ClippyPose.proud:
        _mouthStroke(
          canvas,
          Path()
            ..moveTo(428, 344)
            ..quadraticBezierTo(458, 366, 488, 344),
        );
      case ClippyPose.thinking:
        _mouthStroke(
          canvas,
          Path()
            ..moveTo(436, 350)
            ..lineTo(482, 350),
        );
      case ClippyPose.neutral:
        _mouthStroke(
          canvas,
          Path()
            ..moveTo(430, 348)
            ..quadraticBezierTo(458, 360, 486, 348),
        );
    }
  }

  void _mouthStroke(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = _Art.brow,
    );
  }

  @override
  bool shouldRepaint(_HangerPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      // The controller can be disposed when `animate` flips to false
      // (static pose) — without this, CustomPaint may keep the last
      // animated frame (CodeRabbit review #627).
      oldDelegate._motion != _motion;
}
