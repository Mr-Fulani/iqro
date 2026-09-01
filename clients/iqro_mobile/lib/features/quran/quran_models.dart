import '../../core/utils/json_helpers.dart';

class Surah {
  const Surah({
    required this.id,
    required this.number,
    required this.nameAr,
    required this.nameEn,
    required this.nameRu,
    required this.ayahCount,
    required this.revelationType,
    this.firstPage,
  });

  factory Surah.fromJson(Map<String, Object?> json) {
    return Surah(
      id: json['id']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      nameAr: json['name_ar']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? '',
      nameRu: json['name_ru']?.toString() ?? '',
      ayahCount: (json['ayah_count'] as num?)?.toInt() ?? 0,
      revelationType: json['revelation_type']?.toString() ?? '',
      firstPage: (json['first_page'] as num?)?.toInt(),
    );
  }

  final String id;
  final int number;
  final String nameAr;
  final String nameEn;
  final String nameRu;
  final int ayahCount;
  final String revelationType;
  final int? firstPage;

  String nameFor(String locale) {
    if (locale == 'ar') return nameAr;
    if (locale == 'ru' && nameRu.isNotEmpty) return nameRu;
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }
}

class QuranAyah {
  const QuranAyah({
    required this.id,
    required this.surahNumber,
    required this.number,
    required this.textUthmani,
    required this.pages,
  });

