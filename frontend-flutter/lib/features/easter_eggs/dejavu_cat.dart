// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/easter_eggs_store.dart';
import 'dejavu_cat_gate.dart';

/// Injectable clock for the October gate (issue #615, Decision D4):
/// production reads the wall clock, tests override it with a fixed date so
/// the month check is deterministic. The gate itself is pure
/// ([dejaVuCatActive]).
final dejaVuCatClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Wraps the launch splash body and paints the Deja-vu Cat while it is
/// active (issue #615, capability `flutter-easter-eggs`).
///
/// The cat is shown only when **both** the `dejaVuCat` egg flag is enabled
/// and the injected clock reports October; otherwise [child] is returned
/// untouched (no placeholder, no skeleton). It is non-interactive
/// (`IgnorePointer` — the splash owns no interaction) and honours the
/// system "remove animations" setting via [DejaVuCatWalker].
class DejaVuCatOverlay extends ConsumerWidget {
  const DejaVuCatOverlay({required this.child, this.clock, super.key});

  final Widget child;

  /// Test seam: overrides [dejaVuCatClockProvider] for this subtree.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(easterEggProvider(EasterEggId.dejaVuCat));
    final now = clock?.call() ?? ref.watch(dejaVuCatClockProvider)();
    if (!dejaVuCatActive(enabled: enabled, now: now)) return child;

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: DejaVuCatWalker(
            key: const Key('dejavu-cat'),
            animate: !disableAnimations,
          ),
        ),
      ],
    );
  }
}

/// The walking black cat (issue #615): a repeating, deterministic
/// [AnimationController] drives the horizontal travel across the lower
/// band of the splash, with the "déjà vu" pause/glance beat built into the
/// pure walk math. When [animate] is false (system "remove animations") no
/// controller runs and the cat renders a static pose at the pause beat.
///
/// Since issue #670 the cat is the approved Ghibli-inspired artwork: a
/// seated cat with a big head, large alert camera-facing eyes and the
/// tail wrapped around the front paws — it glides left→right with a
/// subtle walk bob, pauses mid-track and glances back (head tilt +
/// pupil shift) at the déjà-vu beat. The walk/travel/glance contracts
/// are unchanged (D4).
///
/// The walk loops continuously while the splash is visible; the
/// session-restore duration is never stretched to fit it.
class DejaVuCatWalker extends StatefulWidget {
  const DejaVuCatWalker({
    required this.animate,
    this.catWidth = 56,
    this.cycle = const Duration(seconds: 9),
    super.key,
  });

  /// False when the system "remove animations" setting is active.
  final bool animate;

  /// Logical width of the cat's visible silhouette (the painter box is
  /// taller: the approved art is a seated cat, height ≈ 1.39 × width).
  final double catWidth;

  /// One full walk cycle.
  final Duration cycle;

  @override
  State<DejaVuCatWalker> createState() => _DejaVuCatWalkerState();
}

class _DejaVuCatWalkerState extends State<DejaVuCatWalker>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(DejaVuCatWalker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    if (widget.animate && _controller == null) {
      _controller = AnimationController(vsync: this, duration: widget.cycle)
        ..repeat();
    } else if (!widget.animate && _controller != null) {
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
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          // The controller doubles as the repaint listenable: every tick
          // re-schedules a paint (the repaint proof test pins this).
          painter: _CatPainter(repaint: _controller, catWidth: widget.catWidth),
        ),
      ),
    );
  }
}

/// Static pose used when animations are disabled: the pause/glance beat,
/// so the cat sits mid-track and clearly visible (Decision D6).
const double _staticPhase = 0.60;

/// The approved artwork's fixed palette (issue #670, decision D3).
/// Do NOT add raw color literals outside this block (the
/// token-discipline convention pins it).
abstract final class _Art {
  /// Radial fur gradient: `#2b2b35` → `#1a1a21` → `#101015`
  /// (center 45%/35%, r 75% — objectBoundingBox semantics).
  static const furStops = [
    Color(0xFF2B2B35),
    Color(0xFF1A1A21),
    Color(0xFF101015),
  ];
  static const furOffsets = [0.0, 0.60, 1.0];

  /// Rim light `#b9c2d8`, alpha 0.55 → 0.08, top to bottom.
  static const rimColor = Color(0xFFB9C2D8);

  /// Tail stroke (`#141419`).
  static const tail = Color(0xFF141419);

  /// Ear outer (`#17171d`) and inner (`#43434f`).
  static const earOuter = Color(0xFF17171D);
  static const earInner = Color(0xFF43434F);

  /// Eye sclera (`#f7f3e8`), pupil (`#0e0e14`), highlights (white).
  static const sclera = Color(0xFFF7F3E8);
  static const pupil = Color(0xFF0E0E14);
  static const highlight = Color(0xFFFFFFFF);

  /// Nose (`#d8988f`) and mouth stroke (`#8f8f9c`).
  static const nose = Color(0xFFD8988F);
  static const mouth = Color(0xFF8F8F9C);

