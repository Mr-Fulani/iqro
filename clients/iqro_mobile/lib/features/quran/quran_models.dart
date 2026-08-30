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

class MushafAsset {
  const MushafAsset({
    required this.url,
    required this.width,
    this.height,
    this.bytes,
  });

  factory MushafAsset.fromJson(Map<String, Object?> json) {
    return MushafAsset(
      url: json['url']?.toString() ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt(),
    );
  }

  final String url;
  final int width;
  final int? height;
  final int? bytes;
}

class MushafPageData {
  const MushafPageData({
    required this.number,
    required this.assets,
    required this.regions,
  });

  factory MushafPageData.fromJson(Map<String, Object?> json) {
    return MushafPageData(
      number: (json['number'] as num?)?.toInt() ?? 1,
      assets:
          (json['assets'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => MushafAsset.fromJson(Map<String, Object?>.from(item)),
              )
              .where((item) => item.url.isNotEmpty)
              .toList(growable: false) ??
          const <MushafAsset>[],
      regions:
          (json['regions'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
    );
  }

  final int number;
  final List<MushafAsset> assets;
  final List<Map<String, Object?>> regions;

  ({int surah, int ayah})? get firstAyahReference {
    if (regions.isEmpty) return null;
    final ayah = regions.first['ayah'];
    if (ayah is! Map) return null;
    final surahNumber = (ayah['surah'] as num?)?.toInt();
    final ayahNumber = (ayah['number'] as num?)?.toInt();
    if (surahNumber == null || ayahNumber == null) return null;
    return (surah: surahNumber, ayah: ayahNumber);
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
