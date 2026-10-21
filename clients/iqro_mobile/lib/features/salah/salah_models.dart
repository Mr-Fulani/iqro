import 'package:flutter/foundation.dart';

/// The compiled course document (`docs/salah/learning-spec.md` §6).
///
/// The server sends every text in the requested language and expands the
/// prayers into linear steps, so the client only renders. Unknown fields are
/// ignored; a newer, incompatible `schema_version` is rejected.
@immutable
class SalahCourseDocument {
  const SalahCourseDocument({
    required this.schemaVersion,
    required this.course,
    required this.sections,
    required this.lessons,
    required this.formulas,
    required this.media,
  });

  static const supportedSchemaVersion = 1;

  factory SalahCourseDocument.fromJson(Object? value) {
    final json = _map(value, 'document');
    final schemaVersion = _int(json['schema_version']);
    if (schemaVersion == null ||
        schemaVersion < 1 ||
        schemaVersion > supportedSchemaVersion) {
      throw FormatException(
        'Unsupported salah schema version: ${json['schema_version']}',
      );
    }
    final lessons = <SalahLesson>[
      for (final item in _list(json['lessons'])) SalahLesson.fromJson(item),
    ];
    final formulas = <String, SalahFormula>{
      for (final entry in _map(
        json['formulas'] ?? const {},
        'formulas',
      ).entries)
        entry.key: SalahFormula.fromJson(entry.key, entry.value),
    };
    final media = <String, SalahMedia>{
      for (final entry in _map(json['media'] ?? const {}, 'media').entries)
        entry.key: SalahMedia.fromJson(entry.key, entry.value),
    };
    return SalahCourseDocument(
      schemaVersion: schemaVersion,
      course: SalahCourseInfo.fromJson(json['course']),
      sections: <SalahSection>[
        for (final item in _list(json['sections'])) SalahSection.fromJson(item),
      ],
      lessons: lessons,
      formulas: formulas,
      media: media,
    );
  }

  final int schemaVersion;
  final SalahCourseInfo course;
  final List<SalahSection> sections;
  final List<SalahLesson> lessons;
  final Map<String, SalahFormula> formulas;
  final Map<String, SalahMedia> media;

  SalahLesson? lesson(String slug) {
    for (final lesson in lessons) {
      if (lesson.slug == slug) return lesson;
    }
    return null;
  }

  /// Lessons of [section] in its order, skipping slugs the document lacks.
  List<SalahLesson> sectionLessons(SalahSection section) => <SalahLesson>[
    for (final slug in section.lessons) ?lesson(slug),
  ];

  /// Every lesson in course order: by section, each lesson once.
  List<SalahLesson> get orderedLessons {
    final seen = <String>{};
    return <SalahLesson>[
      for (final section in sections)
        for (final lesson in sectionLessons(section))
          if (seen.add(lesson.slug)) lesson,
    ];
  }

  /// Formulas of [step] that the document defines, in the step's order.
  List<SalahFormula> stepFormulas(SalahStep step) => <SalahFormula>[
    for (final id in step.formulas) ?formulas[id],
  ];

  SalahMedia? stepMedia(SalahStep step) {
    final key = step.media;
    return key == null ? null : media[key];
  }
}

@immutable
class SalahCourseInfo {
  const SalahCourseInfo({
    required this.slug,
    required this.version,
    required this.language,
    this.methodology = '',
    this.sourceTitle = '',
    this.reviewedBy = '',
    this.reviewedAt,
    this.publishedAt,
    this.checksumSha256 = '',
  });

  factory SalahCourseInfo.fromJson(Object? value) {
    final json = _map(value, 'course');
    return SalahCourseInfo(
      slug: _required(json, 'slug'),
      version: _required(json, 'version'),
      language: _string(json['language']),
      methodology: _string(json['methodology']),
      sourceTitle: _string(json['source_title']),
      reviewedBy: _string(json['reviewed_by']),
      reviewedAt: _date(json['reviewed_at']),
      publishedAt: _date(json['published_at']),
      checksumSha256: _string(json['checksum_sha256']),
    );
  }

  final String slug;
  final String version;
  final String language;
  final String methodology;
  final String sourceTitle;
  final String reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? publishedAt;
  final String checksumSha256;
}

/// One entry of `GET /salah/courses`.
@immutable
class SalahCourseSummary {
  const SalahCourseSummary({
    required this.slug,
    required this.version,
    this.methodology = '',
    this.languages = const <String>[],
    this.publishedAt,
  });

