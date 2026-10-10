import 'package:flutter/material.dart';

/// The approved IQRO wax seal, revealed once within the app.
class IqroAnimatedLogo extends StatefulWidget {
  const IqroAnimatedLogo({super.key, this.size = 40});
  final double size;

  @override
  State<IqroAnimatedLogo> createState() => _IqroAnimatedLogoState();
}

class _IqroAnimatedLogoState extends State<IqroAnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Semantics(
      label: 'IQRO',
      image: true,
      child: FadeTransition(
        opacity: Tween<double>(begin: .25, end: 1).animate(_reveal),
        child: ScaleTransition(
          scale: Tween<double>(begin: .88, end: 1).animate(_reveal),
          child: Image.asset(
            'assets/brand/iqro-logo.png',
            width: widget.size,
            height: widget.size,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
