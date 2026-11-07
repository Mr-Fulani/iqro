import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design_system/iqro_widgets.dart';
import '../prayer/prayer_repository.dart';
import 'home_open_replay.dart';
import 'home_view_data.dart';

/// The day's five prayers and sunrise, in order, as on the site's sky band.
const skyStopCodes = <String>[
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

/// Minutes after the schedule's local midnight.
double skyMinuteOf(DateTime time) =>
    time.hour * 60 + time.minute + time.second / 60;

/// Label centres for the six stops: at their marks, pushed apart where two
/// times are close (fajr and sunrise in Mecca) so that names never overlap.
/// The same rule as the site's `spreadLabels` (lib/sky-band.ts).
List<double> spreadSkyLabels(
  List<double> marks,
  double width,
  double gap, {
  double edge = 22,
}) {
  final xs = [...marks];
  for (var index = 1; index < xs.length; index++) {
    xs[index] = math.max(xs[index], xs[index - 1] + gap);
  }
  xs[xs.length - 1] = math.min(xs.last, width - edge);
  for (var index = xs.length - 2; index >= 0; index--) {
    xs[index] = math.min(xs[index], xs[index + 1] - gap);
  }
  xs[0] = math.max(xs[0], edge);
  return xs;
}

/// The colours of the sky at one moment.
@immutable
class SkyPalette {
  const SkyPalette({
    required this.top,
    required this.middle,
    required this.horizon,
    required this.ground,
    required this.darkness,
    required this.stars,
  });

  final Color top;
  final Color middle;
  final Color horizon;
  final Color ground;

  /// 0 under a dark sky (white text), 1 under the day sky (deep ink text).
  final double darkness;
  final double stars;

  Color get ink => Color.lerp(Colors.white, const Color(0xFF08293A), darkness)!;
  Color get button => Colors.white.withValues(alpha: .18 + .37 * darkness);

  SkyPalette dimmed(double amount) => SkyPalette(
    top: Color.lerp(top, Colors.black, amount)!,
    middle: Color.lerp(middle, Colors.black, amount)!,
    horizon: Color.lerp(horizon, Colors.black, amount)!,
    ground: ground,
    darkness: darkness,
    stars: stars,
  );

  static SkyPalette lerp(SkyPalette a, SkyPalette b, double t) => SkyPalette(
    top: Color.lerp(a.top, b.top, t)!,
    middle: Color.lerp(a.middle, b.middle, t)!,
    horizon: Color.lerp(a.horizon, b.horizon, t)!,
    ground: Color.lerp(a.ground, b.ground, t)!,
    darkness: ui.lerpDouble(a.darkness, b.darkness, t)!,
    stars: ui.lerpDouble(a.stars, b.stars, t)!,
  );
}

const _night = SkyPalette(
  top: Color(0xFF060E23),
  middle: Color(0xFF101B40),
  horizon: Color(0xFF24315F),
  ground: Color(0x52000000),
  darkness: 0,
  stars: 1,
);
const _dawn = SkyPalette(
  top: Color(0xFF1E2A58),
  middle: Color(0xFF6B5A90),
  horizon: Color(0xFFF0A06C),
  ground: Color(0x4D18122E),
  darkness: 0,
  stars: .55,
);
const _day = SkyPalette(
  top: Color(0xFF3C8DCB),
  middle: Color(0xFF8CC6EA),
  horizon: Color(0xFFDCEFF8),
  ground: Color(0x85FFFFFF),
  darkness: 1,
  stars: 0,
);
const _sunset = SkyPalette(
  top: Color(0xFF3B3974),
  middle: Color(0xFFC7607A),
  horizon: Color(0xFFF6B067),
  ground: Color(0x4D301022),
  darkness: 0,
  stars: .15,
);
const _dusk = SkyPalette(
  top: Color(0xFF211D4A),
  middle: Color(0xFF5A3E73),
  horizon: Color(0xFFB0627A),
  ground: Color(0x52140A1E),
  darkness: 0,
  stars: .5,
);

/// The day's stops in minutes and the sky's colour at any minute of it.
@immutable
class SkyTimeline {
  const SkyTimeline(this.stops);

  /// Null when a time is missing or the order is broken (polar days).
  static SkyTimeline? fromSchedule(PrayerSchedule? schedule) {
    final times = schedule?.times;
    if (times == null) return null;
    final stops = <double>[];
    for (final code in skyStopCodes) {
      final time = times[code];
      if (time == null) return null;
      final minute = skyMinuteOf(time);
      if (stops.isNotEmpty && minute <= stops.last) return null;
      stops.add(minute);
    }
    return SkyTimeline(stops);
  }

  final List<double> stops;

  double get fajr => stops[0];
  double get sunrise => stops[1];
  double get maghrib => stops[4];
  double get isha => stops[5];

  /// Where the opening animation starts: the sun just below the horizon, or
  /// an hour and a half back for a time before dawn.
  double startFor(double now) => math.min(sunrise - 61, now - 90);

  SkyPalette paletteAt(double minute) {
    // The same moments as the site (sky-band.ts), around the real sunrise
    // and sunset of the city.
    final keys = <(double, SkyPalette)>[
      (fajr - 52, _night),
      (sunrise - 61, _dawn),
      (sunrise + 59, _day),
      (maghrib - 98, _day),
      (maghrib - 33, _sunset),
      (maghrib + 52, _dusk),
      (isha + 48, _night),
    ];
    var previous = double.negativeInfinity;
    final ordered = [
      for (final (at, palette) in keys)
        (previous = math.max(previous + 1, at), palette),
    ];
    if (minute <= ordered.first.$1) return ordered.first.$2;
    for (var index = 0; index < ordered.length - 1; index++) {
      final (from, a) = ordered[index];
      final (to, b) = ordered[index + 1];
      if (minute <= to) {
        return SkyPalette.lerp(a, b, (minute - from) / (to - from));
      }
    }
    return ordered.last.$2;
  }
}

/// Home's prayer card: the sky of the day with the sun on its arc from
/// sunrise to maghrib, and the day's prayers on the ground. On every opening
/// the sun rises from the horizon to the present time.
class HomePrayerSkyCard extends StatefulWidget {
  const HomePrayerSkyCard({
    required this.schedule,
    required this.loading,
    required this.clock,
    required this.onTap,
    required this.onQibla,
    required this.onReminders,
    super.key,
  });

  final PrayerSchedule? schedule;
  final bool loading;
  final DateTime clock;
  final VoidCallback onTap;
  final VoidCallback onQibla;
  final VoidCallback onReminders;

  @override
  State<HomePrayerSkyCard> createState() => _HomePrayerSkyCardState();
}

class _HomePrayerSkyCardState extends State<HomePrayerSkyCard>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        HomeOpenReplay<HomePrayerSkyCard> {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
    value: 0,
  );

  // Without a schedule the sky still follows the hour, with typical times.
  static const _fallback = SkyTimeline([300, 390, 750, 930, 1080, 1170]);

  @override
  AnimationController get openController => _controller;

  @override
  bool get openReady => SkyTimeline.fromSchedule(widget.schedule) != null;

  @override
  void didUpdateWidget(HomePrayerSkyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    playWhenReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _name(BuildContext context, String? code) => switch (code) {
    'fajr' => context.l10n.fajr,
    'sunrise' => context.l10n.sunrise,
    'dhuhr' => context.l10n.dhuhr,
    'asr' => context.l10n.asr,
    'maghrib' => context.l10n.maghrib,
    'isha' => context.l10n.isha,
    _ => context.l10n.prayer,
  };

  @override
  Widget build(BuildContext context) {
    final timeline = SkyTimeline.fromSchedule(widget.schedule);
    final now = skyMinuteOf(widget.clock);
    final next = nextPrayerOccurrence(widget.schedule, widget.clock);
    final minutes = next == null
        ? 0
        : next.time.difference(widget.clock).inMinutes.clamp(0, 2880);
    final countdown =
        '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
    final title = widget.loading
        ? context.l10n.loading
        : next == null
        ? context.l10n.prayer
        : '${_name(context, next.code)} ${DateFormat.Hm().format(next.time)}';
    final subtitle = widget.loading
        ? ''
        : next == null
        ? context.l10n.prayerUnavailable
        : context.l10n.homePrayerIn(countdown);
    final times = widget.schedule?.times ?? const <String, DateTime>{};
    final labels = [for (final code in skyStopCodes) _name(context, code)];
    final clocks = [
      for (final code in skyStopCodes)
        times[code] == null ? '—' : DateFormat.Hm().format(times[code]!),
    ];
    final nextIndex = next == null ? -1 : skyStopCodes.indexOf(next.code);
    final tomorrow = timeline != null && now > timeline.isha;
    final dim = Theme.of(context).brightness == Brightness.dark ? .14 : 0.0;
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(16) > 20;
    final labelScale = scaler.scale(1).clamp(1.0, 1.5);
    final groundHeight = 16 + 26 * labelScale;
    final summary = [
      title,
      subtitle,
      for (var index = 0; index < labels.length; index++)
        '${labels[index]} ${clocks[index]}',
    ].where((part) => part.isNotEmpty).join(', ');

    return Semantics(
      key: const ValueKey('home-prayer'),
      button: true,
      label: summary,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final drawn = timeline ?? _fallback;
          final start = drawn.startFor(now);
          // The sun travels for the first 80%, then its glow breathes once.
          // While the schedule loads the sky waits at dawn, where the sun
          // will rise from.
          final t = timeline == null
              ? (widget.loading ? 0.0 : 1.0)
              : Curves.easeInOutCubic.transform(
                  math.min(1, _controller.value / .8),
                );
          final minute = start + (now - start) * t;
          final palette = drawn.paletteAt(minute).dimmed(dim);
          final ink = palette.ink;
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.top,
                    palette.middle,
                    palette.horizon,
                    palette.horizon,
                  ],
                  stops: const [0, .42, .7, 1],
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  excludeFromSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          12,
                          10,
                          0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ExcludeSemantics(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.l10n.nextPrayer,
                                      style: text.bodySmall?.copyWith(
                                        color: ink.withValues(alpha: .85),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      title,
                                      style: text.titleLarge?.copyWith(
                                        color: ink,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    // Kept while loading, so the card does
                                    // not grow when the schedule arrives.
                                    Text(
                                      subtitle.isEmpty ? ' ' : subtitle,
                                      style: text.bodySmall?.copyWith(
                                        color: ink.withValues(alpha: .92),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _SkyButton(
                              key: const ValueKey('home-prayer-qibla'),
                              icon: Icons.explore_outlined,
                              tooltip: context.l10n.qibla,
                              palette: palette,
                              onPressed: widget.onQibla,
                            ),
                            const SizedBox(width: 6),
                            _SkyButton(
                              key: const ValueKey('home-prayer-reminders'),
                              icon: Icons.notifications_none_rounded,
                              tooltip: context.l10n.reminders,
                              palette: palette,
                              onPressed: widget.onReminders,
                            ),
                          ],
                        ),
                      ),
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 82 + groundHeight,
                          child: CustomPaint(
                            painter: SkyPainter(
                              timeline: drawn,
                              minute: minute,
                              palette: palette,
                              showSun: timeline != null,
                              labels: timeline == null ? const [] : labels,
                              clocks: clocks,
                              nextIndex: nextIndex,
                              allPassed: tomorrow && minute > drawn.isha,
                              groundHeight: groundHeight,
                              labelScale: labelScale.toDouble(),
                              evenly: large,
                              rtl:
                                  Directionality.of(context) ==
                                  TextDirection.rtl,
                              arrived: _controller.value,
                              labelStyle: text.labelSmall ?? const TextStyle(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkyButton extends StatelessWidget {
  const _SkyButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final SkyPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: palette.button,
      foregroundColor: palette.ink,
      minimumSize: const Size(44, 44),
    ),
    icon: Icon(icon, size: 22),
  );
}

// Star positions on a 361-wide band, as on the site.
const _stars = <(double, double, double)>[
  (22, 14, 1.2),
  (58, 30, .9),
  (96, 10, 1),
  (132, 40, .8),
  (170, 18, 1.3),
  (214, 34, .9),
  (250, 12, 1),
  (292, 28, 1.1),
  (330, 16, .8),
  (118, 62, .7),
  (196, 58, .8),
  (46, 54, .9),
  (270, 52, .7),
  (344, 48, 1),
];

/// Draws the arc, the sun or the moon, the ground and the day's prayers.
class SkyPainter extends CustomPainter {
  const SkyPainter({
    required this.timeline,
    required this.minute,
    required this.palette,
    required this.showSun,
    required this.labels,
    required this.clocks,
    required this.nextIndex,
    required this.allPassed,
    required this.groundHeight,
    required this.labelScale,
    required this.evenly,
    required this.rtl,
    required this.arrived,
    required this.labelStyle,
  });

  final SkyTimeline timeline;
  final double minute;
  final SkyPalette palette;
  final bool showSun;
  final List<String> labels;
  final List<String> clocks;
  final int nextIndex;
  final bool allPassed;
  final double groundHeight;
  final double labelScale;

  /// Large text: the stops are evenly spaced so that labels never overlap,
  /// and sunrise keeps only its mark.
  final bool evenly;
  final bool rtl;

  /// The opening animation's progress: past 0.8 the sun's glow breathes once.
  final double arrived;

  /// The theme's label font, so that every script has its glyphs.
  final TextStyle labelStyle;

  static const _gold = Color(0xFFF4C24E);
  static const _pad = 28.0;

  double _x(double m, double width) {
    final stops = timeline.stops;
    final span = width - 2 * _pad;
    if (!evenly) {
      return _pad + (m - stops[0]) / (stops[5] - stops[0]) * span;
    }
    var index = 0;
    while (index < 4 && m > stops[index + 1]) {
      index++;
    }
    final f = ((m - stops[index]) / (stops[index + 1] - stops[index])).clamp(
      0.0,
      1.0,
    );
    return _pad + (index + f) * span / 5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final horizon = size.height - groundHeight;
    final ink = palette.ink;
    final scaleX = width / 361;
    canvas.save();
    if (rtl) {
      canvas.translate(width, 0);
      canvas.scale(-1, 1);
    }
    // Stars.
    if (palette.stars > .01) {
      for (final (x, y, r) in _stars) {
        if (y > horizon - 6) continue;
        canvas.drawCircle(
          Offset(x * scaleX, y),
          r,
          Paint()
            ..color = Colors.white.withValues(
              alpha: (palette.stars * (.45 + r / 3)).clamp(0, 1),
            ),
        );
      }
    }
    final x0 = _x(timeline.sunrise, width);
    final x1 = _x(timeline.maghrib, width);
    final cx = (x0 + x1) / 2;
    final rx = (x1 - x0) / 2;
    final ry = math.min(60.0, horizon - 14);
    final oval = Rect.fromCenter(
      center: Offset(cx, horizon),
      width: rx * 2,
      height: ry * 2,
    );
    // Dashed path of the sun.
    final arc = Path()..addArc(oval, math.pi, math.pi);
    final dash = Paint()
      ..color = ink.withValues(alpha: .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in arc.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 3), dash);
      }
    }
    // The moon after dusk and before dawn.
    final moon = minute > timeline.maghrib + 42
        ? ((minute - timeline.maghrib - 42) / 90).clamp(0.0, 1.0)
        : minute < timeline.fajr - 20
        ? 1.0
        : 0.0;
    if (moon > 0) {
      final center = Offset(width - 64, 26);
      canvas.drawCircle(
        center,
        24,
        Paint()
          ..shader = ui.Gradient.radial(center, 24, [
            const Color(0xFFFFF6DA).withValues(alpha: .35 * moon),
            const Color(0x00FFF6DA),
          ]),
      );
      final crescent = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: center, radius: 11)),
        Path()..addOval(
          Rect.fromCircle(center: center + const Offset(5, -4), radius: 9.5),
        ),
      );
      canvas.drawPath(
        crescent,
        Paint()..color = const Color(0xFFF3E7C4).withValues(alpha: moon),
      );
    }
    // The sun on its arc, rising behind the horizon or set below it.
    if (showSun) {
      final trail = Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      Offset? sun;
      var opacity = 1.0;
      if (minute > timeline.sunrise && minute < timeline.maghrib) {
        final sx = _x(minute, width);
        final dx = ((sx - cx) / rx).clamp(-1.0, 1.0);
        final angle = 2 * math.pi - math.acos(dx);
        sun = Offset(sx, horizon + ry * math.sin(angle));
        canvas.drawPath(Path()..addArc(oval, math.pi, angle - math.pi), trail);
      } else {
        final before = minute <= timeline.sunrise;
        // Dawn shows the sun waiting at the horizon for a while; after
        // maghrib it sinks faster.
        final depth = before
            ? ((timeline.sunrise - minute) / 120).clamp(0.0, 1.0)
            : ((minute - timeline.maghrib) / 70).clamp(0.0, 1.0);
        opacity = 1 - depth;
        sun = Offset(before ? x0 : x1, horizon + 2 + depth * 18);
        if (!before && opacity > .02) {
          canvas.drawPath(
            Path()..addArc(oval, math.pi, math.pi),
            trail..color = _gold.withValues(alpha: .9 * opacity),
          );
        }
      }
      if (opacity > .02) {
        final breath = arrived > .8
            ? 1 + .45 * math.sin(math.pi * (arrived - .8) / .2)
            : 1.0;
        final glow = 30.0 * breath;
        canvas.drawCircle(
          sun,
          glow,
          Paint()
            ..shader = ui.Gradient.radial(
              sun,
              glow,
              [
                const Color(0xFFFFF4C8).withValues(alpha: .95 * opacity),
                const Color(0xFFFFE08A).withValues(alpha: .45 * opacity),
                const Color(0x00FFE08A),
              ],
              const [0, .35, 1],
            ),
        );
        canvas.drawCircle(
          sun,
          10.5,
          Paint()..color = const Color(0xFFFFD55E).withValues(alpha: opacity),
        );
        canvas.drawCircle(
          sun,
          10.5,
          Paint()
            ..color = const Color(0xFFFFF3C4).withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    // Ground under the horizon.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, width, groundHeight),
      Paint()..color = palette.ground,
    );
    canvas.drawLine(
      Offset(0, horizon),
      Offset(width, horizon),
      Paint()
        ..color = ink.withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    canvas.restore();

    // Marks and labels, drawn unmirrored at their mirrored places.
    if (labels.length != 6) return;
    final labelXs = spreadSkyLabels(
      [for (final stop in timeline.stops) _x(stop, width)],
      width,
      46 * labelScale,
    );
    for (var index = 0; index < 6; index++) {
      final stop = timeline.stops[index];
      final lx = _x(stop, width);
      final x = rtl ? width - lx : lx;
      final labelX = rtl ? width - labelXs[index] : labelXs[index];
      final next = index == nextIndex;
      final sunrise = index == 1;
      final passed = allPassed ? index != 0 : minute >= stop;
      final opacity = next ? 1.0 : (passed ? .6 : .9);
      final mark = Offset(x, horizon);
      if (next) {
        canvas.drawCircle(mark, 6.5, Paint()..color = _gold);
        canvas.drawCircle(
          mark,
          6.5,
          Paint()
            ..color = ink.withValues(alpha: .5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        final radius = sunrise ? 2.6 : 3.6;
        canvas.drawCircle(
          mark,
          radius,
          Paint()
            ..color = ink.withValues(alpha: opacity)
            ..style = passed ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }
      if (evenly && sunrise) continue;
      final color = next && palette.darkness < .5
          ? const Color(0xFFFFD98A)
          : ink.withValues(alpha: opacity);
      _label(
        canvas,
        labels[index],
        Offset(labelX, horizon + 6),
        10.5 * labelScale,
        next ? FontWeight.w700 : FontWeight.w400,
        color,
      );
      _label(
        canvas,
        clocks[index],
        Offset(labelX, horizon + 6 + 13 * labelScale),
        12.5 * labelScale,
        next ? FontWeight.w700 : FontWeight.w600,
        color,
        numeric: true,
      );
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset top,
    double size,
    FontWeight weight,
    Color color, {
    bool numeric = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.1,
          letterSpacing: 0,
          fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: numeric
          ? TextDirection.ltr
          : (rtl ? TextDirection.rtl : TextDirection.ltr),
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(top.dx - painter.width / 2, top.dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.minute != minute ||
      old.palette != palette ||
      old.labels != labels ||
      old.clocks != clocks ||
      old.nextIndex != nextIndex ||
      old.allPassed != allPassed ||
      old.rtl != rtl ||
      old.evenly != evenly ||
      old.groundHeight != groundHeight ||
      old.arrived != arrived;
}
