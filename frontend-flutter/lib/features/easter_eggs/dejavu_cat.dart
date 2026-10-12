// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

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

  /// Logical width of the cat box (height is `0.64 * catWidth`).
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
    final scheme = Theme.of(context).colorScheme;
    final controller = _controller;
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          // The controller doubles as the repaint listenable: every tick
          // re-schedules a paint (the repaint proof test pins this).
          painter: _CatPainter(
            repaint: controller,
            catWidth: widget.catWidth,
            // The PO requirement is a *black* cat in every theme. In
            // Material 3 `colorScheme.shadow` is the black token in both
            // light and dark schemes, so the body stays black; the
            // `onSurface` rim keeps it readable on the dark surface.
            body: scheme.shadow,
            outline: scheme.onSurface,
            accent: scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Static pose used when animations are disabled: the pause/glance beat,
/// so the cat sits mid-track and clearly visible (Decision D6).
const double _staticPhase = 0.60;

/// Draws the cat silhouette and positions it along the lower band for the
/// current animation phase. Colors come exclusively from the ambient
/// Material 3 color-scheme roles (design-token rule): a black body
/// (`colorScheme.shadow`) with a contrasting rim (`colorScheme.onSurface`)
/// so the cat stays black in BOTH themes, and a `primary` eye/whiskers.
class _CatPainter extends CustomPainter {
  _CatPainter({
    Animation<double>? repaint,
    required this.catWidth,
    required this.body,
    required this.outline,
    required this.accent,
  }) : _motion = repaint,
       super(repaint: repaint);

  /// Live animation phase; `null` = static pose.
  final Animation<double>? _motion;

  final double catWidth;
  final Color body;
  final Color outline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = _motion?.value ?? _staticPhase;
    final travel = dejaVuCatTravel(phase);
    final glance = dejaVuCatGlance(phase);

    final h = catWidth * 0.64;
    // Fully off the left edge at travel 0, fully off the right at travel 1.
    final x = -catWidth + travel * (size.width + catWidth);
    final y = size.height - 72 - h;

    canvas.save();
    canvas.translate(x, y);
    _drawCat(canvas, catWidth, h, glance);
    canvas.restore();
  }

  void _drawCat(Canvas canvas, double w, double h, double glance) {
    final bodyPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = body;
    // Limbs are drawn as a thicker outline stroke first, then the black
    // body stroke on top — a contrasting rim that keeps the black cat
    // readable on the dark surface.
    final limbRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = outline;
    final limbPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = body;
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.035
      ..strokeJoin = StrokeJoin.round
      ..color = outline;
    final accentPaint = Paint()..color = accent;

    // Tail: a curved stroke rising from the rear.
    final tail = Path()
      ..moveTo(w * 0.14, h * 0.66)
      ..cubicTo(-w * 0.02, h * 0.60, w * 0.02, h * 0.18, w * 0.20, h * 0.16);
    canvas.drawPath(tail, limbRim);
    canvas.drawPath(tail, limbPaint);

    // Legs: four short strokes, mid-stride.
    final stride = glance * h * 0.06;
    for (final (lx, dy) in [
      (0.28, 0.0),
      (0.42, stride),
      (0.66, -stride),
      (0.80, 0.0),
    ]) {
      final top = Offset(w * lx, h * 0.72);
      final bottom = Offset(w * lx, h * 0.98 + dy);
      canvas.drawLine(top, bottom, limbRim);
      canvas.drawLine(top, bottom, limbPaint);
    }

    // Body: a rounded elongated torso.
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, h * 0.40, w * 0.66, h * 0.36),
      Radius.circular(h * 0.18),
    );
    canvas.drawRRect(bodyRect, bodyPaint);
    canvas.drawRRect(bodyRect, rimPaint);

    // Head: shifted slightly back during the glance beat.
    final headCx = w * 0.80 - glance * w * 0.06;
    final headCy = h * 0.34;
    final headR = h * 0.24;
    // Ears.
    final ear = Path()
      ..moveTo(headCx - headR * 0.7, headCy - headR * 0.6)
      ..lineTo(headCx - headR * 0.9, headCy - headR * 1.5)
      ..lineTo(headCx - headR * 0.05, headCy - headR * 0.95)
      ..close();
    final ear2 = Path()
      ..moveTo(headCx + headR * 0.15, headCy - headR * 0.95)
      ..lineTo(headCx + headR * 0.95, headCy - headR * 1.4)
      ..lineTo(headCx + headR * 0.8, headCy - headR * 0.5)
      ..close();
    for (final earPath in [ear, ear2]) {
      canvas.drawPath(earPath, bodyPaint);
      canvas.drawPath(earPath, rimPaint);
    }
    canvas.drawCircle(Offset(headCx, headCy), headR, bodyPaint);
    canvas.drawCircle(Offset(headCx, headCy), headR, rimPaint);

    // Eye: a single visible eye (side view), looking back on the glance.
    final eyeDx = headCx + glance * headR * 0.35;
    canvas.drawCircle(
      Offset(eyeDx, headCy - headR * 0.05),
      headR * 0.20,
      accentPaint,
    );

    // Whiskers.
    final whisker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.025
      ..strokeCap = StrokeCap.round
      ..color = accent;
    for (final dy in [-0.10, 0.06]) {
      canvas.drawLine(
        Offset(headCx + headR * 0.5, headCy + h * dy),
        Offset(headCx + headR * 1.6, headCy + h * (dy - 0.06)),
        whisker,
      );
    }
  }

  @override
  bool shouldRepaint(_CatPainter oldDelegate) =>
      oldDelegate.catWidth != catWidth ||
      oldDelegate.body != body ||
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent ||
      // The controller can be disposed when `animate` flips to false
      // (static pose) — without this, CustomPaint may keep the last
      // animated frame.
      oldDelegate._motion != _motion;
}
