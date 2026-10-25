import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/public_asset_uri.dart';
import 'course_models.dart';

const _approvedMediaHosts = <String>{'media.iqro.forum'};

/// The larger copy is taken only when the small one would be scaled up.
const _smallImagePixels = 800;

/// The side gutters of the lesson page around a media frame.
const _pageGutters = 32.0;

/// Slide and banner pictures, kept for reading offline as long as the course
/// documents are; the files never change under one address.
final lessonMediaCacheManagerProvider = Provider<BaseCacheManager>(
  (ref) => lessonMediaCache,
);

/// The cache itself, for what is built before the providers (the prayer
/// course's repository).
final lessonMediaCache = CacheManager(
  Config(
    'iqroLessonMedia',
    stalePeriod: const Duration(days: 180),
    maxNrOfCacheObjects: 2000,
  ),
);

/// Draws a slide or a banner; tests put in-memory images in.
final lessonMediaImageProvider = Provider<ImageProvider Function(String url)>((
  ref,
) {
  final cache = ref.watch(lessonMediaCacheManagerProvider);
  return (url) => CachedNetworkImageProvider(url, cacheManager: cache);
});

/// The media that can be shown: a picture from another host leaves its
/// whole block out, as on the site. The video player checks its own address.
List<LessonMedia> approvedLessonMedia(
  Iterable<LessonMedia> media,
  Uri apiBase,
) {
  bool approved(LessonImage image) => [image.url, image.smallUrl].every(
    (url) => isApprovedPublicAssetUri(
      apiBase.resolve(url),
      allowedHosts: _approvedMediaHosts,
      localApiBase: apiBase,
    ),
  );
  return [
    for (final block in media)
      if (switch (block) {
        LessonVideoMedia() => true,
        LessonSlidesMedia(:final slides) => slides.every(
          (slide) => approved(slide.image),
        ),
        LessonBannerMedia(:final picture) => approved(picture.image),
      })
        block,
  ];
}

/// The copy for a frame [framePixels] device pixels wide.
String lessonImageUrl(LessonImage image, double framePixels) =>
    framePixels <= _smallImagePixels ? image.smallUrl : image.url;

/// The copy [lessonImageUrl] picks for the other size, when the chosen one
/// is not at hand.
String lessonImageOtherUrl(LessonImage image, double framePixels) =>
    framePixels <= _smallImagePixels ? image.url : image.smallUrl;

/// The width in device pixels of a media frame on this device held upright:
/// the copy the lesson shows, so the same one is kept for offline.
double lessonMediaFramePixels() {
  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return _smallImagePixels.toDouble();
  final ratio = view.devicePixelRatio;
  final width = view.physicalSize.shortestSide / ratio - _pageGutters;
  return width * ratio;
}

/// Keeps the slide and banner pictures of a course in the image cache with
/// its document, so the lessons show them offline. A picture that does not
/// arrive is left for the next time; it never fails the course.
class LessonMediaPrefetcher {
  LessonMediaPrefetcher({
    required BaseCacheManager cache,
    required Uri apiBase,
    double Function() framePixels = lessonMediaFramePixels,
  }) : _cache = cache,
       _apiBase = apiBase,
       _framePixels = framePixels;

  final BaseCacheManager _cache;
  final Uri _apiBase;
  final double Function() _framePixels;

  /// The addresses [keep] fetches: those the lessons show on this device.
  List<String> urls(Iterable<LessonMedia> media) {
    final pixels = _framePixels();
    return <String>{
      for (final block in approvedLessonMedia(media, _apiBase))
        ...switch (block) {
          LessonVideoMedia() => const <LessonImage>[],
          LessonSlidesMedia(:final slides) => [
            for (final slide in slides) slide.image,
          ],
          LessonBannerMedia(:final picture) => [picture.image],
        }.map(
          (image) => _apiBase.resolve(lessonImageUrl(image, pixels)).toString(),
        ),
    }.toList();
  }

  /// One after another; a picture already kept is not fetched again.
  Future<void> keep(Iterable<LessonMedia> media) async {
    for (final url in urls(media)) {
      try {
        if (await _cache.getFileFromCache(url) != null) continue;
        await _cache.downloadFile(url);
      } on Object {
        // Offline or a failed file: the lesson loads it when shown.
      }
    }
  }
}
