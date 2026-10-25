import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../courses/course_models.dart'
    show LessonMedia, NoteBlock, parseLessonMedia, parseNoteBlocks;
import '../tajweed/tajweed_models.dart';

/// The course of the first version (docs/tajweed/course.md).
const tajweedCourseSlug = 'tajweed';

/// Examples a lesson asks for first: three to read and one to find.
const tajweedFirstExamples = 4;

/// Examples «More examples» adds.
const tajweedMoreExamples = 3;

final _lessonSlug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final _stepSlug = RegExp(r'^(?:intro|how|find|example-[1-9][0-9]?)$');
final _color = RegExp(r'^#[0-9a-fA-F]{6}$');

bool isTajweedLessonSlug(String value) =>
    value.length <= 64 && _lessonSlug.hasMatch(value);

bool isTajweedStepSlug(String value) => _stepSlug.hasMatch(value);

/// The course is not published, or was withdrawn.
class TajweedCourseUnavailable implements Exception {
  const TajweedCourseUnavailable(this.slug);

  final String slug;

  @override
  String toString() => 'Tajweed course "$slug" is not published';
}

/// The compiled course document in one language. A document of another
/// `schema_version`, or with a lesson that does not fit, is rejected, as on
/// the site; section entries without a lesson are dropped.
@immutable
class TajweedCourseDocument {
  const TajweedCourseDocument({
    required this.course,
    required this.targets,
    required this.sections,
    required this.lessons,
  });

  static const schemaVersion = 1;

  factory TajweedCourseDocument.fromJson(Object? value) {
    final json = _map(value, 'document');
    if (json['schema_version'] != schemaVersion) {
      throw FormatException(
        'Unsupported tajweed course schema version: ${json['schema_version']}',
      );
    }
    final targets = <String, TajweedCourseTarget>{
      for (final entry in _map(json['targets'], 'targets').entries)
        entry.key: TajweedCourseTarget.fromJson(entry.value),
    };
    final lessons = <TajweedCourseLesson>[
      for (final item in _list(json['lessons'], 'lessons'))
        TajweedCourseLesson.fromJson(item),
    ];
    for (final lesson in lessons) {
      if (!targets.containsKey(lesson.target)) {
        throw FormatException('Unknown tajweed target ${lesson.target}');
      }
    }
    final known = {for (final lesson in lessons) lesson.slug};
    return TajweedCourseDocument(
      course: TajweedCourseInfo.fromJson(json['course']),
      targets: targets,
      sections: <TajweedCourseSection>[
        for (final item in _list(json['sections'], 'sections'))
          TajweedCourseSection.fromJson(item, known),
      ],
      lessons: lessons,
    );
  }

  final TajweedCourseInfo course;
  final Map<String, TajweedCourseTarget> targets;
  final List<TajweedCourseSection> sections;
  final List<TajweedCourseLesson> lessons;

  bool get pendingReview => course.reviewStatus == 'pending_teacher_review';

  TajweedCourseLesson? lesson(String slug) =>
      lessons.where((lesson) => lesson.slug == slug).firstOrNull;

  TajweedCourseTarget target(TajweedCourseLesson lesson) =>
      targets[lesson.target]!;

  List<TajweedCourseLesson> sectionLessons(TajweedCourseSection section) => [
    for (final slug in section.lessons) ?lesson(slug),
  ];

  /// Lessons in the course order: by section, each lesson once.
  List<TajweedCourseLesson> get orderedLessons {
    final seen = <String>{};
    return [
      for (final section in sections)
        for (final lesson in sectionLessons(section))
          if (seen.add(lesson.slug)) lesson,
    ];
  }

  TajweedCourseLesson? nextLesson(String slug) {
    final ordered = orderedLessons;
    final index = ordered.indexWhere((lesson) => lesson.slug == slug);
    return index >= 0 && index + 1 < ordered.length ? ordered[index + 1] : null;
  }
}

@immutable
class TajweedCourseInfo {
  const TajweedCourseInfo({
    required this.slug,
    required this.version,
    required this.language,
    required this.title,
    required this.summary,
    required this.reviewStatus,
    this.publishedAt,
  });

  factory TajweedCourseInfo.fromJson(Object? value) {
    final json = _map(value, 'course');
    return TajweedCourseInfo(
      slug: _text(json, 'slug'),
      version: _text(json, 'version'),
      language: _text(json, 'language'),
      title: _text(json, 'title'),
      summary: _text(json, 'summary'),
      reviewStatus: _text(json, 'review_status'),
      publishedAt: json['published_at'] is String
          ? DateTime.tryParse(json['published_at']! as String)
          : null,
    );
  }

  final String slug;
  final String version;
  final String language;
  final String title;
  final String summary;
  final String reviewStatus;
  final DateTime? publishedAt;
}

/// What a lesson looks for in an ayah: a Quran.Foundation class, or a
/// target the course reads from the letters ([rule] is null then).
@immutable
class TajweedCourseTarget {
  const TajweedCourseTarget({
    required this.name,
    required this.arabicName,
    required this.color,
    this.rule,
  });

