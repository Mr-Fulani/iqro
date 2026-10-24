import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iqro_mobile/features/courses/lesson_media_cache.dart';

/// The picture cache of lesson media without a disk or a network: tests
/// say which addresses it holds and which fail.
class FakeMediaCache implements BaseCacheManager {
  FakeMediaCache({Set<String>? cached, this.failing = const {}})
    : cached = cached ?? {};

  final Set<String> cached;
  final Set<String> failing;
  final downloads = <String>[];

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => cached.contains(key) ? _FakeFileInfo() : null;

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloads.add(url);
    if (failing.contains(url)) throw Exception('offline');
    cached.add(url);
    return _FakeFileInfo();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileInfo implements FileInfo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A picture that is still on its way: the placeholder shows.
class PendingImage extends ImageProvider<PendingImage> {
  @override
  Future<PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// A picture that cannot be had, as offline without it in the cache.
class FailingImage extends ImageProvider<FailingImage> {
  @override
  Future<FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Future.error(Exception('offline')));
}

/// Pictures that do not arrive by default; the addresses asked for are kept
/// in [requested].
List<Override> lessonMediaOverrides({
  FakeMediaCache? cache,
  List<String>? requested,
  ImageProvider Function(String url)? images,
}) => <Override>[
  lessonMediaCacheManagerProvider.overrideWithValue(cache ?? FakeMediaCache()),
  lessonMediaImageProvider.overrideWithValue((url) {
    requested?.add(url);
    return images?.call(url) ?? PendingImage();
  }),
];
