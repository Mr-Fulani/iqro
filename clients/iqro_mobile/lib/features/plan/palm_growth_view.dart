import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'palm_growth.dart';

/// Fixed palm palette, shared with the Android home-screen widget art.
abstract final class PalmColors {
  static const gold = Color(0xFFD5A34C);
  static const mint = Color(0xFFD6E5DA);
  static const green = Color(0xFF0B5D4A);
  static const sage = Color(0xFF91B4A5);
  static const sand = Color(0xFFE6D3A8);
  static const trunk = Color(0xFF8A6A3F);
  static const trunkDark = Color(0xFF6B5030);
  static const seed = Color(0xFF7A5230);
  static const dusk = Color(0xFFB9CBC2);
}

/// The palm art. Plays one short growth-and-settle animation when it first
/// appears or the stage changes, then rests; reduced motion draws it still.
class PalmGrowthArt extends StatefulWidget {
  const PalmGrowthArt({
    required this.stage,
    required this.mood,
    this.size = 96,
    super.key,
  });

  final PalmStage stage;
  final PalmMood mood;
  final double size;

  @override
  State<PalmGrowthArt> createState() => _PalmGrowthArtState();
}

class _PalmGrowthArtState extends State<PalmGrowthArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward(from: 0);
    }
    _started = true;
  }

  @override
  void didUpdateWidget(PalmGrowthArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return CustomPaint(
          painter: PalmPainter(
            stage: widget.stage,
            mood: widget.mood,
            growth: Curves.easeOutCubic.transform(t),
            // Damped sway that settles completely at the end.
            sway: math.sin(t * math.pi * 3) * (1 - t) * 0.09,
          ),
        );
      },
    ),
  );
}

class PalmPainter extends CustomPainter {
  const PalmPainter({
    required this.stage,
    required this.mood,
    this.growth = 1,
    this.sway = 0,
    this.celestial = true,
  });

  final PalmStage stage;
  final PalmMood mood;

  /// 0..1; the plant unfurls from 80% to full size.
  final double growth;

  /// Frond rotation in radians.
  final double sway;