  factory TajweedCourseTarget.fromJson(Object? value) {
    final json = _map(value, 'target');
    final color = _text(json, 'color');
    if (!_color.hasMatch(color)) {
      throw const FormatException('Tajweed target colour is invalid');
    }
    return TajweedCourseTarget(
      name: _text(json, 'name'),
      arabicName: _text(json, 'arabic_name'),
      color: Color(0xff000000 | int.parse(color.substring(1), radix: 16)),
      rule: json['rule'] is String ? json['rule']! as String : null,
    );
  }

  final String name;
  final String arabicName;
  final Color color;
  final String? rule;
}

@immutable
class TajweedCourseSection {
  const TajweedCourseSection({
    required this.slug,
    required this.title,
    required this.lessons,
  });

  factory TajweedCourseSection.fromJson(Object? value, Set<String> known) {
    final json = _map(value, 'section');
    return TajweedCourseSection(
      slug: _text(json, 'slug'),
      title: _text(json, 'title'),
      lessons: [
        for (final slug in _list(json['lessons'], 'section lessons'))
          if (slug is String && known.contains(slug)) slug,
      ],
    );
  }

  final String slug;
  final String title;
  final List<String> lessons;
}

@immutable
class TajweedCourseLesson {
  const TajweedCourseLesson({
    required this.slug,
    required this.section,
    required this.target,
    required this.title,
    this.minutes = 0,
    this.summary = '',
    this.explanation = '',
    this.how = '',
    this.letters = '',
    this.media = const [],
    this.explanationBlocks,
    this.howBlocks,
  });

  factory TajweedCourseLesson.fromJson(Object? value) {
    final json = _map(value, 'lesson');
    final slug = _text(json, 'slug');
    if (!isTajweedLessonSlug(slug)) {
      throw FormatException('Tajweed lesson slug "$slug" is invalid');
    }
    final minutes = json['minutes'];
    return TajweedCourseLesson(
      slug: slug,
      section: _text(json, 'section'),
      target: _text(json, 'target'),
      minutes: minutes is num ? minutes.toInt() : 0,
      title: _text(json, 'title'),
      summary: _text(json, 'summary'),
      explanation: _text(json, 'explanation'),
      how: _text(json, 'how'),
      letters: json['letters'] is String ? json['letters']! as String : '',
      // Documents built before lesson media have none.
      media: parseLessonMedia(json['media']),
      // Documents built before links and notes have no blocks.
      explanationBlocks: json['explanation_blocks'] == null
          ? null
          : parseNoteBlocks(json['explanation_blocks']),
      howBlocks: json['how_blocks'] == null
          ? null
          : parseNoteBlocks(json['how_blocks']),
    );
  }

  final String slug;
  final String section;
  final String target;
  final int minutes;
  final String title;
  final String summary;

  /// Paragraphs separated by an empty line, without markup.
  final String explanation;
  final String how;
  final String letters;

  /// The same texts as notes blocks: bold, Arabic runs, «!» and «?» notes
  /// and links; null in documents built before them.
  final List<NoteBlock>? explanationBlocks;
  final List<NoteBlock>? howBlocks;

  /// Videos, slides and banners above the explanation, in the author's
  /// order, in the format of the thematic courses.
  final List<LessonMedia> media;
}

/// One entry of `GET /tajweed/courses`.
@immutable
class TajweedCourseSummary {
  const TajweedCourseSummary({
    required this.slug,
    required this.version,
    this.languages = const [],
  });

  factory TajweedCourseSummary.fromJson(Object? value) {
    final json = _map(value, 'course summary');
    final languages = json['languages'];
    return TajweedCourseSummary(
      slug: _text(json, 'slug'),
      version: _text(json, 'version'),
      languages: [
        if (languages is List)
          for (final item in languages)
            if (item is String) item,
      ],
    );
  }

  final String slug;
  final String version;
  final List<String> languages;
}

/// A part of an occurrence: letters [start]..[end] of the word at [position].
typedef TajweedOccurrencePart = ({int position, int start, int end});

typedef TajweedCourseWord = ({int position, String text});

@immutable
class TajweedOccurrence {
  const TajweedOccurrence({required this.parts, this.variant});

  final List<TajweedOccurrencePart> parts;
  final String? variant;

  /// Positions of the occurrence's words, in reading order.
  List<int> get positions =>
      ({for (final part in parts) part.position}.toList()..sort());

  bool contains(int position) => parts.any((part) => part.position == position);

  /// The occurrence's letters in the word at [position], as fragments for
  /// [tajweedRuns].
  List<TajweedFragment> fragments(int position) => [
    for (final part in parts)
      if (part.position == position)
        TajweedFragment(code: 'target', start: part.start, end: part.end),
  ];
}

/// One ayah where a lesson's target occurs.
@immutable
class TajweedCourseExample {
  const TajweedCourseExample({
    required this.surah,
    required this.ayah,
    required this.words,
    required this.occurrences,
    this.page = 0,
  });

  final int surah;
  final int ayah;
  final int page;

