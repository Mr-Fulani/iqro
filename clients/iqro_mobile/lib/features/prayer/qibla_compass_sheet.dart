import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'prayer_places.dart';
import 'qibla_compass.dart';

enum _CompassState { waiting, live, unavailable }

/// Qibla sheet with a live compass. Until the first heading arrives, or when
/// the device has no compass, the dial stays a static bearing from north.
class QiblaCompassSheet extends StatefulWidget {
  const QiblaCompassSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.locationName,
    this.compass = const QiblaCompass(),
  });

  final double latitude;
  final double longitude;
  final String locationName;
  final QiblaCompass compass;

  @override
  State<QiblaCompassSheet> createState() => _QiblaCompassSheetState();
}

class _QiblaCompassSheetState extends State<QiblaCompassSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final double _bearing = qiblaBearing(
    latitude: widget.latitude,
    longitude: widget.longitude,
  );
  late final double _declination = magneticDeclination(
    latitude: widget.latitude,
    longitude: widget.longitude,
  );
  final _smoother = HeadingSmoother();
  late final Ticker _ticker = createTicker(_tick);
  StreamSubscription<Object?>? _subscription;
  CompassReading? _reading;
  var _state = _CompassState.waiting;
  var _aligned = false;
  var _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The sensors run only while the sheet is visible.
    if (state == AppLifecycleState.resumed) {
      _listen();
    } else {
      _subscription?.cancel();
      _subscription = null;
      _ticker.stop();
    }
  }

  void _listen() {
    if (_subscription != null || _state == _CompassState.unavailable) return;
    _subscription = widget.compass.events().listen(
      _onEvent,
      onError: (Object _) {
        _subscription?.cancel();
        _subscription = null;
        _ticker.stop();
        if (mounted) setState(() => _state = _CompassState.unavailable);
      },
    );
  }

  void _onEvent(Object? event) {
    final reading = compassReadingFromEvent(event, declination: _declination);
    if (reading == null || !mounted) return;
    _reading = reading;
    _state = _CompassState.live;
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final reading = _reading;
    if (reading == null) return;
    final heading = _smoother.step(reading.heading, elapsed - _lastTick);
    _lastTick = elapsed;
    final deviation = angleDifference(heading, _bearing).abs();
    // An uncalibrated compass must not claim the phone faces the Qibla.
    final aligned =
        !reading.needsCalibration &&
        deviation <= (_aligned ? qiblaReleaseDegrees : qiblaAlignedDegrees);
    if (aligned && !_aligned) unawaited(_alignedPulse());
    setState(() => _aligned = aligned);
    // The next sample restarts the ticker.
    if (angleDifference(heading, reading.heading).abs() < .05) _ticker.stop();
  }

  Future<void> _alignedPulse() async {
    try {
      await HapticFeedback.heavyImpact();
    } on PlatformException {
      // Haptics are best effort; the highlight still shows the alignment.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final heading = _state == _CompassState.live ? _smoother.value : null;
    final calibrate = heading != null && _reading!.needsCalibration;
    final degrees = '${_bearing.round()}° ${l10n.fromGeographicNorth}';
    final String hint;
    if (calibrate) {
      hint = l10n.qiblaCalibrationHint;
    } else if (heading != null) {
      hint = l10n.qiblaLiveHint;
    } else if (_state == _CompassState.unavailable) {
      hint = '${l10n.qiblaCompassUnavailable} ${l10n.qiblaNorthHint}';
    } else {
      hint = l10n.qiblaNorthHint;
    }
    final Widget status;
    if (calibrate) {
      status = _Status(
        key: const ValueKey('qibla-calibrate'),
        icon: Icons.all_inclusive,
        text: l10n.qiblaCalibrationNeeded,
        color: colors.error,
      );
    } else if (_aligned) {
      status = _Status(
        key: const ValueKey('qibla-aligned'),
        icon: Icons.check_circle,
        text: l10n.qiblaFacing,
        color: colors.primary,
      );
    } else {
      status = const SizedBox.shrink();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.qiblaDirection, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(widget.locationName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 22),
          Semantics(
            label: '${l10n.qiblaDirection}: $degrees',
            image: true,
            child: SizedBox.square(
              key: const ValueKey('qibla-dial'),
              dimension: 220,
              child: CustomPaint(
                painter: _DialPainter(
                  bearing: _bearing,
                  heading: heading,
                  aligned: _aligned,
                  north: l10n.qiblaNorth,
                  textStyle: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                  colors: colors,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(degrees, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          // Fixed height, so the sheet does not jump when the status changes.
          SizedBox(
            height: 28,
            child: Semantics(liveRegion: true, child: Center(child: status)),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// The site's dial (`PrayerQibla.tsx`) on a 200×200 grid: with a live heading
/// the dial turns so its north matches the real north, and a fixed mark at the
/// top shows where the phone points.
class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.bearing,
    required this.heading,
    required this.aligned,
    required this.north,
    required this.textStyle,
    required this.colors,
  });

  final double bearing;
  final double? heading;
  final bool aligned;
  final String north;
  final TextStyle textStyle;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200);
    const center = Offset(100, 100);
    canvas.drawCircle(
      center,
      92,
      Paint()..color = colors.primary.withValues(alpha: aligned ? .22 : .08),
    );
    canvas.drawCircle(
      center,
      92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 4 : 2
        ..color = colors.primary,
    );

    canvas.save();
    _rotate(canvas, -(heading ?? 0));
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = colors.onSurfaceVariant;
    for (var index = 0; index < 36; index++) {
      canvas.save();
      _rotate(canvas, index * 10.0);
      canvas.drawLine(
        const Offset(100, 12),
        Offset(100, index % 9 == 0 ? 24 : 18),
        tick,
      );
      canvas.restore();
    }
    final label = TextPainter(
      text: TextSpan(text: north, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(100 - label.width / 2, 40 - label.height / 2));
    label.dispose();

    _rotate(canvas, bearing);
    canvas.drawPath(
      Path()
        ..moveTo(100, 170)
        ..lineTo(108, 106)
        ..lineTo(100, 112)
        ..lineTo(92, 106)
        ..close(),
      Paint()..color = colors.outlineVariant,
    );
    canvas.drawPath(
      Path()
        ..moveTo(100, 30)
        ..lineTo(114, 104)
        ..lineTo(100, 94)
        ..lineTo(86, 104)
        ..close(),
      Paint()..color = colors.primary,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(93, 18, 107, 32, const Radius.circular(2)),
      Paint()..color = colors.onSurface,
    );
    canvas.restore();

    if (heading != null) {
      canvas.drawPath(
        Path()
          ..moveTo(100, 13)
          ..lineTo(93, 0)
          ..lineTo(107, 0)
          ..close(),
        Paint()..color = aligned ? colors.primary : colors.onSurface,
      );
    }
    canvas.drawCircle(center, 5, Paint()..color = colors.surface);
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colors.primary,
    );
  }

  void _rotate(Canvas canvas, double degrees) {
    canvas
      ..translate(100, 100)
      ..rotate(degrees * math.pi / 180)
      ..translate(-100, -100);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.bearing != bearing ||
      old.heading != heading ||
      old.aligned != aligned ||
      old.north != north ||
      old.textStyle != textStyle ||
      old.colors != colors;
}