  factory QuranAyah.fromJson(Map<String, Object?> json) {
    return QuranAyah(
      id: json['id']?.toString() ?? '',
      surahNumber: (json['surah_number'] as num?)?.toInt() ?? 0,
      number: (json['number'] as num?)?.toInt() ?? 0,
      textUthmani: json['text_uthmani']?.toString() ?? '',
      pages:
          (json['pages'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const <int>[],
    );
  }

  final String id;
  final int surahNumber;
  final int number;
  final String textUthmani;
  final List<int> pages;
}

class QuranAyahReference {
  const QuranAyahReference({
    required this.id,
    required this.surah,
    required this.ayah,
  });

  factory QuranAyahReference.fromJson(Map<String, Object?> json) {
    return QuranAyahReference(
      id: json['id']?.toString() ?? '',
      surah: (json['surah'] as num?)?.toInt() ?? 0,
      ayah: (json['number'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final int surah;
  final int ayah;

  String get key => '$surah:$ayah';

  @override
  bool operator ==(Object other) {
    return other is QuranAyahReference &&
        other.surah == surah &&
        other.ayah == ayah;
  }

  @override
  int get hashCode => Object.hash(surah, ayah);
}

class MushafPoint {
  const MushafPoint(this.x, this.y);

  final double x;
  final double y;
}

class MushafAyahRegion {
  const MushafAyahRegion({
    required this.id,
    required this.ayah,
    required this.readingOrder,
    required this.polygon,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory MushafAyahRegion.fromJson(Map<String, Object?> json) {
    final ayah = json['ayah'] is Map
        ? Map<String, Object?>.from(json['ayah']! as Map)
        : const <String, Object?>{};
    final polygon =
        (json['polygon'] as List?)
            ?.whereType<List>()
            .where((point) => point.length >= 2)
            .map(
              (point) => MushafPoint(_asDouble(point[0]), _asDouble(point[1])),
            )
            .toList(growable: false) ??
        const <MushafPoint>[];
    return MushafAyahRegion(
      id: json['id']?.toString() ?? '',
      ayah: QuranAyahReference.fromJson(ayah),
      readingOrder: (json['reading_order'] as num?)?.toInt() ?? 0,
      polygon: polygon,
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      width: _asDouble(json['width']),
      height: _asDouble(json['height']),
    );
  }

  final String id;
  final QuranAyahReference ayah;
  final int readingOrder;
  final List<MushafPoint> polygon;
  final double x;
  final double y;
  final double width;
  final double height;

  bool contains(double normalizedX, double normalizedY) {
    if (!normalizedX.isFinite ||
        !normalizedY.isFinite ||
        normalizedX < 0 ||
        normalizedX > 1 ||
        normalizedY < 0 ||
        normalizedY > 1 ||
        !_hasValidBounds) {
      return false;
    }
    if (normalizedX < x ||
        normalizedX > x + width ||
        normalizedY < y ||
        normalizedY > y + height) {
      return false;
    }
    if (polygon.length < 3) return true;
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final currentPoint = polygon[index];
      final previousPoint = polygon[previous];
      final crosses =
          (currentPoint.y > normalizedY) != (previousPoint.y > normalizedY) &&
          normalizedX <
              (previousPoint.x - currentPoint.x) *
                      (normalizedY - currentPoint.y) /
                      (previousPoint.y - currentPoint.y) +
                  currentPoint.x;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  bool get _hasValidBounds {
    if (!x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        x < 0 ||
        y < 0 ||
        width <= 0 ||
        height <= 0 ||
        x + width > 1 ||
        y + height > 1) {
      return false;
    }
    return polygon.every(
      (point) =>
          point.x.isFinite &&
          point.y.isFinite &&
          point.x >= 0 &&
          point.x <= 1 &&
          point.y >= 0 &&
          point.y <= 1,
    );
  }
}

class MushafAsset {
  const MushafAsset({
    required this.url,
    required this.width,
    required this.sha256,
    this.height,
    this.bytes,
  });

  factory MushafAsset.fromJson(Map<String, Object?> json) {
    return MushafAsset(
      url: json['url']?.toString() ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      sha256: json['sha256']?.toString() ?? '',
      height: (json['height'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt(),
    );
  }

  final String url;
  final int width;
  final String sha256;
  final int? height;
  final int? bytes;

  bool get isUsable {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.path.toLowerCase().endsWith('.webp') &&
        width > 0 &&
        height != null &&
        height! > 0 &&
        bytes != null &&
        bytes! > 0 &&
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256);
  }
}

class MushafPageData {
  const MushafPageData({
    required this.number,
    required this.contentVersion,
    required this.checksumSha256,
    required this.imageWidth,
    required this.imageHeight,
    required this.assets,
    required this.regions,
  });

  factory MushafPageData.fromJson(Map<String, Object?> json) {
    return MushafPageData(
      number: (json['number'] as num?)?.toInt() ?? 1,
      contentVersion: json['content_version']?.toString() ?? 'unknown',
      checksumSha256: json['checksum_sha256']?.toString() ?? '',
      imageWidth: (json['image_width'] as num?)?.toInt() ?? 900,
      imageHeight: (json['image_height'] as num?)?.toInt() ?? 1380,
      assets:
          (json['assets'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => MushafAsset.fromJson(Map<String, Object?>.from(item)),
              )
              .where((item) => item.isUsable)
              .toList(growable: false) ??
          const <MushafAsset>[],
      regions:
          (json['regions'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    MushafAyahRegion.fromJson(Map<String, Object?>.from(item)),
              )
              .where((item) => item.ayah.surah > 0 && item.ayah.ayah > 0)
              .toList(growable: false) ??
          const <MushafAyahRegion>[],
    );
  }

  final int number;
  final String contentVersion;
  final String checksumSha256;
  final int imageWidth;
  final int imageHeight;
  final List<MushafAsset> assets;
  final List<MushafAyahRegion> regions;

  ({int surah, int ayah})? get firstAyahReference {
    if (regions.isEmpty) return null;
    final ordered = List<MushafAyahRegion>.of(regions)
      ..sort((a, b) => a.readingOrder.compareTo(b.readingOrder));
    final reference = ordered.first.ayah;
    return (surah: reference.surah, ayah: reference.ayah);
  }

  QuranAyahReference? ayahAt(double normalizedX, double normalizedY) {
    if (!normalizedX.isFinite ||
        !normalizedY.isFinite ||
        normalizedX < 0 ||
        normalizedX > 1 ||
        normalizedY < 0 ||
        normalizedY > 1) {
      return null;
    }
    for (final region in regions.reversed) {
      if (region.contains(normalizedX, normalizedY)) return region.ayah;
    }
    return null;
  }

  MushafAsset? bestAssetFor(double logicalWidth, double devicePixelRatio) {
    if (assets.isEmpty) return null;
    final target = logicalWidth * devicePixelRatio;
    final sorted = List<MushafAsset>.of(assets)
      ..sort((a, b) => a.width.compareTo(b.width));
    return sorted.firstWhere(
      (asset) => asset.width >= target,
      orElse: () => sorted.last,
    );
  }
}

class QuranTranslationEdition {
  const QuranTranslationEdition({
    required this.sourceId,
    required this.languageCode,
    required this.name,
    required this.authorName,
  });

  factory QuranTranslationEdition.fromJson(Map<String, Object?> json) {
    return QuranTranslationEdition(
      sourceId: (json['source_id'] as num?)?.toInt() ?? 0,
      languageCode: json['language_code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '',
    );
  }

  final int sourceId;
  final String languageCode;
  final String name;
  final String authorName;
}

class QuranAyahTranslation {
  const QuranAyahTranslation({
    required this.verseKey,
    required this.surah,
    required this.ayah,
    required this.text,
    required this.footnotes,
  });

  factory QuranAyahTranslation.fromJson(Map<String, Object?> json) {
    return QuranAyahTranslation(
      verseKey: json['verse_key']?.toString() ?? '',
      surah: (json['surah_number'] as num?)?.toInt() ?? 0,
      ayah: (json['ayah_number'] as num?)?.toInt() ?? 0,
      text: json['text']?.toString() ?? '',
      footnotes: _footnotes(json['foot_notes']),
    );
  }

  final String verseKey;
  final int surah;
  final int ayah;
  final String text;
  final List<String> footnotes;
}

class QuranTafsirEdition {
  const QuranTafsirEdition({
    required this.sourceId,
    required this.languageCode,
    required this.name,
    required this.authorName,
  });

  factory QuranTafsirEdition.fromJson(Map<String, Object?> json) {
    return QuranTafsirEdition(
      sourceId: (json['source_id'] as num?)?.toInt() ?? 0,
      languageCode: json['language_code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '',
    );
  }

  final int sourceId;
  final String languageCode;
  final String name;
  final String authorName;
}

class QuranAyahTafsir {
  const QuranAyahTafsir({
    required this.verseKey,
    required this.startVerseKey,
    required this.endVerseKey,
    required this.text,
  });

  factory QuranAyahTafsir.fromJson(Map<String, Object?> json) {
    return QuranAyahTafsir(
      verseKey: json['verse_key']?.toString() ?? '',
      startVerseKey: json['start_verse_key']?.toString() ?? '',
      endVerseKey: json['end_verse_key']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }

  final String verseKey;
  final String startVerseKey;
  final String endVerseKey;
  final String text;

  int get surah => int.tryParse(verseKey.split(':').first) ?? 0;
  int get ayah => int.tryParse(verseKey.split(':').last) ?? 0;

  bool covers(int surah, int ayah) {
    final start = _verseParts(startVerseKey.isEmpty ? verseKey : startVerseKey);
    final end = _verseParts(endVerseKey.isEmpty ? verseKey : endVerseKey);
    final currentOrder = surah * 1000 + ayah;
    return currentOrder >= start.$1 * 1000 + start.$2 &&
        currentOrder <= end.$1 * 1000 + end.$2;
  }
}

(int, int) _verseParts(String key) {
  final parts = key.split(':');
  return (
    int.tryParse(parts.firstOrNull ?? '') ?? 0,
    int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
  );
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _footnotes(Object? value) {
  if (value is List) {
    return value
        .map((item) {
          if (item is Map) return item['text']?.toString() ?? '';
          return item?.toString() ?? '';
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is Map) {
    return value.values
        .map((item) {
          if (item is Map) return item['text']?.toString() ?? '';
          return item?.toString() ?? '';
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

class MushafVariant {
  const MushafVariant({
    required this.sourceId,
    required this.name,
    required this.description,
    required this.qiratName,
    required this.pagesCount,
    required this.renderingAvailable,
    required this.renderingMode,
    required this.linesPerPage,
    required this.sourceChecksum,
    this.fontUrl,
    this.fontUrlTemplate,
  });

  factory MushafVariant.fromJson(Map<String, Object?> json) {
    final rendering = jsonMap(json['rendering']);
    return MushafVariant(
      sourceId: (json['source_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      qiratName: json['qirat_name']?.toString() ?? '',
      pagesCount: (json['pages_count'] as num?)?.toInt() ?? 604,
      renderingAvailable: rendering['available'] == true,
      renderingMode: rendering['mode']?.toString() ?? 'unknown',
      linesPerPage: (json['lines_per_page'] as num?)?.toInt() ?? 15,
      sourceChecksum: json['source_checksum_sha256']?.toString() ?? '',
      fontUrl: rendering['font_url']?.toString(),
      fontUrlTemplate: rendering['font_url_template']?.toString(),
    );
  }

  final int sourceId;
  final String name;
  final String description;
  final String qiratName;
  final int pagesCount;
  final bool renderingAvailable;
  final String renderingMode;
  final int linesPerPage;
  final String sourceChecksum;
  final String? fontUrl;
  final String? fontUrlTemplate;

  String get preferenceValue => '$sourceId';

  // Browser font contracts cannot guarantee a pixel-stable native page or an
  // accurate ayah hit map. Readiness is unlocked by native backend assets.
  bool get supportedOnMobile => false;

  Uri? fontUriForPage(int page) {
    final raw = switch (renderingMode) {
      'unicode-font' => fontUrl,
      'page-font' => fontUrlTemplate?.replaceAll('{page}', '$page'),
      _ => null,
    };
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'verses.quran.foundation' ||
        !uri.path.startsWith('/fonts/quran/') ||
        !uri.path.endsWith('.woff2')) {
      return null;
    }
    return uri;
  }
}

class FoundationMushafPage {
  const FoundationMushafPage({required this.value, required this.fromCache});

  factory FoundationMushafPage.fromJson(
    Map<String, Object?> json, {
    required bool fromCache,
  }) {
    return FoundationMushafPage(value: json, fromCache: fromCache);
  }

  final Map<String, Object?> value;
  final bool fromCache;

  int get pageNumber => (value['page_number'] as num?)?.toInt() ?? 1;

  ({int surah, int ayah})? get firstAyahReference {
    final mapping = value['verse_mapping'];
    if (mapping is! Map || mapping.isEmpty) return null;
    final entries =
        mapping.entries
            .map(
              (entry) => (
                surah: int.tryParse(entry.key.toString()),
                ranges: entry.value?.toString() ?? '',
              ),
            )
            .where((entry) => entry.surah != null)
            .toList(growable: false)
          ..sort((left, right) => left.surah!.compareTo(right.surah!));
    for (final entry in entries) {
      final firstRange = entry.ranges.split(',').first.trim();
      final match = RegExp(r'^(\d+)(?:-\d+)?$').firstMatch(firstRange);
      if (match == null) continue;
      final ayah = int.tryParse(match.group(1)!);
      if (ayah != null) return (surah: entry.surah!, ayah: ayah);
    }
    return null;
  }
}

class ReadingPosition {
  const ReadingPosition({
    required this.edition,
    required this.entityId,
    required this.surah,
    required this.ayah,
    required this.page,
    required this.revision,
  });

  final String edition;
  final String entityId;
  final int surah;
  final int ayah;
  final int page;
  final int revision;
}

class QuranDivision {
  const QuranDivision({
    required this.number,
    required this.startAyah,
    required this.endAyah,
    required this.startPage,
    required this.endPage,
  });

  factory QuranDivision.fromJson(Map<String, Object?> json) {
    final start = json['start_ayah'] is Map
        ? Map<String, Object?>.from(json['start_ayah']! as Map)
        : const <String, Object?>{};
    final end = json['end_ayah'] is Map
        ? Map<String, Object?>.from(json['end_ayah']! as Map)
        : const <String, Object?>{};
    return QuranDivision(
      number: (json['number'] as num?)?.toInt() ?? 0,
      startAyah: QuranAyahReference.fromJson(start),
      endAyah: QuranAyahReference.fromJson(end),
      startPage: (json['start_page'] as num?)?.toInt() ?? 1,
      endPage: (json['end_page'] as num?)?.toInt() ?? 1,
    );
  }

  final int number;
  final QuranAyahReference startAyah;
  final QuranAyahReference endAyah;
  final int startPage;
  final int endPage;
}

class QuranCatalog {
  const QuranCatalog({required this.surahs, required this.fromCache});

  final List<Surah> surahs;
  final bool fromCache;
}

List<Surah> parseSurahs(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map((item) => Surah.fromJson(Map<String, Object?>.from(item)))
      .where((surah) => surah.number > 0)
      .toList(growable: false);
}
