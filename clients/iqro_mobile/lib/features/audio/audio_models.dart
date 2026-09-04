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
    this.renditionQuality,
    this.codec,
    this.bitrateKbps,
    this.renditions = const <AudioRendition>[],
  });

  factory AudioTrack.fromPlayback(Map<String, Object?> json) {
    final track = json['track'] is Map
        ? Map<String, Object?>.from(json['track']! as Map)
        : json;
    final asset = track['asset'] is Map
        ? Map<String, Object?>.from(track['asset']! as Map)
        : const <String, Object?>{};
    final rawRenditions = track['renditions'];
    if (rawRenditions != null &&
        (rawRenditions is! List || rawRenditions.any((item) => item is! Map))) {
      throw const FormatException('Audio renditions are invalid');
    }
    final renditions = rawRenditions is List
        ? rawRenditions
              .map(
                (item) => AudioRendition.fromJson(
                  Map<String, Object?>.from(item! as Map),
                ),
              )
              .where((item) => item.url.isNotEmpty)
              .toList(growable: false)
        : const <AudioRendition>[];
    final selectedQuality = track['selected_quality']?.toString();
    AudioRendition? selected;
    for (final rendition in renditions) {
      if ((selectedQuality != null && rendition.quality == selectedQuality) ||
          (selectedQuality == null && rendition.url == asset['url'])) {
        selected = rendition;
        break;
      }
    }
    selected ??= renditions.where((item) => item.isDefault).firstOrNull;
    return AudioTrack(
      id: track['id']?.toString() ?? '',
      recitationId: track['recitation_id']?.toString() ?? '',
      surah: (track['surah_number'] as num?)?.toInt() ?? 1,
      url: selected?.url ?? asset['url']?.toString() ?? '',
      duration: Duration(
        milliseconds: (track['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      offlineDownloadAllowed: track['offline_download_allowed'] == true,
      renditionQuality: selected?.quality ?? selectedQuality,
      codec: selected?.codec ?? asset['codec']?.toString(),
      bitrateKbps:
          selected?.bitrateKbps ?? (asset['bitrate_kbps'] as num?)?.toInt(),
      renditions: List<AudioRendition>.unmodifiable(renditions),
    );
  }

  final String id;
  final String recitationId;
  final int surah;
  final String url;
  final Duration duration;
  final bool offlineDownloadAllowed;
  final String? renditionQuality;
  final String? codec;
  final int? bitrateKbps;
  final List<AudioRendition> renditions;

  AudioTrack withPreferredQuality(String preference) {
    if (renditions.isEmpty) return this;
    AudioRendition? selected;
    if (preference != 'auto') {
      selected = renditions
          .where((item) => item.quality == preference)
          .firstOrNull;
    }
    selected ??= renditions.where((item) => item.isDefault).firstOrNull;
    selected ??= renditions.first;
    return AudioTrack(
      id: id,
      recitationId: recitationId,
      surah: surah,
      url: selected.url,
      duration: duration,
      offlineDownloadAllowed: offlineDownloadAllowed,
      renditionQuality: selected.quality,
      codec: selected.codec,
      bitrateKbps: selected.bitrateKbps,
      renditions: renditions,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'recitation_id': recitationId,
    'surah_number': surah,
    'duration_ms': duration.inMilliseconds,
    'offline_download_allowed': offlineDownloadAllowed,
    'selected_quality': renditionQuality,
    'asset': <String, Object?>{
      'url': url,
      'codec': codec,
      'bitrate_kbps': bitrateKbps,
    },
    'renditions': renditions.map((item) => item.toJson()).toList(),
  };
}

class AudioRendition {
  const AudioRendition({
    required this.id,
    required this.quality,
    required this.isDefault,
    required this.url,
    required this.codec,
    required this.bitrateKbps,
  });

  factory AudioRendition.fromJson(Map<String, Object?> json) {
    final asset = json['asset'] is Map
        ? Map<String, Object?>.from(json['asset']! as Map)
        : const <String, Object?>{};
    return AudioRendition(
      id: json['id']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      isDefault: json['is_default'] == true,
      url: asset['url']?.toString() ?? '',
      codec: asset['codec']?.toString() ?? '',
      bitrateKbps: (asset['bitrate_kbps'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String quality;
  final bool isDefault;
  final String url;
  final String codec;
  final int bitrateKbps;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'quality': quality,
    'is_default': isDefault,
    'asset': <String, Object?>{
      'url': url,
      'codec': codec,
      'bitrate_kbps': bitrateKbps,
    },
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

  SurahPlayback withPreferredQuality(String preference) => SurahPlayback(
    track: track.withPreferredQuality(preference),
    segments: segments,
  );

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