  factory SalahCourseSummary.fromJson(Object? value) {
    final json = _map(value, 'course summary');
    return SalahCourseSummary(
      slug: _required(json, 'slug'),
      version: _required(json, 'version'),
      methodology: _string(json['methodology']),
      languages: <String>[
        for (final item in _list(json['languages'])) ?_optional(item),
      ],
      publishedAt: _date(json['published_at']),
    );
  }

  final String slug;
  final String version;
  final String methodology;
  final List<String> languages;
  final DateTime? publishedAt;
}

@immutable
class SalahSection {
  const SalahSection({
    required this.slug,
    required this.title,
    required this.lessons,
  });

  factory SalahSection.fromJson(Object? value) {
    final json = _map(value, 'section');
    return SalahSection(
      slug: _required(json, 'slug'),
      title: _string(json['title']),
      lessons: <String>[
        for (final item in _list(json['lessons'])) ?_optional(item),
      ],
    );
  }

  final String slug;
  final String title;
  final List<String> lessons;
}

@immutable
class SalahLesson {
  const SalahLesson({
    required this.slug,
    required this.kind,
    required this.title,
    required this.steps,
    this.summary = '',
    this.minutes = 0,
    this.prayer,
  });

  factory SalahLesson.fromJson(Object? value) {
    final json = _map(value, 'lesson');
    final prayer = json['prayer'];
    return SalahLesson(
      slug: _required(json, 'slug'),
      kind: _string(json['kind']),
      title: _string(json['title']),
      summary: _string(json['summary']),
      minutes: _int(json['minutes']) ?? 0,
      prayer: prayer is Map ? SalahPrayer.fromJson(prayer) : null,
      steps: <SalahStep>[
        for (final item in _list(json['steps'])) SalahStep.fromJson(item),
      ],
    );
  }

  final String slug;

  /// `article`, `steps` or `prayer`.
  final String kind;
  final String title;
  final String summary;
  final int minutes;
  final SalahPrayer? prayer;
  final List<SalahStep> steps;

  int indexOfStep(String slug) => steps.indexWhere((step) => step.slug == slug);
}

@immutable
class SalahPrayer {
  const SalahPrayer({
    required this.code,
    required this.kind,
    required this.rakats,
    this.kindTitle,
  });

  factory SalahPrayer.fromJson(Object? value) {
    final json = _map(value, 'prayer');
    return SalahPrayer(
      code: _string(json['code']),
      kind: _string(json['kind']),
      kindTitle: _optional(json['kind_title']),
      rakats: _int(json['rakats']) ?? 0,
    );
  }

  final String code;

  /// A `prayer_kinds` code of the course (`fard`, `witr`, `sunnah`, and any
  /// kind a newer course adds); the app shows [kindTitle] and never switches on it.
  final String kind;

  /// The kind's name in the document's language.
  final String? kindTitle;
  final int rakats;
}

@immutable
class SalahStep {
  const SalahStep({
    required this.slug,
    required this.kind,
    required this.title,
    required this.instruction,
    this.position,
    this.ruling,
    this.rakat,
    this.details,
    this.media,
    this.formulas = const <String>[],
    this.repeat,
  });

  factory SalahStep.fromJson(Object? value) {
    final json = _map(value, 'step');
    return SalahStep(
      slug: _required(json, 'slug'),
      kind: _string(json['kind']),
      position: _optional(json['position']),
      ruling: _optional(json['ruling']),
      rakat: _int(json['rakat']),
      title: _string(json['title']),
      instruction: _string(json['instruction']),
      details: _optional(json['details']),
      media: _optional(json['media']),
      formulas: <String>[
        for (final item in _list(json['formulas'])) ?_optional(item),
      ],
      repeat: _int(json['repeat']),
    );
  }

  /// Stable id, for example `fajr.r1.ruku`.
  final String slug;

  /// `action`, `recitation` or `info`.
  final String kind;
  final String? position;

  /// `shart`, `rukn`, `wajib` or `sunnah`.
  final String? ruling;
  final int? rakat;
  final String title;
  final String instruction;
  final String? details;
  final String? media;
  final List<String> formulas;
  final int? repeat;
}

@immutable
class SalahFormula {
  const SalahFormula({
    required this.id,
    required this.arabic,
    required this.translation,
    required this.source,
    this.transliteration,
    this.repetitions = 1,
    this.audio,
  });

  factory SalahFormula.fromJson(String id, Object? value) {
    final json = _map(value, 'formula');
    final audio = json['audio'];
    final repetitions = _int(json['repetitions']) ?? 1;
    return SalahFormula(
      id: id,
      arabic: _string(json['arabic']),
      transliteration: _optional(json['transliteration']),
      translation: _string(json['translation']),
      repetitions: repetitions < 1 ? 1 : repetitions,
      audio: audio is Map ? SalahFormulaAudio.fromJson(audio) : null,
      source: SalahFormulaSource.fromJson(json['source']),
    );
  }

