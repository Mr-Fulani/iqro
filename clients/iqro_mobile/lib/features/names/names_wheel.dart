import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/iqro_theme.dart';
import 'names_models.dart';

enum _Motion { idle, drag, inertia, snap }

/// The colours of the wheel, taken from the app's theme.
@immutable
class NamesWheelColors {
  const NamesWheelColors({
    required this.face,
    required this.faceEdge,
    required this.rim,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.gold,
    required this.text,
    required this.muted,
  });

  factory NamesWheelColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iqro = context.iqroColors;
    return NamesWheelColors(
      face: scheme.surface,
      faceEdge: iqro.panelSoft,
      rim: scheme.outline,
      line: iqro.line,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      gold: iqro.gold,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
    );
  }

  final Color face;
  final Color faceEdge;
  final Color rim;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color gold;
  final Color text;
  final Color muted;

  @override
  bool operator ==(Object other) =>
      other is NamesWheelColors &&
      other.face == face &&
      other.faceEdge == faceEdge &&
      other.rim == rim &&
      other.line == line &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.gold == gold &&
      other.text == text &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(
    face,
    faceEdge,
    rim,
    line,
    accent,
    onAccent,
    gold,
    text,
    muted,
  );
}

/// The wheel of the Names (docs/names-of-allah/README.md): a dial of labels
/// with a magnifier at the needle and tasbih ticks every 11 and 33. A finger
/// turns it, with inertia and a snap to a name; a tap on the centre moves to
/// the next name.
class NamesWheel extends StatefulWidget {
  const NamesWheel({
    required this.names,
    required this.arabicLabels,
    required this.onChanged,
    required this.onSettled,
    required this.onTick,
    required this.semanticLabel,
    required this.nextLabel,
    required this.centre,
    super.key,
  });

  final List<DivineName> names;

  /// Arabic labels run the other way round, as the script does.
  final bool arabicLabels;

  /// Another name came under the needle.
  final ValueChanged<int> onChanged;

  /// The needle stopped on a name.
  final ValueChanged<int> onSettled;

  /// A name passed the needle: the click and the haptic.
  final VoidCallback onTick;
  final String semanticLabel;
  final String nextLabel;

  /// What the centre shows; taps go through it to the wheel.
  final Widget centre;

  @override
  State<NamesWheel> createState() => NamesWheelState();
}

