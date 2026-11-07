import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../plan/palm_growth.dart';
import '../plan/palm_growth_view.dart';
import '../plan/plan_repository.dart';
import 'home_open_replay.dart';

/// The day's reading goal under "Continue reading": on every opening the
/// rub al-hizb mark (۞, which marks the quarters of a hizb in the Mushaf)
/// travels along the bar to today's progress, turning a quarter turn, towards
/// the palm that grows with the plan.
class HomePlanProgress extends StatefulWidget {
  const HomePlanProgress({
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
  State<HomePlanProgress> createState() => _HomePlanProgressState();
}

class _HomePlanProgressState extends State<HomePlanProgress>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        HomeOpenReplay<HomePlanProgress> {
  // Starts half a second after the sun, then travels for 2.2 seconds.
  static const _delay = .185;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2700),
  );

  @override
  AnimationController get openController => _controller;

  @override
  bool get openReady => !widget.loading && !widget.error;

  @override
  void didUpdateWidget(HomePlanProgress oldWidget) {
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
                        const SizedBox(height: 6),
                        // The mark moves every frame of the opening; its
                        // own layer keeps the reading card, its shadow and
                        // the rest of Home from repainting with it.
                        RepaintBoundary(
                          child: SizedBox(
                            height: 36,
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) {
                                final travel = Curves.easeInOutCubic.transform(
                                  ((_controller.value - _delay) / (1 - _delay))
                                      .clamp(0.0, 1.0),
                                );
                                return _MarkTrack(
                                  progress: share * travel,
                                  turn: travel * math.pi / 2,
                                  palm: widget.palm,
                                );
                              },
                            ),
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

class _MarkTrack extends StatelessWidget {
  const _MarkTrack({
    required this.progress,
    required this.turn,
    required this.palm,
  });

  final double progress;

  /// Rotation of the mark in radians: a quarter turn over the journey.
  final double turn;
  final PalmGrowth? palm;

  static const _palmSize = 34.0;
  static const _mark = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
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
              bottom: 12,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.iqroColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            PositionedDirectional(
              start: 0,
              width: x,
              bottom: 12,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            PositionedDirectional(
              end: 0,
              bottom: 0,
              width: _palmSize,
              height: _palmSize,
              // The palm stands still while the mark travels to it.
              child: RepaintBoundary(
                child: palm == null
                    ? Icon(Icons.flag_outlined, color: primary)
                    : PalmGrowthArt(
                        stage: palm!.stage,
                        mood: palm!.mood,
                        size: _palmSize,
                      ),
              ),
            ),
            PositionedDirectional(
              key: const ValueKey('home-plan-mark'),
              start: x - _mark / 2,
              bottom: 15 - _mark / 2,
              width: _mark,
              height: _mark,
              child: Transform.rotate(
                angle: turn,
                child: CustomPaint(
                  painter: _HizbMarkPainter(
                    gold: context.iqroColors.gold,
                    fill: theme.colorScheme.surface,
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

/// ۞: two squares, one turned 45°, around a ring, as printed in the Mushaf.
class _HizbMarkPainter extends CustomPainter {
  const _HizbMarkPainter({required this.gold, required this.fill});

  final Color gold;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final side = size.width * .58;
    final rect = Rect.fromCenter(center: center, width: side, height: side);
    final stroke = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final solid = Paint()..color = fill;
    for (final angle in [0.0, math.pi / 4]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.translate(-center.dx, -center.dy);
      final square = RRect.fromRectAndRadius(rect, const Radius.circular(1));
      canvas.drawRRect(square, solid);
      canvas.drawRRect(square, stroke);
      canvas.restore();
    }
    canvas.drawCircle(center, side * .19, stroke..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_HizbMarkPainter old) =>
      old.gold != gold || old.fill != fill;
}
