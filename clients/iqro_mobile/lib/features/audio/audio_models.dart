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

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'slug': slug,
    'name_ar': nameAr,
    'name_en': nameEn,
    'name_ru': nameRu,
    'name_tr': nameTr,
    'biography_ar': biographyAr,
    'biography_en': biographyEn,
    'biography_ru': biographyRu,
    'biography_tr': biographyTr,
    'portrait_url': portraitUrl,
    'country_code': countryCode,
  };

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
    required this.code,
    required this.reciter,
    required this.style,
    required this.timingsAvailable,
    required this.surahCount,
    required this.streamAllowed,
    required this.offlineDownloadAllowed,
  });

  factory Recitation.fromJson(Map<String, Object?> json) {
    final reciterJson = json['reciter'] is Map
        ? Map<String, Object?>.from(json['reciter']! as Map)
        : const <String, Object?>{};
    final timings = json['timings'] is Map
        ? Map<String, Object?>.from(json['timings']! as Map)
        : const <String, Object?>{};
    final coverage = json['coverage'] is Map
        ? Map<String, Object?>.from(json['coverage']! as Map)
        : const <String, Object?>{};
    final rights = json['rights'] is Map
        ? Map<String, Object?>.from(json['rights']! as Map)
        : const <String, Object?>{};
    return Recitation(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      reciter: Reciter.fromJson(reciterJson),
      style: json['style']?.toString() ?? 'murattal',
      timingsAvailable: timings['available'] == true,
      surahCount: (coverage['surah_count'] as num?)?.toInt() ?? 0,
      streamAllowed: rights['stream'] != false,
      offlineDownloadAllowed: rights['offline_download'] == true,
    );
  }

  final String id;
  final String code;
  final Reciter reciter;
  final String style;
  final bool timingsAvailable;
  final int surahCount;
  final bool streamAllowed;
  final bool offlineDownloadAllowed;
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

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'recitation_id': recitationId,
    'surah_number': surah,
    'duration_ms': duration.inMilliseconds,
    'offline_download_allowed': offlineDownloadAllowed,
    'asset': <String, Object?>{'url': url},
  };
}

class AudioSegment {
  const AudioSegment({
    required this.ayahId,
    required this.surah,
    required this.ayah,
    required this.start,
    required this.end,
  });

  factory AudioSegment.fromJson(Map<String, Object?> json) {
    return AudioSegment(
      ayahId: json['ayah_id']?.toString() ?? '',
      surah: (json['surah_number'] as num?)?.toInt() ?? 0,
      ayah: (json['ayah_number'] as num?)?.toInt() ?? 0,
      start: Duration(milliseconds: (json['start_ms'] as num?)?.toInt() ?? 0),
      end: Duration(milliseconds: (json['end_ms'] as num?)?.toInt() ?? 0),
    );
  }

  final String ayahId;
  final int surah;
  final int ayah;
  final Duration start;
  final Duration end;

  Map<String, Object?> toJson() => <String, Object?>{
    'ayah_id': ayahId,
    'surah_number': surah,
    'ayah_number': ayah,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
  };

  bool contains(Duration position) => position >= start && position < end;
}

class SurahPlayback {
  const SurahPlayback({required this.track, required this.segments});

  factory SurahPlayback.fromJson(Map<String, Object?> json) {
    final track = AudioTrack.fromPlayback(json);
    final rawSegments = json['segments'];
    if (rawSegments != null &&
        (rawSegments is! List || rawSegments.any((item) => item is! Map))) {
      throw const FormatException('Audio timing segments are invalid');
    }
    final playback = SurahPlayback(
      track: track,
      segments: rawSegments is List
          ? rawSegments
                .map(
                  (item) => AudioSegment.fromJson(
                    Map<String, Object?>.from(item! as Map),
                  ),
                )
                .toList(growable: false)
          : const <AudioSegment>[],
    );
    return playback.normalized();
  }

  final AudioTrack track;
  final List<AudioSegment> segments;

  SurahPlayback normalized() {
    if (segments.isEmpty) return this;
    final ordered = List<AudioSegment>.of(segments)
      ..sort((left, right) {
        final byStart = left.start.compareTo(right.start);
        return byStart != 0 ? byStart : left.ayah.compareTo(right.ayah);
      });
    AudioSegment? previous;
    final ayahs = <int>{};
    for (final segment in ordered) {
      if (segment.surah != track.surah ||
          segment.ayah < 1 ||
          segment.ayahId.trim().isEmpty ||
          segment.start.isNegative ||
          segment.end <= segment.start ||
          !ayahs.add(segment.ayah) ||
          (previous != null &&
              (segment.ayah <= previous.ayah ||
                  segment.start < previous.end))) {
        throw const FormatException('Audio timing segments are inconsistent');
      }
      previous = segment;
    }
    return SurahPlayback(
      track: track,
      segments: List<AudioSegment>.unmodifiable(ordered),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'track': track.toJson(),
    'segments': segments.map((segment) => segment.toJson()).toList(),
  };

  AudioSegment? segmentFor(int ayah) {
    for (final segment in segments) {
      if (segment.ayah == ayah) return segment;
    }
    return null;
  }
}

List<Reciter> parseReciters(Object? payload) => jsonResults(payload)
    .whereType<Map>()
    .map((item) => Reciter.fromJson(Map<String, Object?>.from(item)))
    .where((item) => item.id.isNotEmpty)
    .toList(growable: false);
