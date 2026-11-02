import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The owner's figure for every reciter without a portrait. Bundled, so it
/// shows offline and before the network answers.
const defaultReciterPortraitAsset = 'assets/reciters/default.webp';

// The frame's width around the photograph.
double _frameInset(double size) => size >= 150 ? 7.0 : 3.0;

/// Shorter side of the backend's small portrait copy (audio/portrait_upload.py).
const _thumbnailPixels = 320;

// The small copy when it is sharp enough for [pixels], else the full portrait.
String? _portraitSource(String? url, String? thumbnailUrl, int pixels) =>
    url != null && thumbnailUrl != null && pixels <= _thumbnailPixels
    ? thumbnailUrl
    : url;

/// The decoded photograph a portrait of [size] shows, the default figure when
/// [url] is null. Precaching this exact image lets a screen open with faces.
ImageProvider reciterPortraitImage(
  String? url, {
  String? thumbnailUrl,
  required double size,
  required double devicePixelRatio,
}) {
  final pixels = ((size - _frameInset(size) * 2) * devicePixelRatio).ceil();
  final source = _portraitSource(url, thumbnailUrl, pixels);
  return ResizeImage.resizeIfNeeded(
    pixels,
    pixels,
    source == null
        ? const AssetImage(defaultReciterPortraitAsset)
        : CachedNetworkImageProvider(source),
  );
}

/// Static polished frame only. The canonical/admin portrait URL is untouched;
/// no colour filter or highlight is painted over the person's photograph.
class PremiumReciterPortrait extends StatelessWidget {
  const PremiumReciterPortrait({
    super.key,
    required this.url,
    required this.size,
    this.thumbnailUrl,
    this.selected = false,
  });

  final String? url;

  /// The small copy of [url], used where it is sharp enough.
  final String? thumbnailUrl;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final inset = _frameInset(size);
    final pixels = ((size - inset * 2) * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    final source = _portraitSource(url, thumbnailUrl, pixels);
    final fallback = Image(
      image: reciterPortraitImage(
        null,
        size: size,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      fit: BoxFit.cover,
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
          child: source == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: source,
                  fit: BoxFit.cover,
                  memCacheWidth: pixels,
                  memCacheHeight: pixels,
                  // A cached photo replaces the default figure at once; the
                  // default 1.5 s cross-fade looked like the screen hanging.
                  fadeOutDuration: Duration.zero,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (context, url) => fallback,
                  errorWidget: (context, url, error) => fallback,
                ),
        ),
      ),
    );
  }
}
