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

  @override
  State<ReaderSwipeArea> createState() => _ReaderSwipeAreaState();
}

/// The strip along each side where a swipe belongs to the system.
const readerSwipeEdge = 24.0;

class _ReaderSwipeAreaState extends State<ReaderSwipeArea>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController.unbounded(vsync: this);
  Offset? _start;
  var _pulled = 0.0;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
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
        animation: _slide,
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
            ],
          );
        },
      ),
    );
  }
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
