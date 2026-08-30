import '../../core/utils/json_helpers.dart';

class Reciter {
  const Reciter({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.nameRu,
    required this.nameTr,
    required this.biographyAr,
    required this.biographyEn,
    required this.biographyRu,
    required this.biographyTr,
    this.portraitUrl,
    this.countryCode,
  });

  factory Reciter.fromJson(Map<String, Object?> json) {
    return Reciter(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? '',
      nameRu: json['name_ru']?.toString() ?? '',
      nameTr: json['name_tr']?.toString() ?? '',
      biographyAr: json['biography_ar']?.toString() ?? '',
      biographyEn: json['biography_en']?.toString() ?? '',
      biographyRu: json['biography_ru']?.toString() ?? '',
      biographyTr: json['biography_tr']?.toString() ?? '',
      portraitUrl: json['portrait_url']?.toString(),
      countryCode: json['country_code']?.toString(),
    );
  }

  final String id;
  final String slug;
  final String nameAr;
  final String nameEn;
  final String nameRu;
  final String nameTr;
  final String biographyAr;
  final String biographyEn;
  final String biographyRu;
  final String biographyTr;
  final String? portraitUrl;
  final String? countryCode;

  String nameFor(String locale) {
    if (locale == 'ar' && nameAr.isNotEmpty) return nameAr;
    if (locale == 'ru' && nameRu.isNotEmpty) return nameRu;
    if (locale == 'tr' && nameTr.isNotEmpty) return nameTr;
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }

  String biographyFor(String locale) {
    if (locale == 'ar' && biographyAr.isNotEmpty) return biographyAr;
    if (locale == 'ru' && biographyRu.isNotEmpty) return biographyRu;
    if (locale == 'tr' && biographyTr.isNotEmpty) return biographyTr;
    return biographyEn;
  }

  String get initials {
    final words = nameEn.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return 'IQ';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class Recitation {
  const Recitation({
    required this.id,
    required this.reciter,
    required this.style,
    required this.timingsAvailable,
  });

  factory Recitation.fromJson(Map<String, Object?> json) {
    final reciterJson = json['reciter'] is Map
        ? Map<String, Object?>.from(json['reciter']! as Map)
        : const <String, Object?>{};
    final timings = json['timings'] is Map
        ? Map<String, Object?>.from(json['timings']! as Map)
        : const <String, Object?>{};
    return Recitation(
      id: json['id']?.toString() ?? '',
      reciter: Reciter.fromJson(reciterJson),
      style: json['style']?.toString() ?? 'murattal',
      timingsAvailable: timings['available'] == true,
    );
  }

  final String id;
  final Reciter reciter;
  final String style;
  final bool timingsAvailable;
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.recitationId,
    required this.surah,
    required this.url,
    required this.duration,
    required this.offlineDownloadAllowed,
  });

  factory AudioTrack.fromPlayback(Map<String, Object?> json) {
    final track = json['track'] is Map
        ? Map<String, Object?>.from(json['track']! as Map)
        : json;
    final asset = track['asset'] is Map
        ? Map<String, Object?>.from(track['asset']! as Map)
        : const <String, Object?>{};
    return AudioTrack(
      id: track['id']?.toString() ?? '',
      recitationId: track['recitation_id']?.toString() ?? '',
      surah: (track['surah_number'] as num?)?.toInt() ?? 1,
      url: asset['url']?.toString() ?? '',
      duration: Duration(
        milliseconds: (track['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      offlineDownloadAllowed: track['offline_download_allowed'] == true,
    );
  }

  final String id;
  final String recitationId;
  final int surah;
  final String url;
  final Duration duration;
  final bool offlineDownloadAllowed;
}

List<Reciter> parseReciters(Object? payload) => jsonResults(payload)
    .whereType<Map>()
    .map((item) => Reciter.fromJson(Map<String, Object?>.from(item)))
    .where((item) => item.id.isNotEmpty)
    .toList(growable: false);
