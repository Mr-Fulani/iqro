import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Static polished frame only. The canonical/admin portrait URL is untouched;
/// no colour filter or highlight is painted over the person's photograph.
class PremiumReciterPortrait extends StatelessWidget {
  const PremiumReciterPortrait({
    super.key,
    required this.url,
    required this.size,
    this.initials,
    this.selected = false,
  });

  final String? url;
  final double size;
  final String? initials;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final inset = size >= 150 ? 7.0 : 3.0;
    final pixels = ((size - inset * 2) * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    final fallback = ColoredBox(
      color: const Color(0xFF163C33),
      child: Center(
        child: initials == null
            ? Icon(
                Icons.person_rounded,
                size: size * .48,
                color: const Color(0xFFB6E8D9),
              )
            : Padding(
                padding: const EdgeInsets.all(5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    initials!,
                    style: TextStyle(
                      color: const Color(0xFFF5EAD5),
                      fontSize: size * .24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
      ),
    );
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(inset),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? const [
                    Color(0xFFFFE6AE),
                    Color(0xFFAC7936),
                    Color(0xFFFFF2CF),
                    Color(0xFFBA8D47),
                  ]
                : const [
                    Color(0xFFE8DCC4),
                    Color(0xFF9A8A70),
                    Color(0xFFFFF8E9),
                    Color(0xFF9F8E72),
                  ],
            stops: const [0, .4, .65, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipOval(
          child: url == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  memCacheWidth: pixels,
                  memCacheHeight: pixels,
                  placeholder: (context, url) => fallback,
                  errorWidget: (context, url, error) => fallback,
                ),
        ),
      ),
    );
  }
}
