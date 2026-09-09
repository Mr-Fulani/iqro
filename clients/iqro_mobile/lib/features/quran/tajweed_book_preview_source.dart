import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';

/// Opt-in visual experiment, never a published edition or release feature.
const tajweedBookPreviewEnabled =
    !kReleaseMode && bool.fromEnvironment('TAJWEED_BOOK_PREVIEW');

bool canShowTajweedBookPreview(AppConfig config) =>
    tajweedBookPreviewEnabled && !config.isProduction;

class TajweedBookSample {
  const TajweedBookSample(this.page, this.bytes, this.checksum);

  static const commit = 'c6f1455281e19d56a71a999498a323a828de3365';
  static const width = 645;
  static const height = 1000;
  static const samples = <TajweedBookSample>[
    TajweedBookSample(
      51,
      198649,
      '71c7448348cd68a74c9cdf871439e6e044bd66092c110df42ea775a54836b323',
    ),
    TajweedBookSample(
      52,
      200165,
      'e920cf216b94959443b4f0ba9e88223029418a733a6089c7c764642e259e01ab',
    ),
    TajweedBookSample(
      53,
      206161,
      '8277c72b287a2f1310c3ba0b2cb64c63bf4024389c8fe11bcbddcb589b033db3',
    ),
  ];

  final int page;
  final int bytes;
  final String checksum;

  Uri get uri => Uri.parse(
    'https://raw.githubusercontent.com/QuranHub/quran-pages-images/'
    '$commit/easyquran.com/hafs-tajweed/$page.jpg',
  );

  bool verifies(List<int> data) =>
      data.length == bytes && sha256.convert(data).toString() == checksum;
}

/// A three-file, immutable, isolated preview cache. Does not access the Quran
/// database, selected edition, offline packages, account or audio controller.
/// No source images are bundled into production APKs.
class TajweedBookPreviewSource {
  TajweedBookPreviewSource()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.bytes,
        ),
      );

  final Dio _dio;
  final _pending = <int, Future<File>>{};

  Future<File> load(TajweedBookSample sample) =>
      _pending.putIfAbsent(sample.page, () async {
        try {
          return await _load(sample);
        } on Object {
          _pending.remove(sample.page);
          rethrow;
        }
      });

  Future<File> _load(TajweedBookSample sample) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/tajweed-book-preview-v1');
    final file = File('${directory.path}/${sample.checksum}.jpg');
    if (await file.exists()) {
      if (sample.verifies(await file.readAsBytes())) return file;
      // Never silently replace an existing file or use a corrupted scan.
      throw const FormatException('Preview source checksum mismatch');
    }
    final response = await _dio.get<List<int>>(sample.uri.toString());
    final data = response.data;
    if (data == null || !sample.verifies(data)) {
      throw const FormatException('Preview source checksum mismatch');
    }
    await directory.create(recursive: true);
    // Single-flight per page; a partial write is never handed to the renderer.
    final incoming = File(
      '${file.path}.incoming-${DateTime.now().microsecondsSinceEpoch}',
    );
    await incoming.writeAsBytes(data, flush: true);
    return incoming.rename(file.path);
  }

  void dispose() => _dio.close(force: true);
}