  /// Draws the sun or moon of the mood; the home widget art leaves it out.
  final bool celestial;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    _paintSky(canvas);
    final scale = 0.8 + 0.2 * growth;
    const groundY = 84.0;
    switch (stage) {
      case PalmStage.seed:
        _paintSeed(canvas, groundY);
      case PalmStage.sprout:
        _paintSprout(canvas, groundY, scale);
      case PalmStage.seedling:
        _paintCrown(
          canvas,
          const Offset(50, groundY - 1),
          3,
          21 * scale,
          spread: 0.75,
        );
      case PalmStage.youngPalm:
        _paintPalm(canvas, groundY, 18 * scale, 5, 26 * scale);
      case PalmStage.palm:
        _paintPalm(canvas, groundY, 32 * scale, 7, 31 * scale);
      case PalmStage.fruitingPalm:
        _paintPalm(canvas, groundY, 36 * scale, 7, 32 * scale, dates: true);
    }
    _paintGround(canvas, groundY);
    canvas.restore();
  }

  void _paintSky(Canvas canvas) {
    final resting = mood == PalmMood.resting;
    canvas.drawCircle(
      const Offset(50, 50),
      48,
      Paint()
        ..color = (resting ? PalmColors.dusk : PalmColors.mint).withValues(
          alpha: .75,
        ),
    );
    if (!celestial) return;
    final gold = Paint()..color = PalmColors.gold;
    switch (mood) {
      case PalmMood.flourishing:
        canvas.drawCircle(
          const Offset(76, 24),
          15,
          Paint()..color = PalmColors.gold.withValues(alpha: .22),
        );
        canvas.drawCircle(const Offset(76, 24), 9, gold);
      case PalmMood.growing:
      case PalmMood.planting:
        canvas.drawCircle(
          const Offset(76, 28),
          7,
          Paint()..color = PalmColors.gold.withValues(alpha: .85),
        );
      case PalmMood.waiting:
        canvas.drawCircle(
          const Offset(78, 34),
          6,
          Paint()..color = PalmColors.gold.withValues(alpha: .55),
        );
      case PalmMood.resting:
        // A calm crescent: evening rest, never a wilted plant.
        final moon = Path()
          ..addOval(Rect.fromCircle(center: const Offset(76, 24), radius: 8));
        final cut = Path()
          ..addOval(Rect.fromCircle(center: const Offset(80, 21), radius: 7));
        canvas.drawPath(
          Path.combine(PathOperation.difference, moon, cut),
          gold,
        );
    }
  }

  void _paintGround(Canvas canvas, double groundY) {
    final mound = Path()
      ..moveTo(14, groundY + 4)
      ..quadraticBezierTo(50, groundY - 9, 86, groundY + 4)
      ..quadraticBezierTo(50, groundY + 12, 14, groundY + 4)
      ..close();
    canvas.drawPath(mound, Paint()..color = PalmColors.sand);
  }

  void _paintSeed(Canvas canvas, double groundY) {
    canvas.save();
    canvas.translate(50, groundY - 4);
    canvas.rotate(-0.35);
    final seed = Rect.fromCenter(center: Offset.zero, width: 18, height: 10);
    canvas.drawOval(seed, Paint()..color = PalmColors.seed);
    canvas.drawLine(
      const Offset(-6, 0),
      const Offset(6, 0),
      Paint()
        ..color = PalmColors.sand.withValues(alpha: .7)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _paintSprout(Canvas canvas, double groundY, double scale) {
    final base = Offset(50, groundY - 2);
    final top = base + Offset(0, -13 * scale);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(base.dx - 2, base.dy - 7 * scale, top.dx, top.dy),
      Paint()
        ..color = PalmColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    _paintFrond(canvas, top, -2.3 + sway, 10 * scale, leaflets: false);
    _paintFrond(canvas, top, -0.8 + sway, 11 * scale, leaflets: false);
  }

  void _paintPalm(
    Canvas canvas,
    double groundY,
    double trunkHeight,
    int fronds,
    double frondLength, {
    bool dates = false,
  }) {
    final base = Offset(50, groundY);
    final crown = Offset(51 + trunkHeight * .04, groundY - trunkHeight);
    final trunk = Path()
      ..moveTo(base.dx - 4, base.dy)
      ..quadraticBezierTo(
        base.dx - 3,
        base.dy - trunkHeight * .5,
        crown.dx - 2.2,
        crown.dy,
      )
      ..lineTo(crown.dx + 2.2, crown.dy)
      ..quadraticBezierTo(
        base.dx + 3,
        base.dy - trunkHeight * .5,
        base.dx + 4,
        base.dy,
      )
      ..close();
    canvas.drawPath(trunk, Paint()..color = PalmColors.trunk);
    final rings = Paint()
      ..color = PalmColors.trunkDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var y = base.dy - 4; y > crown.dy + 2; y -= 4.5) {
      final f = (base.dy - y) / trunkHeight;
      final x = base.dx + (crown.dx - base.dx) * f;
      final half = 3.6 - 1.4 * f;
      canvas.drawPath(
        Path()
          ..moveTo(x - half, y)
          ..quadraticBezierTo(x, y + 1.6, x + half, y),
        rings,
      );
    }
    if (dates) _paintDates(canvas, crown);
    _paintCrown(canvas, crown, fronds, frondLength);
  }

  void _paintDates(Canvas canvas, Offset crown) {
    final fruit = Paint()..color = PalmColors.gold;
    final shade = Paint()..color = const Color(0xFFB0812F);
    for (final side in <double>[-1, 1]) {
      final hang = crown + Offset(side * 5, 3);
      canvas.drawLine(
        crown + Offset(side * 1.5, 0),
        hang,
        Paint()
          ..color = PalmColors.trunkDark
          ..strokeWidth = 1,
      );
      const offsets = <Offset>[
        Offset(0, 1.5),
        Offset(-2.4, 3.5),
        Offset(2.4, 3.5),
        Offset(0, 5.6),
        Offset(-1.6, 7.4),
        Offset(1.6, 7.4),
      ];
      for (var i = 0; i < offsets.length; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: hang + Offset(offsets[i].dx * side, offsets[i].dy),
            width: 2.8,
            height: 3.6,
          ),
          i.isEven ? fruit : shade,
        );
      }
    }
  }

  void _paintCrown(
    Canvas canvas,
    Offset crown,
    int count,
    double length, {
    double spread = math.pi / 2 - 0.28,
  }) {
    // Fronds fan out around upright; a full palm reaches almost horizontal.
    final start = -math.pi / 2 - spread;
    final end = -math.pi / 2 + spread;
    for (var i = 0; i < count; i++) {
      final angle = start + (end - start) * i / (count - 1);
      // Outer fronds sway more than the upright ones.
      final weight = 0.4 + 0.6 * math.cos(angle + math.pi / 2).abs();
      _paintFrond(canvas, crown, angle + sway * weight, length);
    }
    canvas.drawCircle(crown, 2.4, Paint()..color = PalmColors.green);
  }

  void _paintFrond(
    Canvas canvas,
    Offset base,
    double angle,
    double length, {
    bool leaflets = true,
  }) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-dir.dy, dir.dx);
    // Horizontal fronds droop under their own weight.
    final droop = length * 0.45 * dir.dx.abs();
    final control = base + dir * (length * 0.6);
    final tip = base + dir * length + Offset(0, droop);
    final width = leaflets ? length * 0.11 : length * 0.28;
    Offset at(double t) =>
        base * ((1 - t) * (1 - t)) +
        control * (2 * (1 - t) * t) +
        tip * (t * t);

    if (leaflets) {
      final leaflet = Paint()
        ..color = PalmColors.sage
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      for (var t = 0.18; t < 0.96; t += 0.09) {
        final point = at(t);
        final tangent =
            (control - base) * (2 * (1 - t)) + (tip - control) * (2 * t);
        final unit = tangent / tangent.distance;
        final side = Offset(-unit.dy, unit.dx);
        final reach = length * 0.22 * (1 - t * 0.7);
        for (final s in <double>[-1, 1]) {
          canvas.drawLine(
            point,
            point + side * (reach * s) + unit * (reach * 0.55) + Offset(0, 1),
            leaflet,
          );
        }
      }
    }
    final blade = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(
        (control + normal * width).dx,
        (control + normal * width).dy,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        (control - normal * width).dx,
        (control - normal * width).dy,
        base.dx,
        base.dy,
      )
      ..close();
    canvas.drawPath(blade, Paint()..color = PalmColors.green);
  }

  @override
  bool shouldRepaint(PalmPainter oldDelegate) =>
      oldDelegate.stage != stage ||
      oldDelegate.mood != mood ||
      oldDelegate.growth != growth ||
      oldDelegate.sway != sway ||
      oldDelegate.celestial != celestial;
}

/// Plan tab card: the palm, its stage, a gentle mood line and the way ahead.
class PalmGrowthCard extends StatelessWidget {
  const PalmGrowthCard({required this.growth, super.key});

  final PalmGrowth growth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final next = growth.nextStage;
    return IqroCard(
      key: const ValueKey('palm-growth'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            image: true,
            label: palmStageLabel(l10n, growth.stage),
            child: ExcludeSemantics(
              child: PalmGrowthArt(stage: growth.stage, mood: growth.mood),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.palmTitle, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  palmStageLabel(l10n, growth.stage),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(palmMoodLabel(l10n, growth.mood)),
                const SizedBox(height: 12),
                Text(
                  next == null
                      ? l10n.palmFullyGrown
                      : l10n.palmNextStage(palmStageLabel(l10n, next)),
                  style: theme.textTheme.labelMedium,
                ),
                if (next != null) ...<Widget>[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: growth.progressToNext,
                    minHeight: 6,
                    color: PalmColors.gold,
                    backgroundColor: context.iqroColors.line,
                    borderRadius: BorderRadius.circular(4),
                    semanticsLabel: l10n.palmNextStage(
                      palmStageLabel(l10n, next),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(l10n.palmHowItGrows, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
