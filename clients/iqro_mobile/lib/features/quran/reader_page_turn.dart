import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Which way the finger moved across the text.
enum ReaderSwipeDirection { right, left }

/// What a swipe leads to, shown under the page while the finger pulls it.
class ReaderSwipeTarget {
  const ReaderSwipeTarget({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// A horizontal swipe across the Quran text. The page slides with the finger
/// and shows what lies that way; pulled far enough, or flicked, it calls
/// [onSwipe], else it slides back. A swipe that starts at the very edge is
/// the system's back gesture and is left alone, and so is everything while
/// [enabled] is false: a finger pulling word handles must not turn pages.
class ReaderSwipeArea extends StatefulWidget {
  const ReaderSwipeArea({
    required this.child,
    required this.onSwipe,
    this.right,
    this.left,
    this.enabled = true,
    this.background,
    this.hint,
    this.onHintEnd,
    super.key,
  });

  final Widget child;

  /// Under the page while it slides; the app's background by default.
  final Color? background;

  /// Where a swipe to the right and to the left lead; null: nowhere.
  final ReaderSwipeTarget? right;
  final ReaderSwipeTarget? left;
  final bool enabled;

  /// The direction, and where the finger first touched, in global terms.
  final void Function(ReaderSwipeDirection direction, Offset start) onSwipe;

  /// Once this caption is given, the page shows that it can be swiped: a
  /// hand pulls it a little to the right, then to the left, uncovering what
  /// lies each way, and [onHintEnd] follows. A touch ends it at once. With
  /// animations off the hand and the caption only stand for a while.
  final String? hint;
  final VoidCallback? onHintEnd;

  @override
  State<ReaderSwipeArea> createState() => _ReaderSwipeAreaState();
}

/// The strip along each side where a swipe belongs to the system.
const readerSwipeEdge = 24.0;

/// The swipe hint: to the right, a pause, back, to the left, a pause, back.
const readerSwipeHintDuration = Duration(milliseconds: 3600);

/// How long the still hint stands when animations are off.
const readerSwipeHintStill = Duration(seconds: 4);

/// The page's place through the hint, as a share of the pull: 1 is fully to
/// the right, -1 to the left.
final _hintPath = TweenSequence<double>(<TweenSequenceItem<double>>[
  TweenSequenceItem(tween: ConstantTween(0), weight: 3),
  TweenSequenceItem(
    tween: Tween<double>(
      begin: 0,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    weight: 6,
  ),
  TweenSequenceItem(tween: ConstantTween(1), weight: 5),
  TweenSequenceItem(
    tween: Tween<double>(
      begin: 1,
      end: 0,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    weight: 4,
  ),
  TweenSequenceItem(
    tween: Tween<double>(
      begin: 0,
      end: -1,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    weight: 6,
  ),
  TweenSequenceItem(tween: ConstantTween(-1), weight: 5),
  TweenSequenceItem(
    tween: Tween<double>(
      begin: -1,
      end: 0,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    weight: 4,
  ),
  TweenSequenceItem(tween: ConstantTween(0), weight: 3),
]);

class _ReaderSwipeAreaState extends State<ReaderSwipeArea>
    with TickerProviderStateMixin {
  late final _slide = AnimationController.unbounded(vsync: this);
  late final _hint = AnimationController(
    vsync: this,
    duration: readerSwipeHintDuration,
    // The hint is asked for only with animations on: it runs at full length.
    animationBehavior: AnimationBehavior.preserve,
  );
  Timer? _hintStill;
  var _hinting = false;
  Offset? _start;
  var _pulled = 0.0;

  @override
  void initState() {
    super.initState();
    _hint.addListener(() {
      if (!_hinting || !_hint.isAnimating) return;
      final width = context.size?.width ?? 0;
      // Far enough for the strip under the page to name where it leads.
      _slide.value = _hintPath.evaluate(_hint) * math.min(width * .36, 150);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.hint != null && !_hinting) _startHint();
  }

  @override
  void didUpdateWidget(ReaderSwipeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hint != null && oldWidget.hint == null) _startHint();
    if (widget.hint == null && _hinting) _stopHint();
  }

  @override
  void dispose() {
    _hintStill?.cancel();
    _hint.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _startHint() {
    if (_hinting) return;
    _hinting = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _hintStill = Timer(readerSwipeHintStill, _endHint);
      return;
    }
    unawaited(
      _hint.forward(from: 0).whenComplete(() {
        if (mounted && _hinting) _endHint();
      }),
    );
  }

  void _stopHint() {
    _hinting = false;
    _hintStill?.cancel();
    _hintStill = null;
    _hint.stop();
    if (_slide.value != 0 && _start == null) _slideBack();
  }

  void _endHint() {
    if (!_hinting) return;
    setState(_stopHint);
    widget.onHintEnd?.call();
  }

  bool _allows(Offset global) {
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    return global.dx > math.max(readerSwipeEdge, insets.left) &&
        global.dx < width - math.max(readerSwipeEdge, insets.right);
  }

  void _update(DragUpdateDetails details) {
    _pulled += details.delta.dx;
    if (widget.right == null) _pulled = math.min(0, _pulled);
    if (widget.left == null) _pulled = math.max(0, _pulled);
    // The page follows the finger, a little behind, and never far.
    final width = context.size?.width ?? 1;
    _slide.value = _pulled.sign * math.min(_pulled.abs() * .6, width * .4);
  }

  void _end(DragEndDetails details) {
    final start = _start;
    final offset = _slide.value;
    final width = context.size?.width ?? 1;
    final velocity = details.primaryVelocity ?? 0;
    final far = _pulled.abs() > width / 3;
    final flick = velocity.abs() > 800 && velocity.sign == offset.sign;
    _start = null;
    _pulled = 0;
    _slideBack();
    if (start == null || offset == 0 || !(far || flick)) return;
    widget.onSwipe(
      offset > 0 ? ReaderSwipeDirection.right : ReaderSwipeDirection.left,
      start,
    );
  }

  void _slideBack() => unawaited(
    _slide.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      // Any touch ends the hint, before the gesture is told apart.
      onPointerDown: (_) => _endHint(),
      child: _area(context, scheme),
    );
  }

  Widget _area(BuildContext context, ColorScheme scheme) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        if (widget.enabled)
          _ReaderSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<_ReaderSwipeRecognizer>(
                () => _ReaderSwipeRecognizer(_allows),
                (recognizer) => recognizer
                  ..onStart = (details) {
                    _slide.stop();
                    _start = details.globalPosition;
                    _pulled = _slide.value / .6;
                  }
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = () {
                    _start = null;
                    _pulled = 0;
                    _slideBack();
                  },
              ),
      },
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_slide, _hint]),
        child: widget.child,
        builder: (context, child) {
          final offset = _slide.value;
          final target = offset > 0
              ? widget.right
              : offset < 0
              ? widget.left
              : null;
          return Stack(
            children: <Widget>[
              if (target != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: scheme.primary,
                    child: Align(
                      alignment: offset > 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: SizedBox(
                        width: offset.abs(),
                        child: _SwipeTargetLabel(target: target),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(offset, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: offset == 0
                        ? null
                        : const <BoxShadow>[
                            BoxShadow(color: Color(0x47000000), blurRadius: 24),
                          ],
                  ),
                  child: ColoredBox(
                    color:
                        widget.background ??
                        Theme.of(context).scaffoldBackgroundColor,
                    child: child,
                  ),
                ),
              ),
              if (_hinting)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SwipeHint(
                      caption: widget.hint ?? '',
                      offset: offset,
                      shown: _hint.isAnimating
                          ? (math.min(_hint.value, 1 - _hint.value) * 14)
                                .clamp(0, 1)
                                .toDouble()
                          : 1,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A hand with its forefinger out, moving with the page it pulls, and under
/// it the words on what a swipe opens.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({
    required this.caption,
    required this.offset,
    required this.shown,
  });

  final String caption;
  final double offset;
  final double shown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A light hand with a dark outline in both themes: it lies on the text.
    final dark = scheme.brightness == Brightness.dark;
    return Opacity(
      opacity: shown,
      // Below the middle, where the strip under the page names its target.
      child: Align(
        alignment: const Alignment(0, .6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Transform.translate(
              // The finger leads the page a little, as a real one does.
              offset: Offset(offset * 1.15, 0),
              child: CustomPaint(
                key: const ValueKey('reader-swipe-hint-hand'),
                size: const Size(72, 84),
                painter: _SwipeHandPainter(
                  skin: dark ? scheme.onSurface : scheme.surface,
                  line: dark ? scheme.surface : scheme.onSurface,
                  touch: scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x33000000), blurRadius: 16),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      caption,
                      key: const ValueKey('reader-swipe-hint'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hand, drawn on a 48 by 56 grid: the same outline as the site's
/// (services/web/components/ReaderSwipe.tsx), with a ring where it touches.
class _SwipeHandPainter extends CustomPainter {
  const _SwipeHandPainter({
    required this.skin,
    required this.line,
    required this.touch,
  });

  final Color skin;
  final Color line;
  final Color touch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 56);
    const tip = Offset(21.5, 8);
    canvas
      ..drawCircle(tip, 7.5, Paint()..color = touch.withValues(alpha: .25))
      ..drawCircle(
        tip,
        7.5,
        Paint()
          ..color = touch
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    Radius round(double radius) => Radius.circular(radius);
    final hand = Path()
      ..moveTo(18, 7)
      ..relativeArcToPoint(const Offset(7, 0), radius: round(3.5))
      ..relativeLineTo(0, 14)
      ..relativeArcToPoint(const Offset(6.4, 0), radius: round(3.2))
      ..relativeLineTo(0, 2)
      ..relativeArcToPoint(const Offset(6, 0), radius: round(3))
      ..relativeLineTo(0, 2)
      ..relativeArcToPoint(const Offset(5.6, 0), radius: round(2.8))
      ..relativeLineTo(0, 12)
      ..relativeCubicTo(0, 9, -6, 15, -14, 15)
      ..relativeLineTo(-3, 0)
      ..relativeCubicTo(-5, 0, -8, -3, -11, -8)
      ..relativeLineTo(-7, -10)
      ..relativeCubicTo(-1.5, -2.5, 0, -5, 2.5, -5.5)
      ..relativeCubicTo(2, -.4, 3.5, .5, 5, 2)
      ..relativeLineTo(2.5, 2.5)
      ..close();
    canvas
      ..drawShadow(hand, const Color(0x66000000), 3, false)
      ..drawPath(hand, Paint()..color = skin)
      ..drawPath(
        hand,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_SwipeHandPainter old) =>
      old.skin != skin || old.line != line || old.touch != touch;
}

class _SwipeTargetLabel extends StatelessWidget {
  const _SwipeTargetLabel({required this.target});

  final ReaderSwipeTarget target;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    // The words come once the strip has room for them.
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(target.icon, color: color, size: 30),
              if (constraints.maxWidth >= 104) ...<Widget>[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    target.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _ReaderSwipeRecognizer(this.allows);

  final bool Function(Offset global) allows;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allows(event.position) && super.isPointerAllowed(event);
}

/// The side a turning page is fixed on.
enum ReaderPageHinge { left, right }

/// A page turning in over the one under it, fixed on one side as a Mushaf
/// page is, its free edge sweeping the way the finger went. Run backwards it
/// turns away again. Without animations it simply fades.
class ReaderPageTurn extends StatelessWidget {
  const ReaderPageTurn({
    required this.animation,
    required this.hinge,
    required this.child,
    super.key,
  });

  /// What a route pushed by a swipe carries, so its page turns in.
  static const routeExtra = 'reader-page-turn';

  final Animation<double> animation;
  final ReaderPageHinge hinge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final left = hinge == ReaderPageHinge.left;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final turned = Curves.easeOutCubic.transform(animation.value);
          if (turned >= 1) return child!;
          final angle = (1 - turned) * math.pi / 2 * (left ? 1 : -1);
          // The free edge comes up towards the reader; the depth keeps it
          // in front of the eye on a tablet too.
          final depth = .5 / math.max(constraints.maxWidth, 1);
          return Transform(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            transform: Matrix4.identity()
              ..setEntry(3, 2, depth)
              ..rotateY(angle),
            child: Stack(
              fit: StackFit.passthrough,
              children: <Widget>[
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: (1 - turned) * .3),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