  /// Every word of the ayah, by Quran.Foundation position.
  final List<TajweedCourseWord> words;

  /// Every place of the target, in reading order.
  final List<TajweedOccurrence> occurrences;

  String get verseKey => '$surah:$ayah';

  /// Index of the occurrence with a part in the word at [position], or -1.
  int occurrenceAt(int position) =>
      occurrences.indexWhere((occurrence) => occurrence.contains(position));

  /// The example from the API, or null when it does not fit.
  static TajweedCourseExample? tryParse(Object? value) {
    if (value is! Map) return null;
    final key = value['verse_key'];
    if (key is! String) return null;
    final match = RegExp(r'^(\d{1,3}):(\d{1,3})$').firstMatch(key);
    final surah = value['surah_number'] is int
        ? value['surah_number'] as int
        : int.tryParse(match?.group(1) ?? '');
    final ayah = value['ayah_number'] is int
        ? value['ayah_number'] as int
        : int.tryParse(match?.group(2) ?? '');
    final rawWords = value['words'];
    final rawOccurrences = value['occurrences'];
    if (surah == null ||
        ayah == null ||
        rawWords is! List ||
        rawOccurrences is! List ||
        rawOccurrences.isEmpty) {
      return null;
    }
    final words = <TajweedCourseWord>[];
    for (final word in rawWords) {
      if (word is! Map || word['position'] is! int || word['text'] is! String) {
        return null;
      }
      words.add((
        position: word['position'] as int,
        text: word['text'] as String,
      ));
    }
    final occurrences = <TajweedOccurrence>[];
    for (final occurrence in rawOccurrences) {
      final rawParts = occurrence is Map ? occurrence['parts'] : null;
      if (rawParts is! List || rawParts.isEmpty) return null;
      final parts = <TajweedOccurrencePart>[];
      for (final part in rawParts) {
        if (part is! Map ||
            part['position'] is! int ||
            part['start'] is! int ||
            part['end'] is! int) {
          return null;
        }
        parts.add((
          position: part['position'] as int,
          start: part['start'] as int,
          end: part['end'] as int,
        ));
      }
      final variant = (occurrence as Map)['variant'];
      occurrences.add(
        TajweedOccurrence(
          parts: parts,
          variant: variant is String ? variant : null,
        ),
      );
    }
    return TajweedCourseExample(
      surah: surah,
      ayah: ayah,
      page: value['page_number'] is int ? value['page_number'] as int : 0,
      words: words,
      occurrences: occurrences,
    );
  }
}

/// A page of lesson examples; examples that do not fit are dropped.
@immutable
class TajweedExamplesPage {
  const TajweedExamplesPage({
    required this.offset,
    required this.nextOffset,
    required this.examples,
  });

  factory TajweedExamplesPage.fromJson(Object? value) {
    if (value is! Map || value['examples'] is! List) {
      return const TajweedExamplesPage(
        offset: 0,
        nextOffset: null,
        examples: [],
      );
    }
    return TajweedExamplesPage(
      offset: value['offset'] is int ? value['offset'] as int : 0,
      nextOffset: value['next_offset'] is int
          ? value['next_offset'] as int
          : null,
      examples: [
        for (final item in value['examples'] as List)
          ?TajweedCourseExample.tryParse(item),
      ],
    );
  }

  final int offset;

  /// Null when there are no more examples.
  final int? nextOffset;
  final List<TajweedCourseExample> examples;
}

/// Step slugs of a lesson with [shown] examples to read and, maybe, the
/// «find the rule» exercise. `example-1` is there even before the examples
/// arrive: it shows their loading.
List<String> tajweedLessonStepSlugs(int shown, {required bool find}) => [
  'intro',
  'how',
  for (var index = 1; index <= (shown < 1 ? 1 : shown); index++)
    'example-$index',
  if (find) 'find',
];

/// The first page of examples: all but the last are read, the last is found.
/// A single example is only read.
({List<TajweedCourseExample> shown, TajweedCourseExample? find})
splitFirstTajweedExamples(List<TajweedCourseExample> examples) =>
    examples.length < 2
    ? (shown: [...examples], find: null)
    : (shown: examples.sublist(0, examples.length - 1), find: examples.last);

/// `[start, end)` of an occurrence in the reciter's track, from its first
/// word's start to its last word's end; null when one is not timed.
({Duration start, Duration end})? tajweedOccurrenceTiming(
  Map<int, ({Duration start, Duration end})> words,
  TajweedOccurrence occurrence,
) {
  final positions = occurrence.positions;
  if (positions.isEmpty) return null;
  final first = words[positions.first];
  final last = words[positions.last];
  return first == null || last == null || last.end <= first.start
      ? null
      : (start: first.start, end: last.end);
}

Map<String, Object?> _map(Object? value, String where) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('Tajweed course $where is not an object');
}

List<Object?> _list(Object? value, String where) {
  if (value is List) return List<Object?>.from(value);
  throw FormatException('Tajweed course $where is not a list');
}

String _text(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Tajweed course field "$key" is not a string');
  }
  return value;
}