  /// Whiskers (`#b9b9c6`, 85%).
  static const whisker = Color(0xFFB9B9C6);

  /// Front paws (`#23232c`) and toe lines (`#0f0f14`).
  static const paw = Color(0xFF23232C);
  static const toeLine = Color(0xFF0F0F14);
}

/// Draws the approved Ghibli-inspired cat artwork (issue #670) and
/// positions it along the lower band for the current animation phase.
///
/// The painter is a hand-port of the approved SVG (decision D1 of
/// `670-easter-egg-redesign-karl-kleiderbuegel`): every SVG construct
/// maps 1:1 to Flutter painting — the near-black radial fur gradient
/// ([_Art.furStops] via `ui.Gradient.radial`), the soft blue-grey rim
/// light with per-stop alpha ([_Art.rimColor] via `ui.Gradient.linear`),
/// bézier paths and ellipses. Dev-time the port was pixel-compared
/// against an `rsvg-convert` reference render of the approved SVG.
///
/// The fixed palette ([_Art], decision D3) was chosen by design to keep
/// the near-black cat readable on BOTH light and dark surfaces (the
/// warm rim light replaces the old pure `onSurface` contour stroke) —
/// goldens in both themes protect that.
class _CatPainter extends CustomPainter {
  _CatPainter({Animation<double>? repaint, required this.catWidth})
    : _motion = repaint,
      super(repaint: repaint);

  /// Live animation phase; `null` = static pose.
  final Animation<double>? _motion;

  final double catWidth;

  /// Approved viewBox: the visible cat spans x 82–254, y 37–276.
  static const _viewWidth = 172.0; // 254 - 82
  static const _viewHeight = 239.0; // 276 - 37

  @override
  void paint(Canvas canvas, Size size) {
    final phase = _motion?.value ?? _staticPhase;
    final travel = dejaVuCatTravel(phase);
    final glance = dejaVuCatGlance(phase);

    final s = catWidth / _viewWidth;
    final h = _viewHeight * s;
    // Fully off the left edge at travel 0, fully off the right at travel 1.
    final x = -catWidth + travel * (size.width + catWidth);
    final y = size.height - 72 - h;

    canvas.save();
    canvas.translate(x - 82 * s, y - 37 * s);
    canvas.scale(s);

    // Walk bob: 12 whole sine cycles per controller cycle (continuous
    // across restarts), damped to zero through the déjà-vu pause so the
    // paused cat sits still.
    final bob = math.sin(phase * 2 * math.pi * 12) * 2.5 * (1 - glance);
    canvas.translate(0, bob);

    _drawTail(canvas);
    _drawBody(canvas);
    _drawHead(canvas, glance);
    _drawPaws(canvas);

    canvas.restore();
  }

  Shader _furShader(Rect bounds) => ui.Gradient.radial(
    Offset(
      bounds.left + 0.45 * bounds.width,
      bounds.top + 0.35 * bounds.height,
    ),
    0.75 * math.max(bounds.width, bounds.height),
    _Art.furStops,
    _Art.furOffsets,
  );

  /// The rim-light gradient over [bounds] (vertical, 55% → 8% alpha).
  Shader _rimShader(Rect bounds) => ui.Gradient.linear(
    Offset(bounds.left, bounds.top),
    Offset(bounds.left, bounds.bottom),
    [
      _Art.rimColor.withValues(alpha: 0.55),
      _Art.rimColor.withValues(alpha: 0.08),
    ],
  );

