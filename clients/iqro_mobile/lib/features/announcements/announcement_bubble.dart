import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'announcement_controller.dart';
import 'announcement_dialog.dart';
import 'announcement_logic.dart';
import 'announcement_parts.dart';

// Sizes and motion agreed with the site's phone bubble.
const announcementBubbleSize = 68.0;
const _faceSize = 46.0;
const _popDuration = Duration(milliseconds: 380);
const _openAfter = Duration(milliseconds: 320);
// Rising in (600 ms), then two larger bobs (1.6 s), then the drift.
const _introDuration = Duration(milliseconds: 2200);
// Every period of the drift divides this, so the path closes without a jump.
const _driftSeconds = 144.0;
// Clear of the screen's edges and the bars, with room for the badge.
const _edge = 12.0;
const _riseShare = 600 / 2200;
const _rise = Cubic(.34, 1.56, .64, 1);

// Where the six drops fly when the bubble pops.
const _drops = <(Offset, Color)>[
  (Offset(-39, -29), Color(0xFF34D399)),
  (Offset(39, -31), Color(0xFF34D399)),
  (Offset(-44, 21), Color(0xFF38BDF8)),
  (Offset(42, 26), Color(0xFF34D399)),
  (Offset(0, -47), Color(0xFFFBBF24)),
  (Offset(-5, 44), Color(0xFFA78BFA)),
];

/// Lets the bubble float over the home screen, between the top bar and the
/// bottom navigation, above the page and below windows; it takes no room in
/// the layout.
class AnnouncementBubbleLayer extends StatelessWidget {
  const AnnouncementBubbleLayer({
    required this.child,
    this.topBarHeight = 64,
    super.key,
  });

  /// The home screen with its top bar.
  final Widget child;