  final String id;
  final String arabic;
  final String? transliteration;
  final String translation;
  final int repetitions;
  final SalahFormulaAudio? audio;
  final SalahFormulaSource source;
}

@immutable
class SalahFormulaAudio {
  const SalahFormulaAudio({
    required this.url,
    this.startMs,
    this.endMs,
    this.segments = const <SalahAudioSegment>[],
  });

  factory SalahFormulaAudio.fromJson(Object? value) {
    final json = _map(value, 'audio');
    return SalahFormulaAudio(
      url: _required(json, 'url'),
      startMs: _int(json['start_ms']),
      endMs: _int(json['end_ms']),
      segments: <SalahAudioSegment>[
        for (final item in _list(json['segments']))
          SalahAudioSegment.fromJson(item),
      ],
    );
  }

  final String url;
  final int? startMs;
  final int? endMs;
  final List<SalahAudioSegment> segments;
}

@immutable
class SalahAudioSegment {
  const SalahAudioSegment({
    required this.ayah,
    required this.startMs,
    required this.endMs,
  });

  factory SalahAudioSegment.fromJson(Object? value) {
    final json = _map(value, 'segment');
    return SalahAudioSegment(
      ayah: _int(json['ayah']) ?? 0,
      startMs: _int(json['start_ms']) ?? 0,
      endMs: _int(json['end_ms']) ?? 0,
    );
  }

  final int ayah;
  final int startMs;
  final int endMs;
}

@immutable
class SalahFormulaSource {
  const SalahFormulaSource({
    required this.kind,
    this.collection,
    this.sourceNumber,
    this.surah,
    this.ayahFrom,
    this.ayahTo,
  });

  factory SalahFormulaSource.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return SalahFormulaSource(
      kind: _string(json['kind']),
      collection: _optional(json['collection']),
      sourceNumber: _int(json['source_number']),
      surah: _int(json['surah']),
      ayahFrom: _int(json['ayah_from']),
      ayahTo: _int(json['ayah_to']),
    );
  }

  /// `dua`, `quran` or `inline`.
  final String kind;
  final String? collection;
  final int? sourceNumber;
  final int? surah;
  final int? ayahFrom;
  final int? ayahTo;
}

@immutable
class SalahMedia {
  const SalahMedia({
    required this.key,
    required this.url,
    required this.width,
    required this.height,
    this.bytes = 0,
    this.sha256 = '',
    this.alt = '',
    this.scene,
  });

  factory SalahMedia.fromJson(String key, Object? value) {
    final json = _map(value, 'media');
    return SalahMedia(
      key: key,
      url: _required(json, 'url'),
      width: _int(json['width']) ?? 0,
      height: _int(json['height']) ?? 0,
      bytes: _int(json['bytes']) ?? 0,
      sha256: _string(json['sha256']),
      alt: _string(json['alt']),
      scene: SalahMediaScene.tryParse(json['scene']),
    );
  }

  final String key;
  final String url;
  final int width;
  final int height;
  final int bytes;
  final String sha256;
  final String alt;

  /// Set when the picture is a still of the schematic 3D scene.
  final SalahMediaScene? scene;

  /// Width over height, or a square when the document omits the size.
  double get aspectRatio => width > 0 && height > 0 ? width / height : 1;
}

/// The pose and view of the schematic 3D scene (docs/salah/salah-3d.md) that
/// a picture is a still of. A malformed scene leaves just the picture.
@immutable
class SalahMediaScene {
  const SalahMediaScene({required this.pose, this.view = 'full'});

  static SalahMediaScene? tryParse(Object? value) {
    if (value is! Map) return null;
    final pose = value['pose'];
    final view = value['view'];
    if (pose is! String || pose.isEmpty) return null;
    if (view is! String || !_views.contains(view)) return null;
    return SalahMediaScene(pose: pose, view: view);
  }

  static const _views = <String>{'full', 'hand', 'back'};

  /// A pose of the scene, for example `ruku`.
  final String pose;

  /// `full`, `hand` or `back`.
  final String view;

  @override
  bool operator ==(Object other) =>
      other is SalahMediaScene && other.pose == pose && other.view == view;

  @override
  int get hashCode => Object.hash(pose, view);
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('Salah $name must be a JSON object');
}

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

String _string(Object? value) => value?.toString() ?? '';

String? _optional(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _required(Map<String, Object?> json, String key) {
  final value = _optional(json[key]);
  if (value == null) throw FormatException('Salah field "$key" is missing');
  return value;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