  void _rimStroke(
    Canvas canvas,
    Path path,
    double width, {
    double opacity = 1,
  }) {
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top),
          Offset(b.left, b.bottom),
          [
            _Art.rimColor.withValues(alpha: 0.55 * opacity),
            _Art.rimColor.withValues(alpha: 0.08 * opacity),
          ],
        ),
    );
  }

  void _drawTail(Canvas canvas) {
    final tail = Path()
      ..moveTo(234, 244)
      ..cubicTo(292, 250, 304, 192, 264, 172)
      ..cubicTo(240, 160, 216, 176, 222, 198);
    canvas.drawPath(
      tail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 27
        ..strokeCap = StrokeCap.round
        ..color = _Art.tail,
    );
    // Rim light on the tail's upper sweep.
    canvas.drawPath(
      Path()
        ..moveTo(234, 244)
        ..cubicTo(288, 248, 298, 196, 264, 177),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = _rimShader(tail.getBounds()),
    );
  }

  void _drawBody(Canvas canvas) {
    final body = Path()
      ..moveTo(97, 258)
      ..cubicTo(92, 212, 118, 186, 150, 181)
      ..lineTo(188, 181)
      ..cubicTo(221, 186, 245, 212, 240, 258)
      ..cubicTo(240, 268, 232, 275, 219, 275)
      ..lineTo(118, 275)
      ..cubicTo(105, 275, 97, 268, 97, 258)
      ..close();
    canvas.drawPath(body, Paint()..shader = _furShader(body.getBounds()));
    _rimStroke(
      canvas,
      Path()
        ..moveTo(104, 244)
        ..cubicTo(104, 214, 124, 194, 150, 188),
      3.5,
      opacity: 0.9,
    );
  }

  /// Head group: ears, head, face — tilted by the déjà-vu glance around
  /// the neck so the pause beat reads as a look back (D4).
  void _drawHead(Canvas canvas, double glance) {
    canvas.save();
    canvas.translate(168, 178);
    canvas.rotate(-0.10 * glance);
    canvas.translate(-168, -178);

    // Ears.
    canvas.drawPath(
      Path()
        ..moveTo(118, 98)
        ..cubicTo(107, 62, 109, 48, 120, 37)
        ..cubicTo(136, 45, 148, 58, 154, 78)
        ..close(),
      Paint()..color = _Art.earOuter,
    );
    canvas.drawPath(
      Path()
        ..moveTo(218, 98)
        ..cubicTo(229, 62, 227, 48, 216, 37)
        ..cubicTo(200, 45, 188, 58, 182, 78)
        ..close(),
      Paint()..color = _Art.earOuter,
    );
    canvas.drawPath(
      Path()
        ..moveTo(124, 88)
        ..cubicTo(118, 64, 119, 54, 124, 46)
        ..cubicTo(134, 52, 142, 62, 146, 76)
        ..close(),
      Paint()..color = _Art.earInner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(212, 88)
        ..cubicTo(218, 64, 217, 54, 212, 46)
        ..cubicTo(202, 52, 194, 62, 190, 76)
        ..close(),
      Paint()..color = _Art.earInner,
    );

    // Head.
    final headRect = Rect.fromCenter(
      center: const Offset(168, 134),
      width: 132,
      height: 114,
    );
    canvas.drawOval(headRect, Paint()..shader = _furShader(headRect));
    _rimStroke(
      canvas,
      Path()
        ..moveTo(118, 106)
        ..cubicTo(112, 88, 116, 68, 126, 56),
      3.5,
      opacity: 0.9,
    );

    // Eyes: large, alert, facing the camera; the pupils shift back on
    // the glance beat (the déjà-vu look).
    final eyeShift = Offset(-glance * 5, 0);
    for (final cx in const [149.0, 191.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 131), width: 35, height: 44),
        Paint()..color = _Art.sclera,
      );
    }
    for (final cx in const [152.0, 188.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, 134) + eyeShift,
          width: 18,
          height: 26,
        ),
        Paint()..color = _Art.pupil,
      );
    }
    canvas.drawCircle(
      Offset(149, 128) + eyeShift,
      3.4,
      Paint()..color = _Art.highlight,
    );
    canvas.drawCircle(
      Offset(185, 128) + eyeShift,
      3.4,
      Paint()..color = _Art.highlight,
    );
    canvas.drawCircle(
      Offset(155, 140) + eyeShift,
      1.6,
      Paint()..color = _Art.highlight.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      Offset(191, 140) + eyeShift,
      1.6,
      Paint()..color = _Art.highlight.withValues(alpha: 0.85),
    );

    // Nose + mouth.
    canvas.drawPath(
      Path()
        ..moveTo(162, 152)
        ..cubicTo(162, 147.5, 178, 147.5, 178, 152)
        ..cubicTo(178, 158, 170, 161, 170, 161)
        ..cubicTo(170, 161, 162, 158, 162, 152)
        ..close(),
      Paint()..color = _Art.nose,
    );
    canvas.drawPath(
      Path()
        ..moveTo(170, 161)
        ..cubicTo(167, 167, 162, 168, 158.5, 165)
        ..moveTo(170, 161)
        ..cubicTo(173, 167, 178, 168, 181.5, 165),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = _Art.mouth,
    );

    // Whiskers.
    final whisker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..color = _Art.whisker.withValues(alpha: 0.85);
    for (final (sx, sy, ex, ey) in const [
      (120.0, 142.0, 84.0, 134.0),
      (120.0, 150.0, 82.0, 151.0),
      (120.0, 158.0, 85.0, 169.0),
      (216.0, 142.0, 252.0, 134.0),
      (216.0, 150.0, 254.0, 151.0),
      (216.0, 158.0, 251.0, 169.0),
    ]) {
      canvas.drawLine(Offset(sx, sy), Offset(ex, ey), whisker);
    }

    canvas.restore();
  }

  void _drawPaws(Canvas canvas) {
    for (final cx in const [140.0, 196.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 266), width: 34, height: 20),
        Paint()..color = _Art.paw,
      );
      canvas.drawLine(
        Offset(cx, 259),
        Offset(cx, 272),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _Art.toeLine,
      );
    }
  }

  @override
  bool shouldRepaint(_CatPainter oldDelegate) =>
      oldDelegate.catWidth != catWidth ||
      // The controller can be disposed when `animate` flips to false
      // (static pose) — without this, CustomPaint may keep the last
      // animated frame.
      oldDelegate._motion != _motion;
}