class NamesWheelState extends State<NamesWheel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<double>(0);
  final _labels = _LabelCache();

  var _motion = _Motion.idle;
  var _velocity = 0.0; // names per millisecond
  var _target = 0;
  var _index = 0;
  Duration? _lastFrame;

  // The drag in progress.
  var _dragInCore = false;
  var _travelled = 0.0;
  var _lastAngle = 0.0;
  Offset _down = Offset.zero;
  final _samples = <({Duration time, double position})>[];

  double get _position => _repaint.value;
  set _position(double value) => _repaint.value = value;

  int get _count => widget.names.length;

  /// The name under the needle.
  int get index => _index;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_frame);
  }

  @override
  void didUpdateWidget(NamesWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arabicLabels != widget.arabicLabels ||
        !identical(oldWidget.names, widget.names)) {
      _labels.clear();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _labels.clear();
    super.dispose();
  }

  bool get _reducedMotion => MediaQuery.disableAnimationsOf(context);

  void _moved() {
    final index = wheelIndex(_position, _count);
    if (index == _index) return;
    _index = index;
    widget.onTick();
    widget.onChanged(index);
  }

  void _frame(Duration elapsed) {
    final last = _lastFrame ?? elapsed;
    _lastFrame = elapsed;
    final dt = math.min(40, (elapsed - last).inMicroseconds / 1000);
    switch (_motion) {
      case _Motion.inertia:
        _position += _velocity * dt;
        _velocity *= math.exp(-dt / 450);
        if (_velocity.abs() < 0.0035) {
          _motion = _Motion.snap;
          _target = _position.round();
        }
      case _Motion.snap:
        _position += (_target - _position) * (1 - math.exp(-dt / 70));
        if ((_target - _position).abs() < 0.003) {
          _position = _target.toDouble();
          _stop();
          _moved();
          widget.onSettled(_index);
          return;
        }
      case _Motion.idle || _Motion.drag:
        _stop();
        return;
    }
    _moved();
  }

  void _start(_Motion motion) {
    _motion = motion;
    _lastFrame = null;
    if (!_ticker.isActive) _ticker.start();
  }

  void _stop() {
    _motion = _Motion.idle;
    _lastFrame = null;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Turns the wheel to a name the short way round.
  void goTo(int index) {
    _target = wheelTarget(_position, index, _count);
    if (_reducedMotion) {
      _stop();
      _position = _target.toDouble();
      _moved();
      widget.onSettled(_index);
      return;
    }
    _start(_Motion.snap);
  }

  void next() => goTo(_position.round() + 1);

  void previous() => goTo(_position.round() - 1);

  // Gestures --------------------------------------------------------------

  Offset _local(PointerEvent event, double size) =>
      event.localPosition - Offset(size / 2, size / 2);

  void _onDown(PointerDownEvent event, double size) {
    final point = _local(event, size);
    _stop();
    _motion = _Motion.drag;
    _velocity = 0;
    _dragInCore = point.distance <= size * .16;
    _travelled = 0;
    _down = event.position;
    _lastAngle = point.direction;
    _samples
      ..clear()
      ..add((time: event.timeStamp, position: _position));
  }

  void _onMove(PointerMoveEvent event, double size) {
    if (_motion != _Motion.drag) return;
    final point = _local(event, size);
    _travelled = math.max(_travelled, (event.position - _down).distance);
    if (point.distance < 12) return;
    final angle = point.direction;
    var delta = angle - _lastAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastAngle = angle;
    if (_travelled < 6 && _dragInCore) return;
    _position +=
        (widget.arabicLabels ? -1 : 1) * delta / (2 * math.pi / _count);
    _samples.add((time: event.timeStamp, position: _position));
    while (_samples.length > 2 &&
        event.timeStamp - _samples.first.time >
            const Duration(milliseconds: 90)) {
      _samples.removeAt(0);
    }
    _moved();
  }

  void _onUp(PointerEvent event) {
    if (_motion != _Motion.drag) return;
    // A tap on the centre: the next name.
    if (_dragInCore && _travelled < 8) {
      _motion = _Motion.idle;
      next();
      return;
    }
    final first = _samples.first;
    final last = _samples.last;
    final span = (last.time - first.time).inMicroseconds / 1000;
    var velocity = span > 0 ? (last.position - first.position) / span : 0.0;
    if (event.timeStamp - last.time > const Duration(milliseconds: 80)) {
      velocity = 0;
    }
    _velocity = velocity.clamp(-.09, .09);
    if (_reducedMotion || _velocity.abs() < .004) {
      _target = _position.round();
      _start(_Motion.snap);
    } else {
      _start(_Motion.inertia);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NamesWheelColors.of(context);
    final direction = Directionality.of(context);
    final name = widget.names[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Semantics(
          container: true,
          slider: true,
          label: widget.semanticLabel,
          value: '${name.label}, ${name.meaning}',
          increasedValue: widget.names[(_index + 1) % _count].label,
          decreasedValue: widget.names[(_index - 1 + _count) % _count].label,
          onTapHint: widget.nextLabel,
          onIncrease: next,
          onDecrease: previous,
          onTap: next,
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: size,
              // The wheel takes the touch at once, so a page that scrolls
              // under it does not move while the wheel turns.
              child: RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(EagerGestureRecognizer.new, (_) {}),
                },
                child: Listener(
                  key: const ValueKey('names-dial'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _onDown(event, size),
                  onPointerMove: (event) => _onMove(event, size),
                  onPointerUp: _onUp,
                  onPointerCancel: _onUp,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _WheelPainter(
                              position: _repaint,
                              names: widget.names,
                              arabic: widget.arabicLabels,
                              colors: colors,
                              labels: _labels,
                              textDirection: direction,
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.fontFamily,
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Container(
                          width: size * .32,
                          height: size * .32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.face,
                            border: Border.all(
                              color: colors.gold.withValues(alpha: .6),
                            ),
                          ),
                          child: widget.centre,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Laid-out labels at their base size: only the few names near the needle
/// change size while the wheel turns.
class _LabelCache {
  final _painters = <int, TextPainter>{};
  Object? _key;

  TextPainter base(int index, Object key, TextPainter Function() build) {
    if (key != _key) {
      clear();
      _key = key;
    }
    return _painters.putIfAbsent(index, build);
  }

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.position,
    required this.names,
    required this.arabic,
    required this.colors,
    required this.labels,
    required this.textDirection,
    required this.fontFamily,
  }) : super(repaint: position);

  final ValueListenable<double> position;
  final List<DivineName> names;
  final bool arabic;
  final NamesWheelColors colors;
  final _LabelCache labels;
  final TextDirection textDirection;
  final String? fontFamily;

  static const _tau = 2 * math.pi;

  TextPainter _text(String text, double size, FontWeight weight, Color color) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: arabic ? IqroTheme.arabicFontFamily : fontFamily,
            fontSize: size,
            fontWeight: weight,
            color: color,
            height: arabic ? 1.4 : 1.1,
          ),
        ),
        // Labels are placed by hand; Arabic still shapes right to left.
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final total = names.length;
    final side = size.shortestSide;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = side / 2 - 3;
    final step = _tau / total;
    final direction = arabic ? -1 : 1;
    double angleOf(num index) => -math.pi / 2 + direction * index * step;
    final at = position.value;
    final coreRadius = side * .16;

    // The face.
    final face = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.3),
          colors: <Color>[colors.face, colors.faceEdge],
        ).createShader(face),
    );
    final stroke = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      centre,
      radius - 2.5,
      stroke
        ..strokeWidth = 5
        ..color = colors.rim,
    );
    canvas.drawCircle(
      centre,
      radius - 6,
      stroke
        ..strokeWidth = 1
        ..color = colors.gold.withValues(alpha: .55),
    );

    final tickRadius = radius - 9;
    final outer = radius - 19;
    final inner = radius * .43;
    canvas.drawCircle(centre, inner - 8, stroke..color = colors.line);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    // A tick for every name, a longer one every 11, a gold one every 33: the
    // marks of a tasbih.
    for (var index = 0; index < total; index++) {
      final major = index % 33 == 0;
      final middle = index % 11 == 0;
      final length = major ? 9.0 : (middle ? 6.0 : 3.0);
      final angle = angleOf(index);
      final unit = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        unit * (tickRadius - length),
        unit * tickRadius,
        Paint()
          ..strokeWidth = major ? 1.6 : 1
          ..color = (major ? colors.gold : colors.muted).withValues(
            alpha: major ? .95 : (middle ? .7 : .4),
          ),
      );
    }

    final wrapped = ((at % total) + total) % total;
    final near = wheelIndex(at, total);
    final baseSize = math.max(6.5, side * .0205) * (arabic ? 1.5 : 1);
    final span = outer - inner;
    final cacheKey = Object.hash(side, arabic, colors, fontFamily);

    String labelOf(int index) =>
        arabic ? stripHarakat(names[index].arabic) : names[index].label;

    // Latin and Cyrillic labels start at the inner radius; Arabic ones are
    // short and end at the rim. Returns where the label begins.
    double label(int index, {bool measureOnly = false}) {
      var distance = (index - wrapped).abs();
      distance = math.min(distance, total - distance);
      final zoom = math.exp(-(distance * distance) / .6);
      final selected = index == near;
      final TextPainter painter;
      final ownPainter = selected || zoom >= .01;
      if (ownPainter) {
        painter = _text(
          labelOf(index),
          baseSize * (1 + zoom),
          selected
              ? FontWeight.w600
              : (zoom > .3 ? FontWeight.w500 : FontWeight.w400),
          selected
              ? colors.onAccent
              : (zoom > .08 ? colors.text : colors.muted).withValues(
                  alpha: .6 + .4 * zoom,
                ),
        );
      } else {
        painter = labels.base(
          index,
          cacheKey,
          () => _text(
            labelOf(index),
            baseSize,
            FontWeight.w400,
            colors.muted.withValues(alpha: .6),
          ),
        );
      }
      final limit = selected ? span - 4 : span;
      final scale = painter.width > limit ? limit / painter.width : 1.0;
      final width = painter.width * scale;
      final height = painter.height * scale;
      final pad = math.max(4.0, height * .3);
      final start = arabic ? outer - width : inner;
      if (!measureOnly) {
        final angle = angleOf(index);
        canvas.save();
        canvas.rotate(angle);
        final leftHalf = math.cos(angle) < -1e-6;
        if (leftHalf) canvas.rotate(math.pi);
        final x = leftHalf ? -(start + width) : start;
        if (selected) {
          final pill = height * 1.15;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x - pad, -pill / 2, width + pad * 2, pill),
              Radius.circular(pill / 2),
            ),
            Paint()..color = colors.accent,
          );
        }
        canvas.translate(x, -height / 2);
        canvas.scale(scale);
        painter.paint(canvas, Offset.zero);
        canvas.restore();
      }
      if (ownPainter) painter.dispose();
      return start - pad;
    }

    for (var index = 0; index < total; index++) {
      if (index != near) label(index);
    }

    // The needle goes under the chosen label, so the label stays on top.
    canvas.save();
    canvas.rotate(-math.pi / 2 + direction * at * step);
    final from = coreRadius + 8;
    final to = arabic
        ? math.max(inner - 12, label(near, measureOnly: true) - 9)
        : inner - 12;
    final needle = Paint()
      ..color = colors.gold
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(from, 0), Offset(to, 0), needle);
    canvas.drawPath(
      Path()
        ..moveTo(to + 5, 0)
        ..lineTo(to - 2, -3.2)
        ..lineTo(to - 2, 3.2)
        ..close(),
      Paint()..color = colors.gold,
    );
    canvas.drawCircle(Offset(from, 0), 3.2, Paint()..color = colors.face);
    canvas.drawCircle(
      Offset(from, 0),
      3.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colors.gold,
    );
    // The mark on the rim.
    canvas.drawLine(
      Offset(tickRadius - 12, 0),
      Offset(radius - 4, 0),
      needle..strokeWidth = 2.5,
    );
    canvas.restore();

    label(near);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      !identical(oldDelegate.names, names) ||
      oldDelegate.arabic != arabic ||
      oldDelegate.colors != colors ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.fontFamily != fontFamily;
}
