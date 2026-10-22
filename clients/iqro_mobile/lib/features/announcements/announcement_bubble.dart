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

const announcementBubbleSize = 52.0;
const _popDuration = Duration(milliseconds: 380);
const _openAfter = Duration(milliseconds: 320);

// Where the six drops fly when the bubble pops, as on the site.
const _drops = <(Offset, Color)>[
  (Offset(-30, -22), Color(0xFF91D7C3)),
  (Offset(30, -24), Color(0xFF91D7C3)),
  (Offset(-34, 16), Color(0xFF91D7C3)),
  (Offset(32, 20), Color(0xFF91D7C3)),
  (Offset(0, -36), Color(0xFFF3D7A1)),
  (Offset(-4, 34), Color(0xFFC4B5FD)),
];

/// The live bubble in the top corner of the home screen. A tap pops it and
/// opens the window; it comes back by the admin's frequency until read.
class AnnouncementBubble extends ConsumerStatefulWidget {
  const AnnouncementBubble({super.key});

  @override
  ConsumerState<AnnouncementBubble> createState() => _AnnouncementBubbleState();
}

class _AnnouncementBubbleState extends ConsumerState<AnnouncementBubble>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _float;
  late final AnimationController _spin;
  late final AnimationController _pop;
  String? _locale;
  var _popping = false;
  var _moving = false;
  Timer? _openTimer;

  AnnouncementsController get _controller =>
      ref.read(announcementsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
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
    _float.dispose();
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _setMoving(bool moving) {
    if (moving == _moving) return;
    _moving = moving;
    if (moving) {
      _float.repeat();
      _spin.repeat();
    } else {
      _float.stop();
      _spin.stop();
    }
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
    await showAnnouncementDialog(context, items: items, surface: 'bubble');
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
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Home may sit under another tab or screen: then the bubble is not seen,
    // neither counted nor moving.
    final onScreen =
        Visibility.of(context) && TickerMode.valuesOf(context).enabled;
    final visible = items.isNotEmpty && !_popping && onScreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setMoving(visible && !reduced);
      if (visible) _controller.recordShown(items);
    });
    if (items.isEmpty && !_popping) return const SizedBox.shrink();

    final first = items.isEmpty ? null : items.first;
    final onTap = first == null || _popping
        ? null
        : () => unawaited(_open(items));
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Semantics(
        button: true,
        label: context.l10n.newsBubble(items.length),
        onTap: onTap,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: announcementBubbleSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              if (_popping && !reduced) _Burst(animation: _pop),
              AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_float, _pop]),
                builder: (context, child) {
                  // The site's bob: up 4 px and 4 % larger at the middle.
                  final phase = (1 - math.cos(_float.value * 2 * math.pi)) / 2;
                  final pop = _pop.value;
                  final popScale = pop < .45
                      ? 1 + .3 * (pop / .45)
                      : 1.3 + .4 * ((pop - .45) / .55);
                  final popOpacity = pop < .45
                      ? 1 - .15 * (pop / .45)
                      : .85 * (1 - (pop - .45) / .55);
                  return Opacity(
                    opacity: _popping
                        ? (reduced ? 0 : popOpacity.clamp(0, 1))
                        : 1,
                    child: Transform.translate(
                      offset: Offset(0, -4 * phase),
                      child: Transform.scale(
                        scale: (1 + .04 * phase) * (_popping ? popScale : 1),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('announcement-bubble'),
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: _BubbleBody(spin: _spin, first: first),
                  ),
                ),
              ),
              if (items.length > 1 && !_popping)
                PositionedDirectional(
                  top: -3,
                  end: -3,
                  child: _Count(count: items.length),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.spin, required this.first});

  final Animation<double> spin;
  final Announcement? first;

  @override
  Widget build(BuildContext context) {
    final item = first;
    final portrait = item != null && item.bubbleIcon == 'portrait'
        ? item.image?.thumbUrl ?? item.image?.url
        : null;
    final icon = Icon(
      announcementIcon(item?.bubbleIcon ?? 'megaphone'),
      size: 20,
      color: announcementFaceInk,
    );
    return SizedBox.square(
      dimension: announcementBubbleSize,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // The film: a soft shine and a tinted edge.
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
              boxShadow: const <BoxShadow>[
                // Smaller than the site's: the top bar ends 6 px below.
                BoxShadow(
                  color: Color(0x2E073E34),
                  blurRadius: 8,
                  offset: Offset(0, 3),
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
            width: 34,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: announcementFaceGradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: .8),
                width: 1.5,
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

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = const SweepGradient(
        colors: <Color>[
          Color(0xE691D7C3),
          Color(0xE6F3D7A1),
          Color(0xE6C4B5FD),
          Color(0xE67DD3FC),
          Color(0xE691D7C3),
        ],
      ).createShader(rect);
    canvas.drawCircle(rect.center, size.width / 2 - 1.25, paint);
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
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 4),
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
            fontSize: 11,
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
                        color: const Color(0xF291D7C3),
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
                        width: 6,
                        height: 6,
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
