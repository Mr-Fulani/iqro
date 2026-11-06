import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../plan/palm_growth.dart';
import '../plan/palm_growth_view.dart';
import '../plan/plan_repository.dart';
import 'home_open_replay.dart';

/// The day's reading goal under "Continue reading": on every opening a
/// traveller with a book walks along the bar to today's progress, towards
/// the palm that grows with the plan.
class HomePlanWalker extends StatefulWidget {
  const HomePlanWalker({
    required this.achieved,
    required this.target,
    required this.metric,
    required this.loading,
    required this.error,
    required this.onTap,
    this.palm,
    super.key,
  });

  final num achieved;
  final num target;
  final ReadingGoalMetric metric;
  final bool loading;
  final bool error;
  final VoidCallback onTap;
  final PalmGrowth? palm;

  @override
  State<HomePlanWalker> createState() => _HomePlanWalkerState();
}

class _HomePlanWalkerState extends State<HomePlanWalker>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        HomeOpenReplay<HomePlanWalker> {
  // Starts half a second after the sun, then walks for 2.2 seconds.
  static const _delay = .185;
  static const _total = Duration(milliseconds: 2700);
  static const _stepMs = 420.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );

  @override
  AnimationController get openController => _controller;

  @override
  bool get openReady => !widget.loading && !widget.error;

  @override
  void didUpdateWidget(HomePlanWalker oldWidget) {
    super.didUpdateWidget(oldWidget);
    playWhenReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _amount(num value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = switch (widget.metric) {
      ReadingGoalMetric.minutes => context.l10n.minutes,
      ReadingGoalMetric.pages => context.l10n.pages,
      ReadingGoalMetric.ayahs => context.l10n.ayahs,
    };
    final share = widget.loading || widget.error || widget.target <= 0
        ? 0.0
        : (widget.achieved / widget.target).clamp(0, 1).toDouble();
    final complete =
        !widget.loading && !widget.error && widget.target > 0 && share >= 1;
    final amount = widget.loading
        ? context.l10n.loading
        : widget.error
        ? context.l10n.openPlan
        : '${_amount(widget.achieved)} / ${_amount(widget.target)} $unit';
    return Semantics(
      key: const ValueKey('home-plan'),
      button: true,
      label: [
        context.l10n.dailyGoal,
        amount,
        if (complete) context.l10n.completed,
      ].join(', '),
      onTap: widget.onTap,
      child: InkWell(
        onTap: widget.onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(14),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          Text(
                            context.l10n.dailyGoal,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            complete
                                ? '$amount · ${context.l10n.completed}'
                                : amount,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (!widget.error) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 44,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              final v = _controller.value;
                              final walk = ((v - _delay) / (1 - _delay)).clamp(
                                0.0,
                                1.0,
                              );
                              final progress =
                                  share * Curves.easeInOutCubic.transform(walk);
                              final moving =
                                  _controller.isAnimating &&
                                  walk > 0 &&
                                  walk < 1;
                              final step = v * _total.inMilliseconds / _stepMs;
                              return _WalkerTrack(
                                progress: progress,
                                swing: moving ? math.sin(step * math.pi) : 0,
                                palm: widget.palm,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalkerTrack extends StatelessWidget {
  const _WalkerTrack({
    required this.progress,
    required this.swing,
    required this.palm,
  });

  final double progress;

  /// -1..1: how far the legs are apart while walking; 0 standing.
  final double swing;
  final PalmGrowth? palm;

  static const _palmSize = 34.0;
  static const _walker = Size(26, 34);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = constraints.maxWidth - _palmSize - 4;
        final x = rail * progress;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              start: 0,
              width: rail,
              bottom: 6,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.iqroColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            PositionedDirectional(
              start: 0,
              width: x,
              bottom: 6,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [primary, Color.lerp(primary, Colors.white, .22)!],
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: 0,
              bottom: 0,
              width: _palmSize,
              height: _palmSize,
              child: palm == null
                  ? Icon(Icons.flag_outlined, color: primary)
                  : PalmGrowthArt(
                      stage: palm!.stage,
                      mood: palm!.mood,
                      size: _palmSize,
                    ),
            ),
            PositionedDirectional(
              key: const ValueKey('home-plan-walker'),
              start: x - _walker.width / 2,
              bottom: 12,
              width: _walker.width,
              height: _walker.height,
              child: Transform.flip(
                flipX: rtl,
                child: CustomPaint(
                  painter: _WalkerPainter(
                    swing: swing,
                    robe: primary,
                    outline: context.iqroColors.line,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A traveller in a robe and a white cap, a book under the arm, facing the
/// direction of reading. Drawn on a 26 × 34 grid.
class _WalkerPainter extends CustomPainter {
  const _WalkerPainter({
    required this.swing,
    required this.robe,
    required this.outline,
  });

  final double swing;
  final Color robe;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 34);
    final bob = swing.abs() * 1.2;
    canvas.translate(0, -bob);
    final leg = Paint()
      ..color = robe
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const hip = Offset(13, 23);
    for (final (dx, sign) in [(-1.0, 1.0), (1.0, -1.0)]) {
      canvas.save();
      canvas.translate(hip.dx, hip.dy);
      canvas.rotate(sign * swing * .4);
      canvas.drawLine(Offset(dx, 0), Offset(dx * 2.5, 9), leg);
      canvas.restore();
    }
    canvas.drawPath(
      Path()
        ..moveTo(8.5, 11.5)
        ..quadraticBezierTo(13, 9.5, 17.5, 11.5)
        ..lineTo(18.5, 25)
        ..lineTo(7.5, 25)
        ..close(),
      Paint()..color = robe,
    );
    canvas.drawLine(const Offset(15, 13.5), const Offset(18.5, 17.5), leg);
    canvas.save();
    canvas.translate(20.5, 18.5);
    canvas.rotate(-12 * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3.5, -4, 7, 8),
        const Radius.circular(1.2),
      ),
      Paint()..color = const Color(0xFFD5A34C),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-3.2, -.9, 6.4, 1.2),
      Paint()..color = const Color(0xB3FFFDF8),
    );
    canvas.restore();
    canvas.drawCircle(
      const Offset(13, 6.6),
      3.6,
      Paint()..color = const Color(0xFFD9B48C),
    );
    final cap = Path()
      ..moveTo(9.4, 6)
      ..quadraticBezierTo(13, 1.4, 16.6, 6)
      ..close();
    canvas.drawPath(cap, Paint()..color = const Color(0xFFFFFDF8));
    canvas.drawPath(
      cap,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
  }

  @override
  bool shouldRepaint(_WalkerPainter old) =>
      old.swing != swing || old.robe != robe || old.outline != outline;
}