  /// Height of [child]'s top bar below the status bar.
  final double topBarHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The bottom inset includes the navigation the page extends
              // under.
              final padding = MediaQuery.paddingOf(context);
              const half = announcementBubbleSize / 2;
              final left = padding.left + _edge + half;
              final top = padding.top + topBarHeight + _edge + half;
              final right = math.max(
                left,
                constraints.maxWidth - padding.right - _edge - half,
              );
              final bottom = math.max(
                top,
                constraints.maxHeight - padding.bottom - _edge - half,
              );
              return Stack(
                children: <Widget>[
                  AnnouncementBubble(
                    zone: Rect.fromLTRB(left, top, right, bottom),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The live bubble drifting over the home screen like a soap bubble in the
/// air. A tap pops it and opens the window; it comes back by the admin's
/// frequency until read.
class AnnouncementBubble extends ConsumerStatefulWidget {
  const AnnouncementBubble({required this.zone, super.key});

  /// Where the bubble's centre may go, in the layer's coordinates.
  final Rect zone;

  @override
  ConsumerState<AnnouncementBubble> createState() => _AnnouncementBubbleState();
}

class _AnnouncementBubbleState extends ConsumerState<AnnouncementBubble>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro;
  late final AnimationController _drift;
  late final AnimationController _spin;
  late final AnimationController _pop;
  String? _locale;
  var _popping = false;
  var _moving = false;
  // Focused from the keyboard or a screen reader: it holds still.
  var _held = false;
  DateTime? _introducedFor;
  Timer? _openTimer;

  AnnouncementsController get _controller =>
      ref.read(announcementsProvider.notifier);

  @override
  void initState() {
    super.initState();
    // At rest until a visit plays the rise.
    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..value = 1
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _moving && !_held) {
          _drift.repeat();
        }
      });
    _drift = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_driftSeconds * 1000).round()),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _pop = AnimationController(vsync: this, duration: _popDuration);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == _locale) return;
    _locale = locale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.load(locale));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final locale = _locale;
    if (state == AppLifecycleState.paused) {
      _controller.left();
    } else if (state == AppLifecycleState.resumed &&
        _controller.returned() &&
        locale != null) {
      unawaited(_controller.load(locale, refresh: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openTimer?.cancel();
    _intro.dispose();
    _drift.dispose();
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  /// The first sight of a visit rises in at the top end and bobs twice, then
  /// drifts; still it stays where it is.
  void _setMoving(bool moving, DateTime visit) {
    _moving = moving;
    if (!moving) {
      _intro
        ..stop()
        ..value = 1;
      _drift.stop();
      _spin.stop();
      return;
    }
    if (!_spin.isAnimating) _spin.repeat();
    if (_introducedFor != visit) {
      _introducedFor = visit;
      _drift
        ..stop()
        ..value = 0;
      _intro.forward(from: 0);
    } else if (!_intro.isAnimating && !_drift.isAnimating && !_held) {
      _drift.repeat();
    }
  }

  void _hold(bool held) {
    if (held == _held) return;
    _held = held;
    if (held) {
      _drift.stop();
    } else if (_moving && !_intro.isAnimating) {
      _drift.repeat();
    }
  }

  /// The drift: two waves across and two down, slow and never repeating
  /// within a visit's glance. It starts at the top end of the zone and keeps
  /// to its upper half, clear of the player and the bottom buttons.
  Offset _position() {
    final seconds = _drift.value * _driftSeconds;
    double wave(double period) => math.cos(2 * math.pi * seconds / period);
    final across = .65 + .35 * (.6 * wave(16) + .4 * wave(9));
    final down = .25 * (1 - (.6 * wave(12) + .4 * wave(14.4)));
    final zone = widget.zone;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Offset(
      rtl ? zone.right - across * zone.width : zone.left + across * zone.width,
      zone.top + down * zone.height,
    );
  }

  Future<void> _open(List<Announcement> items) async {
    if (_popping) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() => _popping = true);
    if (!reduced) {
      unawaited(_pop.forward(from: 0));
      final opened = Completer<void>();
      _openTimer = Timer(_openAfter, opened.complete);
      await opened.future;
      if (!mounted) return;
    }
    final box = context.findRenderObject() as RenderBox?;
    await showAnnouncementDialog(
      context,
      items: items,
      surface: 'bubble',
      origin: box != null && box.hasSize
          ? box.localToGlobal(box.size.center(Offset.zero))
          : null,
    );
    if (!mounted) return;
    _pop.reset();
    setState(() => _popping = false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = announcementSignedIn(
      ref.watch(sessionProvider.select((value) => value.valueOrNull)),
    );
    ref.listen(sessionProvider.select((value) => value.valueOrNull?.userId), (
      previous,
      next,
    ) {
      if (next != null && next != previous) {
        unawaited(_controller.syncReceipts());
      }
    });
    final items = ref.watch(
      announcementsProvider.select((value) => value.bubble(signedIn: signedIn)),
    );
    final visit = ref.watch(
      announcementsProvider.select((value) => value.openedAt),
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Home may sit under another tab or screen: then the bubble is not seen,
    // neither counted nor moving.
    final onScreen =
        Visibility.of(context) && TickerMode.valuesOf(context).enabled;
    final visible = items.isNotEmpty && !_popping && onScreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setMoving(visible && !reduced, visit);
      if (visible) _controller.recordShown(items);
    });
    if (items.isEmpty && !_popping) return const SizedBox.shrink();

    final first = items.isEmpty ? null : items.first;
    final onTap = first == null || _popping
        ? null
        : () => unawaited(_open(items));
    final core = Semantics(
      button: true,
      label: context.l10n.newsBubble(items.length),
      onTap: onTap,
      onDidGainAccessibilityFocus: () => _hold(true),
      onDidLoseAccessibilityFocus: () => _hold(false),
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('announcement-bubble'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              onFocusChange: _hold,
              child: _BubbleBody(spin: _spin, first: first),
            ),
          ),
          if (items.length > 1 && !_popping)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: _Count(count: items.length),
            ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_intro, _drift, _pop]),
      child: core,
      builder: (context, core) {
        final at = _position();
        final motion = _motion();
        final pop = _pop.value;
        final popScale = pop < .45
            ? 1 + .3 * (pop / .45)
            : 1.3 + .4 * ((pop - .45) / .55);
        final popOpacity = pop < .45
            ? 1 - .15 * (pop / .45)
            : .85 * (1 - (pop - .45) / .55);
        return Positioned(
          left: at.dx - announcementBubbleSize / 2,
          top: at.dy - announcementBubbleSize / 2,
          width: announcementBubbleSize,
          height: announcementBubbleSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              if (_popping && !reduced) _Burst(animation: _pop),
              Opacity(
                opacity: _popping
                    ? (reduced ? 0 : popOpacity.clamp(0, 1))
                    : motion.opacity,
                child: Transform.translate(
                  offset: Offset(0, motion.dy),
                  child: Transform.scale(
                    scale: motion.scale * (_popping ? popScale : 1),
                    child: core,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ({double scale, double dy, double opacity}) _motion() {
    var scale = 1.0;
    var dy = 0.0;
    var opacity = 1.0;
    final intro = _intro.value;
    if (intro < _riseShare) {
      final progress = intro / _riseShare;
      final rise = _rise.transform(progress);
      scale = .4 + .6 * rise;
      dy = 12 * (1 - rise);
      opacity = (progress / .4).clamp(0, 1);
    } else {
      // Two full bobs, up 8 px and 8 % larger at their tops.
      final progress = (intro - _riseShare) / (1 - _riseShare);
      final phase = (1 - math.cos(progress * 4 * math.pi)) / 2;
      scale = 1 + .08 * phase;
      dy = -8 * phase;
    }
    // Breathing while it drifts: 4 % larger every 3.6 s.
    final seconds = _drift.value * _driftSeconds;
    final phase = (1 - math.cos(2 * math.pi * seconds / 3.6)) / 2;
    return (scale: scale * (1 + .04 * phase), dy: dy, opacity: opacity);
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.spin, required this.first});

  final Animation<double> spin;
  final Announcement? first;

  @override
  Widget build(BuildContext context) {
    final item = first;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final portrait = item != null && item.bubbleIcon == 'portrait'
        ? item.image?.thumbUrl ?? item.image?.url
        : null;
    final icon = Icon(
      announcementIcon(item?.bubbleIcon ?? 'megaphone'),
      size: 26,
      color: announcementFaceInk,
    );
    return SizedBox.square(
      dimension: announcementBubbleSize,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // The film: a soft shine, a tinted edge and an emerald glow.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .85),
                width: 1,
              ),
              gradient: const RadialGradient(
                colors: <Color>[
                  Color(0x1FFFFFFF),
                  Color(0x1FFFFFFF),
                  Color(0x8091D7C3),
                  Color(0x59C49647),
                ],
                stops: <double>[0, .52, .78, 1],
                // The site's circle reaches the corners of the box.
                radius: .7071,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: dark
                      ? const Color(0x9934D399)
                      : const Color(0x5934D399),
                  blurRadius: dark ? 14 : 10,
                ),
                const BoxShadow(
                  color: Color(0x33073E34),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const SizedBox.expand(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-.38, -.5),
                radius: 1,
                colors: <Color>[
                  Color(0xF2FFFFFF),
                  Color(0xF2FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: <double>[0, .07, .17],
              ),
            ),
            child: SizedBox.expand(),
          ),
          // The rainbow rim turns slowly, like light on a soap film.
          RotationTransition(
            turns: spin,
            child: const CustomPaint(
              size: Size.square(announcementBubbleSize),
              painter: _RimPainter(),
            ),
          ),
          Container(
            width: _faceSize,
            height: _faceSize,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: announcementFaceGradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: .9),
                width: 2,
              ),
            ),
            child: portrait == null
                ? icon
                : AnnouncementNetworkImage(url: portrait, fallback: icon),
          ),
        ],
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  const _RimPainter();

  static const _width = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..shader = const SweepGradient(
        colors: <Color>[
          Color(0xFF34D399),
          Color(0xFFFBBF24),
          Color(0xFFA78BFA),
          Color(0xFF38BDF8),
          Color(0xFF34D399),
        ],
      ).createShader(rect);
    canvas.drawCircle(rect.center, size.width / 2 - _width / 2, paint);
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) => false;
}

class _Count extends StatelessWidget {
  const _Count({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.iqroColors.gold,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 2,
          ),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// The ring and drops of a popped bubble.
class _Burst extends StatelessWidget {
  const _Burst({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeOut.transform(animation.value);
          final ring = (animation.value * 380 / 340).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Opacity(
                opacity: 1 - Curves.easeOut.transform(ring),
                child: Transform.scale(
                  scale: 1 + 1.3 * Curves.easeOut.transform(ring),
                  child: Container(
                    width: announcementBubbleSize,
                    height: announcementBubbleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xF234D399),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              for (final (offset, color) in _drops)
                Transform.translate(
                  offset: Directionality.of(context) == TextDirection.rtl
                      ? Offset(-offset.dx, offset.dy) * t
                      : offset * t,
                  child: Opacity(
                    opacity: 1 - t,
                    child: Transform.scale(
                      scale: 1 - .6 * t,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
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
